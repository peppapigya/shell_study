#!/bin/bash

set -euo pipefail
declare  -r SSH_KEY_DIR="/root/.ssh/"
declare -r SSH_KEY_TYPE="rsa"
declare -r SSH_KEY_FILE_NAME="id_rsa"
declare -r SSH_KEY_PASSWORD="Wjk990921"
declare -r HOST_PORT="22"

declare -r IMAGE_REPOSITORY="registry.aliyuncs.com/google_containers"
declare -r CIDR="10.100.0.0/24"
declare -r k8s_version="1.23.6"
declare  -r MASTER_IP="10.0.0.175"
declare -a -r HOSTS=(
  "10.0.0.175"
  "10.0.0.176"
  "10.0.0.177"
)

prepare() {
  # 1. 关闭防火墙
  systemctl stop firewalld
  systemctl disable firewalld

  # 2. 关闭selinux
  sed -i 's/enforcing/disabled/g' /etc/selinux/config
  # 3. 配置ip转发
  echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
  sysctl -p
  #4. 关闭swap
  swapoff -a
  sed -i '/swap/d' /etc/fstab

  # 5. 配置hosts
  sed -E -i  '/^10.0.0.175|^10.0.0.176|^10.0.0.177/d' /etc/hosts
  cat >> /etc/hosts << EOF
10.0.0.175 k8s-master
10.0.0.176 k8s-node1
10.0.0.177 k8s-node2
EOF
  # 6. 将桥接的IPV4的流量交给iptables处理
   tee /etc/modules-load.d/k8s.conf << EOF
  net.bridge.bridge-nf-call-ip6tables = 1
  net.bridge.bridge-nf-call-iptables = 1
EOF
  # 使配置生效
  sysctl --system
  # 7. 时间同步
  if ! which ntpdate; then
    yum install -y ntpdate
  fi
  ntpdate -u ntp.aliyun.com

  echo "*/3 * * * * /sbin/ntpdate ntp.aliyun.com  >/dev/null  2>&1" >> /var/spool/cron/root
  # 8. 添加阿里云yum源仓库
  tee /etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF
  #10.  关闭docker 默认的cgroup驱动，如果不修改的话会导致kubelet启动失败，缺少参数
  # 错误信息12月 15 20:41:33 k8s-master kubelet[58688]: E1215 20:41:33.456611   58688 server.go:302] "Failed to run kubelet" err="failed to run Kubelet: misconfiguration: kubelet cgroup driver: \"systemd\" is different from docker cgroup driver: \"cgroupfs\""
  tee /etc/docker/daemon.json << EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "registry-mirrors": [
          "https://docker.1panel.live"
        ]
}
EOF
  systemctl daemon-reload
  systemctl restart docker
  # 11. 安装kubernetes
  yum install -y kubelet-1.23.6 kubeadm-1.23.6 kubectl-1.23.6
  systemctl enbale  kubelet

  # 12.配置kubectl自动补全
  yum istall -y bash-completion
  kubectl completion bash |  tee /etc/bash_completion.d/kubelet > /dev/null
  source /usr/share/bash-completion/bash_completion

}

# 初始化master节点
master_init() {
  #1. 初始化主节点
  kubeadm init \
         --image-repository ${IMAGE_REPOSITORY} \
         --kubernetes-version ${k8s_version} \
         --pod-network-cidr=${CIDR} \
         --apiserver-advertise-address=${MASTER_IP}
  #2. 初始化之后的操作
  mkdir -p "${HOME}"/.kube
  cp -i /etc/kubernetes/admin.conf "${HOME}"/.kube/config
  # shellcheck disable=SC2046
  chown $(id -u):$(id -g) "${HOME}"/.kube/config
  if kubectl get nodes; then
    echo "初始化成功..."
  esle
    echo "初始化失败..."
    exit 1
  fi

}

# 生成ssh秘钥
generate_ssh_key() {
  echo "生成ssh秘钥..."
  [ -f "${SSH_KEY_DIR}/${SSH_KEY_FILE_NAME}" ] && return

  ssh-keygen -t "${SSH_KEY_TYPE}"  -f "${SSH_KEY_DIR}/${SSH_KEY_FILE_NAME}" -P '' > /dev/null 2>&1
}

# 分发ssh秘钥
distribute_ssh_key() {
  echo "分发ssh秘钥..."
  for host in "${HOSTS[@]}"; do
    if [[ ${host} == "${MASTER_IP}" ]]; then
      continue
    fi
    echo "分发到${host}..."
    sshpass -p "${SSH_KEY_PASSWORD}" ssh-copy-id -i "${SSH_KEY_DIR}/${SSH_KEY_FILE_NAME}" -p "${HOST_PORT}" root@${host} > /dev/null 2>&1
  done
  echo "分发完成..."
}

# 添加slave节点
add_slave() {
  # 获取token
  if [[ $(kubeadm token list | wc -l ) -le 1 ]]; then
    kubeadm token create --print-join-command > /tmp/join.sh
  fi
  token=$(kubeadm token list | awk 'NR==2{print $1}')
  hashCode=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')
  # 加入到集群当中
  for host in "${HOSTS[@]}"; do
    # 跳过master节点
    if [[ ${host} == "${MASTER_IP}" ]]; then
      continue
    fi
    ssh "${host}" "kubeadm join --token ${token} 10.0.0.175:6443 --discovery-token-ca-cert-hash sha256:${hashCode}"
  done
  if $(kubectl get nodes | wc -l) -gt ${#HOSTS[@]}; then
    echo "添加节点成功..."
  else
    echo "添加节点失败..."
    exit 1
  fi
}

# 部署网络CNI插件，使节点之间可以通信
deploy_network() {
  kubectl get componentstatus
  kubectl get pods  -n kube-system | grep -i  "pending"
  # 1. 下载对应的文件
  mkdir -p /opt/k8s && curl https://docs.projectcalico.org/manifests/calico.yaml -o /opt/k8s/calico.yaml
  cp /opt/k8s/calico.yaml /opt/k8s/calico.yaml.bak
  # 2. 修改CALICO_IPV4POOL_CIDR
  sed -i "/# - name: CALICO_IPV4POOL_CIDR/,/#   value:/s/# - name: CALICO_IPV4POOL_CIDR/- name: CALICO_IPV4POOL_CIDR/" /opt/k8s/calico.yaml
  sed -i "/- name: CALICO_IPV4POOL_CIDR/,/value:/s/#*  value: \".*\"/   value: \"${CIDR}\"/" calico.yaml
  # 替换docker.io
  sed -i 's#docker.io/#docker.m.daocloud.io/#g' /opt/k8s/calico.yaml

  #3. 启动 网络
   kubectl apply  -f /opt/k8s/calico.yaml
  # 4.测试启动一个容器
  kubectl create deployment nginx --image=nginx
  kubectl expose deployment nginx --port=80 --type=NodePort
}

# 配置子节点可以使用kubectl
config_kubectl() {
  echo "配置子节点可以使用kubectl..."
  for host in "${HOSTS[@]}"; do
    if [[ ${host} == "${MASTER_IP}" ]]; then
      continue
    fi
    echo "配置${host}..."
    scp /etc/kubernetes/admin.conf root@"${host}":/etc/kubernetes/
    echo "KUBECONFIG=/etc/kubernetes/admin.conf" >> ~/.bash_profile
    # shellcheck disable=SC1090
    source ~/.bash_profile
  done
}

main() {
  prepare
  distribute_ssh_key
  master_init
  add_slave
  deploy_network
  config_kubectl
}
main
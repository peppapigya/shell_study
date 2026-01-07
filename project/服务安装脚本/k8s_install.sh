#!/bin/bash
: '
author: peppa-pig
date: 2022-01-05
description: k8s集群安装脚本 目前只适用麒麟或者centos系列
本脚本不提供docker环境安装
'

# 解决初始化/etc/bashrc文件的时候报错问题
# shellcheck disable=SC2121
set BASHRCSOURCED=Y
set -eo pipefail
declare  -r SSH_KEY_DIR="/root/.ssh/"
declare -r SSH_KEY_TYPE="rsa"
declare -r SSH_KEY_FILE_NAME="id_rsa"
declare -r SSH_KEY_PASSWORD="Wjk990921"
declare -r HOST_PORT="22"
# 没有指定默认是k8s-master
declare MASTER_NAME=""
declare SLAVE_NAME_PREFIX="k8s-node-"
declare -r IMAGE_REPOSITORY="registry.aliyuncs.com/google_containers"
declare -r CIDR="10.100.0.0/24"
declare -r k8s_version="1.23.6"
declare  -r MASTER_IP="10.0.0.178"
declare -a -r HOSTS=(
  "10.0.0.178"
  "10.0.0.179"
  "10.0.0.180"
)
declare CNI="calico"
# 最大重试次数
declare -r MAX_FAILED_SHOULD=5
#最大超时时间
declare -r MAX_TIMEOUT=300

prepare() {
  # 1. 系统优化
  system_environment_prepare
  # 2. 时间同步
  if ! which ntpdate; then
    yum install -y ntpdate
  fi
  ntpdate -u ntp.aliyun.com

  echo "*/3 * * * * /sbin/ntpdate ntp.aliyun.com  >/dev/null  2>&1" >> /var/spool/cron/root
  # 3. 添加阿里云yum源仓库
  tee /etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF
  #4.  关闭docker 默认的cgroup驱动，如果不修改的话会导致kubelet启动失败，缺少参数
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
  # 5. 安装kubernetes
  yum install -y kubelet-1.23.6 kubeadm-1.23.6 kubectl-1.23.6

  systemctl enable  kubelet

  # 6.配置kubectl自动补全
  yum install -y bash-completion
  kubectl completion bash |  tee /etc/bash_completion.d/kubelet > /dev/null
  source /usr/share/bash-completion/bash_completion

}
# 系统环境准备
system_environment_prepare() {
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
 for (( i=0;i<${#HOSTS[@]};i++ )); do
   if [[ ${HOSTS[${i}]} == "${MASTER_IP}" ]]; then
     continue
   fi
   sed -i "/^${HOSTS[${i}]}/d" /etc/hosts
   echo "${HOSTS[${i}]} ${SLAVE_NAME_PREFIX}${i}" >> /etc/hosts
 done
  # 6. 将桥接的IPV4的流量交给iptables处理
   tee /etc/modules-load.d/k8s.conf << EOF
  net.bridge.bridge-nf-call-ip6tables = 1
  net.bridge.bridge-nf-call-iptables = 1
EOF
  # 7. 内核优化
  cat > /etc/sysctl.d/k8s.conf <<'EOF'
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv6.conf.all.disable_ipv6 = 1
fs.may_detach_mounts = 1
vm.overcommit_memory=1
vm.panic_on_oom=0
fs.inotify.max_user_watches=89100
fs.file-max=52706963
fs.nr_open=52706963
net.netfilter.nf_conntrack_max=2310720
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl =15
net.ipv4.tcp_max_tw_buckets = 36000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_orphans = 327680
net.ipv4.tcp_orphan_retries = 3
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.ip_conntrack_max = 65536
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.tcp_timestamps = 0
net.core.somaxconn = 16384
EOF
  sysctl --system

  # 安装ipvs，默认的iptables不能满足k8s的网络要求
  yum install ipvsadm ipset sysstat conntrack

  # 所有节点创建要开机自动加载的模块配置文件
  cat > /etc/modules-load.d/ipvs.conf << 'EOF'
ip_vs
ip_vs_lc
ip_vs_wlc
ip_vs_rr
ip_vs_wrr
ip_vs_lblc
ip_vs_lblcr
ip_vs_dh
ip_vs_sh
ip_vs_fo
ip_vs_nq
ip_vs_sed
ip_vs_ftp
ip_vs_sh
nf_conntrack
ip_tables
ip_set
xt_set
ipt_set
ipt_rpfilter
ipt_REJECT
ipip
EOF
}


# 在所有节点准备环境
prepare_all_nodes() {
  echo "开始在 master 节点准备环境..."
  prepare

  echo "开始在工作节点准备环境..."
  for host in "${HOSTS[@]}"; do
    if [[ "${host}" == "${MASTER_IP}" ]]; then
      continue
    fi

    echo "在节点 ${host} 上准备环境..."

    # 方法1: 直接通过 SSH 执行脚本
    ssh root@${host} << 'EOF'
#!/bin/bash
set -euo pipefail

# 定义准备函数
prepare_remote() {
  # 1. 系统优化
  systemctl stop firewalld 2>/dev/null || true
  systemctl disable firewalld 2>/dev/null || true
  sed -i 's/enforcing/disabled/g' /etc/selinux/config
  setenforce 0 2>/dev/null || true

  echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
  sysctl -p

  swapoff -a
  sed -i '/swap/d' /etc/fstab

  # 时间同步
  if ! which ntpdate; then
    yum install -y ntpdate
  fi
  ntpdate -u ntp.aliyun.com
  echo "*/3 * * * * /sbin/ntpdate ntp.aliyun.com >/dev/null 2>&1" >> /var/spool/cron/root

  # 添加阿里云yum源
  tee /etc/yum.repos.d/kubernetes.repo << K8S_EOF
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
K8S_EOF

  # 配置Docker
  tee /etc/docker/daemon.json << DOCKER_EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "registry-mirrors": ["https://docker.1panel.live"]
}
DOCKER_EOF
systemctl restart docker
  # 安装Kubernetes
  yum install -y kubelet-1.23.6 kubeadm-1.23.6 kubectl-1.23.6
  yum install -y bash-completion
  systemctl enable kubelet

  # 内核优化
  cat > /etc/sysctl.d/k8s.conf << 'SYSCTL_EOF'
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv6.conf.all.disable_ipv6 = 1
fs.may_detach_mounts = 1
vm.overcommit_memory=1
vm.panic_on_oom=0
fs.inotify.max_user_watches=89100
fs.file-max=52706963
fs.nr_open=52706963
net.netfilter.nf_conntrack_max=2310720
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl =15
net.ipv4.tcp_max_tw_buckets = 36000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_orphans = 327680
net.ipv4.tcp_orphan_retries = 3
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.ip_conntrack_max = 65536
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.tcp_timestamps = 0
net.core.somaxconn = 16384
SYSCTL_EOF
  sysctl --system

  # 安装IPVS
  yum install -y ipvsadm ipset sysstat conntrack

  cat > /etc/modules-load.d/ipvs.conf << 'IPVS_EOF'
ip_vs
ip_vs_lc
ip_vs_wlc
ip_vs_rr
ip_vs_wrr
ip_vs_lblc
ip_vs_lblcr
ip_vs_dh
ip_vs_sh
ip_vs_fo
ip_vs_nq
ip_vs_sed
ip_vs_ftp
ip_vs_sh
nf_conntrack
ip_tables
ip_set
xt_set
ipt_set
ipt_rpfilter
ipt_REJECT
ipip
IPVS_EOF

  systemctl restart systemd-modules-load.service
}

# 执行准备
prepare_remote
EOF

    if [ $? -eq 0 ]; then
      echo "节点 ${host} 环境准备完成"
    else
      echo "节点 ${host} 环境准备失败"
    fi
  done

  echo "所有节点环境准备完成"
  sleep 2
}
# 初始化master节点
master_init() {
  kubeadm reset -f
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
  else
    echo "初始化失败..."
    exit 1
  fi

}

# 生成ssh秘钥
generate_ssh_key() {
  echo "生成ssh秘钥..."
  [ -f "${SSH_KEY_DIR}${SSH_KEY_FILE_NAME}" ] && return

  ssh-keygen -t "${SSH_KEY_TYPE}"  -f "${SSH_KEY_DIR}${SSH_KEY_FILE_NAME}" -P '' > /dev/null 2>&1
}

# 分发ssh秘钥
distribute_ssh_key() {
    yum install -y epel-release sshpass --skip-broken
  echo "分发ssh秘钥..."
  for host in "${HOSTS[@]}"; do
    if [[ ${host} == "${MASTER_IP}" ]]; then
      continue
    fi
    echo "分发到${host}..."
    sshpass -p "${SSH_KEY_PASSWORD}" ssh-copy-id -i "${SSH_KEY_DIR}${SSH_KEY_FILE_NAME}" \
     -p "${HOST_PORT}" -o "StrictHostKeyChecking=no"  root@"${host}"
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
    echo "${host}:加入到集群当中..."
    ssh "${host}" "kubeadm join --token ${token} ${MASTER_IP}:6443 --discovery-token-ca-cert-hash sha256:${hashCode}"
  done
  node_count=$(kubectl get nodes 2>/dev/null | tail -n +2 | wc -l)
  # shellcheck disable=SC2181
  if [ $? -eq 0 ] && [ "${node_count}" -ge ${#HOSTS[@]} ] ; then
    echo "添加节点成功..."
    kubectl get nodes
  else
    echo "添加节点失败..."
    exit 1
  fi
}

# 部署网络CNI插件，使节点之间可以通信
deploy_network() {
  # todo 后续支持flannel网络插件
  # 安装网络calico插件
  kubectl get componentstatus
  kubectl get pods  -n kube-system | grep -i  "pending"
  # 1. 下载对应的文件
  mkdir -p /opt/k8s && curl https://calico-v3-25.netlify.app/archive/v3.25/manifests/calico.yaml -o /opt/k8s/calico.yaml
  cp /opt/k8s/calico.yaml /opt/k8s/calico.yaml.bak
  # 2. 修改CALICO_IPV4POOL_CIDR
  sed -i "/# - name: CALICO_IPV4POOL_CIDR/,/#   value:/s/# - name: CALICO_IPV4POOL_CIDR/- name: CALICO_IPV4POOL_CIDR/" /opt/k8s/calico.yaml
  sed -i "/- name: CALICO_IPV4POOL_CIDR/,/value:/s@#*  value: \".*\"@   value: \"${CIDR}\"@" /opt/k8s/calico.yaml
  # 替换docker.io
  sed -i 's#docker.io/#docker.m.daocloud.io/#g' /opt/k8s/calico.yaml
  #3. 启动 网络
   kubectl apply  -f /opt/k8s/calico.yaml
   local count=0
   # 循环检查pod是否准备完毕
   echo "等待网络插件就绪..."
   while true; do
    if [ "${count}" -ge "${MAX_FAILED_SHOULD}" ]; then
      echo "超过最大失败次数，请检查网络..."
      exit 1
    fi
     kubectl wait --for=condition=Ready pods -l "k8s-app in (calico-node,calico-kube-controllers)" -n kube-system --timeout="${MAX_TIMEOUT}s"
     if [ ! $? -eq 0 ]; then
       echo "超过超时时间，正在重试..."
    fi
    ((count++))
   done
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
  echo "配置完成..."
}

main() {
  generate_ssh_key
  distribute_ssh_key
  prepare_all_nodes

  master_init
  add_slave
  deploy_network
  config_kubectl
  echo "集群搭建完成..."
}
main
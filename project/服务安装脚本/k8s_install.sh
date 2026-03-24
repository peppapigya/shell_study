#!/bin/bash
: '
author: peppa-pig
date: 2022-01-05 (Updated and fixed)
description: k8s集群安装脚本，目前适用 麒麟/CentOS 系列 和 Ubuntu/Debian 系列
说明：
1. 本脚本不提供docker环境安装，默认机器已安装 Docker
2. 已修复 Ubuntu 上 kubeadm init 报错：
   /proc/sys/net/bridge/bridge-nf-call-iptables does not exist
3. 已忽略 Docker 版本过高的 warning，不额外处理
'
# 解决初始化/etc/bashrc文件的时候报错问题
# shellcheck disable=SC2121
set BASHRCSOURCED=Y
set -eo pipefail
export DEBIAN_FRONTEND=noninteractive
declare -r SSH_KEY_DIR="/root/.ssh/"
declare -r SSH_KEY_TYPE="rsa"
declare -r SSH_KEY_FILE_NAME="id_rsa"
declare -r SSH_KEY_PASSWORD="1"
declare -r HOST_PORT="22"
# 没有指定默认是k8s-master
declare MASTER_NAME="k8s-master"
declare SLAVE_NAME_PREFIX="k8s-node"
declare -r IMAGE_REPOSITORY="registry.aliyuncs.com/google_containers"
declare -r CIDR="192.168.0.0/16"
declare -r k8s_version="1.23.6"
declare -r MASTER_IP="192.168.31.20"
declare -a -r HOSTS=(
  "192.168.31.20"
  "192.168.31.21"
  "192.168.31.22"
)
declare CNI="calico"
# 最大重试次数
declare -r MAX_FAILED_SHOULD=5
# 最大超时时间
declare -r MAX_TIMEOUT=300
# 检测操作系统类型
detect_os() {
  if grep -Eqi "CentOS|Kylin|Red Hat|AlmaLinux|Rocky" /etc/issue 2>/dev/null || grep -Eqi "CentOS|Kylin|Red Hat|AlmaLinux|Rocky" /etc/*-release 2>/dev/null; then
    echo "centos"
  elif grep -Eqi "Ubuntu|Debian" /etc/issue 2>/dev/null || grep -Eqi "Ubuntu|Debian" /etc/*-release 2>/dev/null; then
    echo "ubuntu"
  else
    echo "unknown"
  fi
}
declare -r OS_TYPE=$(detect_os)
prepare() {
  # 1. 系统优化
  system_environment_prepare
  # 2. 时间同步
  if [ "${OS_TYPE}" == "ubuntu" ]; then
    apt-get update -y
    if ! command -v ntpdate >/dev/null 2>&1; then
      apt-get install -y ntpdate
    fi
  else
    if ! command -v ntpdate >/dev/null 2>&1; then
      yum install -y ntpdate
    fi
  fi
  ntpdate -u ntp.aliyun.com || true
  # 配置定时任务路径兼容
  local cron_file="/var/spool/cron/root"
  [ "${OS_TYPE}" == "ubuntu" ] && cron_file="/var/spool/cron/crontabs/root"
  mkdir -p "$(dirname "${cron_file}")"
  touch "${cron_file}"
  grep -q "ntp.aliyun.com" "${cron_file}" 2>/dev/null || \
    echo "*/3 * * * * $(which ntpdate) ntp.aliyun.com >/dev/null 2>&1" >> "${cron_file}"
  if [ "${OS_TYPE}" == "ubuntu" ]; then
    chmod 600 "${cron_file}" || true
  fi
  # 3. 添加yum源/apt源仓库
  if [ "${OS_TYPE}" == "ubuntu" ]; then
    apt-get install -y apt-transport-https ca-certificates curl gnupg
    curl -fsSL https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | apt-key add - 2>/dev/null || true
    cat > /etc/apt/sources.list.d/kubernetes.list << EOF
deb https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main
EOF
    apt-get update -y
  else
    cat > /etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=0
repo_gpgcheck=0
EOF
  fi
  # 4. 关闭docker默认的cgroup驱动差异
  mkdir -p /etc/docker
  cat > /etc/docker/daemon.json << EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "registry-mirrors": [
    "https://docker.1panel.live"
  ]
}
EOF
  systemctl daemon-reload
  systemctl restart docker || true
  # 5. 安装kubernetes
  if [ "${OS_TYPE}" == "ubuntu" ]; then
    apt-get install -y kubelet="${k8s_version}-00" kubeadm="${k8s_version}-00" kubectl="${k8s_version}-00" bash-completion
    apt-mark hold kubelet kubeadm kubectl
  else
    yum install -y kubelet-"${k8s_version}" kubeadm-"${k8s_version}" kubectl-"${k8s_version}" bash-completion
  fi
  systemctl enable kubelet
  systemctl restart kubelet || true
  # 6. kubectl自动补全
  mkdir -p /etc/bash_completion.d
  kubectl completion bash > /etc/bash_completion.d/kubectl || true
  source /usr/share/bash-completion/bash_completion 2>/dev/null || true
}
# 系统环境准备
system_environment_prepare() {
  # 1. 关闭防火墙
  if [ "${OS_TYPE}" == "ubuntu" ]; then
    ufw disable || true
    systemctl stop ufw 2>/dev/null || true
    systemctl disable ufw 2>/dev/null || true
  else
    systemctl stop firewalld 2>/dev/null || true
    systemctl disable firewalld 2>/dev/null || true
  fi
  # 2. 关闭selinux
  if [ -f /etc/selinux/config ]; then
    sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config || true
  fi
  setenforce 0 2>/dev/null || true
  # 3. 关闭swap
  swapoff -a
  sed -ri '/\sswap\s/s/^#?/#/' /etc/fstab || true
  # 4. 配置hosts
  sed -i "/${MASTER_IP}/d" /etc/hosts
  echo "${MASTER_IP} ${MASTER_NAME}" >> /etc/hosts
  for (( i=0; i<${#HOSTS[@]}; i++ )); do
    if [[ "${HOSTS[$i]}" == "${MASTER_IP}" ]]; then
      continue
    fi
    sed -i "/^${HOSTS[$i]}\s/d" /etc/hosts
    echo "${HOSTS[$i]} ${SLAVE_NAME_PREFIX}${i}" >> /etc/hosts
  done
  # 5. 加载内核模块（修复关键点）
  cat > /etc/modules-load.d/k8s.conf << EOF
br_netfilter
overlay
EOF
  modprobe br_netfilter || true
  modprobe overlay || true
  # 6. 内核优化
  cat > /etc/sysctl.d/k8s.conf <<'EOF'
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv6.conf.all.disable_ipv6 = 1
fs.may_detach_mounts = 1
vm.overcommit_memory = 1
vm.panic_on_oom = 0
fs.inotify.max_user_watches = 89100
fs.file-max = 52706963
fs.nr_open = 52706963
net.netfilter.nf_conntrack_max = 2310720
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_max_tw_buckets = 36000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_orphans = 327680
net.ipv4.tcp_orphan_retries = 3
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.ip_conntrack_max = 65536
net.ipv4.tcp_timestamps = 0
net.core.somaxconn = 16384
EOF
  sysctl --system || true
  # 7. 安装ipvs相关工具
  if [ "${OS_TYPE}" == "ubuntu" ]; then
    apt-get update -y
    apt-get install -y ipvsadm ipset sysstat conntrack
  else
    yum install -y ipvsadm ipset sysstat conntrack
  fi
  # 8. 所有节点创建开机自动加载模块配置文件
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
nf_conntrack
ip_tables
ip_set
xt_set
ipt_set
ipt_rpfilter
ipt_REJECT
ipip
EOF
  modprobe ip_vs || true
  modprobe ip_vs_rr || true
  modprobe ip_vs_wrr || true
  modprobe ip_vs_sh || true
  modprobe nf_conntrack || true
  systemctl restart systemd-modules-load.service || true
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
    ssh -o StrictHostKeyChecking=no root@"${host}" << 'EOF'
#!/bin/bash
set -eo pipefail
export DEBIAN_FRONTEND=noninteractive
K8S_VER="1.23.6"
MASTER_IP="192.168.31.20"
MASTER_NAME="k8s-master"
detect_remote_os() {
  if grep -Eqi "CentOS|Kylin|Red Hat|AlmaLinux|Rocky" /etc/issue 2>/dev/null || grep -Eqi "CentOS|Kylin|Red Hat|AlmaLinux|Rocky" /etc/*-release 2>/dev/null; then
    echo "centos"
  elif grep -Eqi "Ubuntu|Debian" /etc/issue 2>/dev/null || grep -Eqi "Ubuntu|Debian" /etc/*-release 2>/dev/null; then
    echo "ubuntu"
  else
    echo "unknown"
  fi
}
REMOTE_OS=$(detect_remote_os)
prepare_remote() {
  # 1. 防火墙和SELinux
  if [ "${REMOTE_OS}" == "ubuntu" ]; then
    ufw disable || true
    systemctl stop ufw 2>/dev/null || true
    systemctl disable ufw 2>/dev/null || true
  else
    systemctl stop firewalld 2>/dev/null || true
    systemctl disable firewalld 2>/dev/null || true
  fi
  if [ -f /etc/selinux/config ]; then
    sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config || true
  fi
  setenforce 0 2>/dev/null || true
  # 2. swap
  swapoff -a
  sed -ri '/\sswap\s/s/^#?/#/' /etc/fstab || true
  # 3. hosts
  grep -q "${MASTER_IP} ${MASTER_NAME}" /etc/hosts || echo "${MASTER_IP} ${MASTER_NAME}" >> /etc/hosts
  # 4. 加载内核模块（修复关键点）
  cat > /etc/modules-load.d/k8s.conf << MOD_EOF
br_netfilter
overlay
MOD_EOF
  modprobe br_netfilter || true
  modprobe overlay || true
  # 5. sysctl
  cat > /etc/sysctl.d/k8s.conf << 'SYSCTL_EOF'
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv6.conf.all.disable_ipv6 = 1
fs.may_detach_mounts = 1
vm.overcommit_memory = 1
vm.panic_on_oom = 0
fs.inotify.max_user_watches = 89100
fs.file-max = 52706963
fs.nr_open = 52706963
net.netfilter.nf_conntrack_max = 2310720
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_max_tw_buckets = 36000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_orphans = 327680
net.ipv4.tcp_orphan_retries = 3
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.ip_conntrack_max = 65536
net.ipv4.tcp_timestamps = 0
net.core.somaxconn = 16384
SYSCTL_EOF
  sysctl --system || true
  # 6. 时间同步
  if [ "${REMOTE_OS}" == "ubuntu" ]; then
    apt-get update -y
    if ! command -v ntpdate >/dev/null 2>&1; then
      apt-get install -y ntpdate
    fi
  else
    if ! command -v ntpdate >/dev/null 2>&1; then
      yum install -y ntpdate
    fi
  fi
  ntpdate -u ntp.aliyun.com || true
  CRON_FILE="/var/spool/cron/root"
  [ "${REMOTE_OS}" == "ubuntu" ] && CRON_FILE="/var/spool/cron/crontabs/root"
  mkdir -p "$(dirname "${CRON_FILE}")"
  touch "${CRON_FILE}"
  grep -q "ntp.aliyun.com" "${CRON_FILE}" 2>/dev/null || \
    echo "*/3 * * * * $(which ntpdate) ntp.aliyun.com >/dev/null 2>&1" >> "${CRON_FILE}"
  if [ "${REMOTE_OS}" == "ubuntu" ]; then
    chmod 600 "${CRON_FILE}" || true
  fi
  # 7. 添加源并安装K8S
  if [ "${REMOTE_OS}" == "ubuntu" ]; then
    apt-get install -y apt-transport-https ca-certificates curl gnupg
    curl -fsSL https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | apt-key add - 2>/dev/null || true
    cat > /etc/apt/sources.list.d/kubernetes.list << K8S_EOF
deb https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main
K8S_EOF
    apt-get update -y
  else
    cat > /etc/yum.repos.d/kubernetes.repo << K8S_EOF
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=0
repo_gpgcheck=0
K8S_EOF
  fi
  # 8. Docker配置
  mkdir -p /etc/docker
  cat > /etc/docker/daemon.json << DOCKER_EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "registry-mirrors": ["https://docker.1panel.live"]
}
DOCKER_EOF
  systemctl daemon-reload
  systemctl restart docker || true
  # 9. 安装Kubernetes
  if [ "${REMOTE_OS}" == "ubuntu" ]; then
    apt-get install -y kubelet="${K8S_VER}-00" kubeadm="${K8S_VER}-00" kubectl="${K8S_VER}-00" bash-completion
    apt-mark hold kubelet kubeadm kubectl
  else
    yum install -y kubelet-"${K8S_VER}" kubeadm-"${K8S_VER}" kubectl-"${K8S_VER}" bash-completion
  fi
  systemctl enable kubelet
  systemctl restart kubelet || true
  # 10. 安装IPVS
  if [ "${REMOTE_OS}" == "ubuntu" ]; then
    apt-get install -y ipvsadm ipset sysstat conntrack
  else
    yum install -y ipvsadm ipset sysstat conntrack
  fi
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
nf_conntrack
ip_tables
ip_set
xt_set
ipt_set
ipt_rpfilter
ipt_REJECT
ipip
IPVS_EOF
  modprobe ip_vs || true
  modprobe ip_vs_rr || true
  modprobe ip_vs_wrr || true
  modprobe ip_vs_sh || true
  modprobe nf_conntrack || true
  systemctl restart systemd-modules-load.service || true
}
prepare_remote
EOF
    if [ $? -eq 0 ]; then
      echo "节点 ${host} 环境准备完成"
    else
      echo "节点 ${host} 环境准备失败"
      exit 1
    fi
  done
  echo "所有节点环境准备完成"
  sleep 2
}
# 初始化master节点
master_init() {
  kubeadm reset -f || true
  rm -rf /etc/cni/net.d || true
  ipvsadm --clear || true
  # 初始化主节点
  kubeadm init \
    --ignore-preflight-errors=SystemVerification \
    --image-repository "${IMAGE_REPOSITORY}" \
    --kubernetes-version "${k8s_version}" \
    --pod-network-cidr="${CIDR}" \
    --apiserver-advertise-address="${MASTER_IP}"
  # 初始化之后的操作
  mkdir -p "${HOME}/.kube"
  cp -f /etc/kubernetes/admin.conf "${HOME}/.kube/config"
  chown "$(id -u)":"$(id -g)" "${HOME}/.kube/config"
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
  mkdir -p "${SSH_KEY_DIR}"
  [ -f "${SSH_KEY_DIR}${SSH_KEY_FILE_NAME}" ] && return
  ssh-keygen -t "${SSH_KEY_TYPE}" -f "${SSH_KEY_DIR}${SSH_KEY_FILE_NAME}" -P '' > /dev/null 2>&1
}
# 分发ssh秘钥
distribute_ssh_key() {
  if [ "${OS_TYPE}" == "ubuntu" ]; then
    apt-get update -y
    apt-get install -y sshpass
  else
    yum install -y epel-release sshpass --skip-broken || yum install -y sshpass
  fi
  echo "分发ssh秘钥..."
  for host in "${HOSTS[@]}"; do
    if [[ "${host}" == "${MASTER_IP}" ]]; then
      continue
    fi
    echo "分发到 ${host} ..."
    sshpass -p "${SSH_KEY_PASSWORD}" ssh-copy-id \
      -i "${SSH_KEY_DIR}${SSH_KEY_FILE_NAME}" \
      -p "${HOST_PORT}" \
      -o "StrictHostKeyChecking=no" \
      root@"${host}"
  done
  echo "分发完成..."
}
# 添加slave节点
add_slave() {
  if [[ $(kubeadm token list | wc -l) -le 1 ]]; then
    kubeadm token create --print-join-command > /tmp/join.sh
  fi
  token=$(kubeadm token list | awk 'NR==2{print $1}')
  hashCode=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt \
    | openssl rsa -pubin -outform der 2>/dev/null \
    | openssl dgst -sha256 -hex \
    | sed 's/^.* //')
  for host in "${HOSTS[@]}"; do
    if [[ "${host}" == "${MASTER_IP}" ]]; then
      continue
    fi
    echo "${host}: 加入到集群当中..."
    ssh -o StrictHostKeyChecking=no root@"${host}" \
      "kubeadm reset -f >/dev/null 2>&1 || true; rm -rf /etc/cni/net.d || true; kubeadm join --token ${token} ${MASTER_IP}:6443 --discovery-token-ca-cert-hash sha256:${hashCode}"
  done
  sleep 5
  kubectl get nodes
  node_count=$(kubectl get nodes 2>/dev/null | tail -n +2 | wc -l)
  if [ "${node_count}" -ge "${#HOSTS[@]}" ]; then
    echo "添加节点成功..."
    kubectl get nodes
  else
    echo "添加节点失败..."
    exit 1
  fi
}
# 部署网络CNI插件，使节点之间可以通信
deploy_network() {
  kubectl get componentstatus || true
  kubectl get pods -n kube-system | grep -i "pending" || true
  mkdir -p /opt/k8s
  curl -sSL https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/calico.yaml -o /opt/k8s/calico.yaml
  cp /opt/k8s/calico.yaml /opt/k8s/calico.yaml.bak
  # 修改 CALICO_IPV4POOL_CIDR
  sed -i "/# - name: CALICO_IPV4POOL_CIDR/,/#   value:/s/# - name: CALICO_IPV4POOL_CIDR/- name: CALICO_IPV4POOL_CIDR/" /opt/k8s/calico.yaml
  sed -i "/- name: CALICO_IPV4POOL_CIDR/,/value:/s@#*  value: \".*\"@  value: \"${CIDR}\"@" /opt/k8s/calico.yaml
  # 替换 docker.io
  sed -i 's#docker.io/#docker.m.daocloud.io/#g' /opt/k8s/calico.yaml
  kubectl apply -f /opt/k8s/calico.yaml
  local count=0
  echo "等待网络插件就绪..."
  while true; do
    if [ "${count}" -ge "${MAX_FAILED_SHOULD}" ]; then
      echo "超过最大失败次数，请检查网络..."
      exit 1
    fi
    if kubectl wait --for=condition=Ready pod -l k8s-app=calico-node -n kube-system --timeout="${MAX_TIMEOUT}s" && \
       kubectl wait --for=condition=Ready pod -l k8s-app=calico-kube-controllers -n kube-system --timeout="${MAX_TIMEOUT}s"; then
      break
    else
      echo "超过超时时间，正在重试..."
    fi
    ((count++))
  done
  kubectl create deployment nginx --image=nginx || true
  kubectl expose deployment nginx --port=80 --type=NodePort || true
}
# 配置子节点可以使用kubectl
config_kubectl() {
  echo "配置子节点可以使用kubectl..."
  for host in "${HOSTS[@]}"; do
    if [[ "${host}" == "${MASTER_IP}" ]]; then
      continue
    fi
    echo "配置 ${host} ..."
    ssh root@"${host}" "mkdir -p /etc/kubernetes"
    scp /etc/kubernetes/admin.conf root@"${host}":/etc/kubernetes/
    ssh root@"${host}" "grep -q 'KUBECONFIG=' ~/.bash_profile 2>/dev/null || echo 'export KUBECONFIG=/etc/kubernetes/admin.conf' >> ~/.bash_profile"
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

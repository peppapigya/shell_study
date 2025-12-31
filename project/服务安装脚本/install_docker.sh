#!/bin/bash
set -aueo pipefail
: '
  本脚本用于安装docker
  仅适用于麒麟10,后续加上ubuntu的系统
'
declare -r YUM_REPO="/etc/yum.repos.d/docker-ce.repo"
# shellcheck disable=SC2155
declare -r DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/v2.40.3/docker-compose-linux-x86_64"


prepare() {
  echo "进行准备工作..."
  cat > ${YUM_REPO} << 'EOF'
[docker-ce-stable]
name=Docker CE Stable - $basearch
baseurl=https://download.docker.com/linux/centos/7/$basearch/stable
enabled=1
gpgcheck=1
gpgkey=https://download.docker.com/linux/centos/gpg
[docker-ce-stable-source]
name=Docker CE Stable - Sources
baseurl=https://download.docker.com/linux/centos/8/source/stable
enabled=0
gpgcheck=1
gpgkey=https://download.docker.com/linux/centos/gpg
[docker-ce-test]
name=Docker CE Test - $basearch
baseurl=https://download.docker.com/linux/centos/8/$basearch/test
enabled=0
gpgcheck=1
gpgkey=https://download.docker.com/linux/centos/gpg
[docker-ce-test-source]
name=Docker CE Test - Sources
baseurl=https://download.docker.com/linux/centos/8/source/test
enabled=0
gpgcheck=1
gpgkey=https://download.docker.com/linux/centos/gpg
EOF
  # 卸载所有的dokcer组件
  yum remove -y docker \
                  docker-client \
                  docker-client-latest \
                  docker-common \
                  docker-latest \
                  docker-latest-logrotate \
                  docker-logrotate \
                  docker-engine \
                  docker-runc
}
# 安装docker
install_docker() {
  sudo dnf install -y  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
  echo "docker 安装成功，版本信息为：$(docker --version)"
}
# 安装docker插件
install_docker_plugin() {
  echo "进行docker插件安装..."
  # 下载docker-compose
  echo "下载docker-compose..."
  curl -L "${DOCKER_COMPOSE_URL}" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
  echo "docker-compose 安装成功,版本为：$(docker-compose -v)"
}
main() {
  prepare
  install_docker
  install_docker_plugin
}

 main

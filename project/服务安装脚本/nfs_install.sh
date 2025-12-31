#!/bin/bash
set -aueEo pipefail
# 需要安装的所有服务
declare  -ra SERVICES=(
   "nfs-utils"
   "rpcbind"
)
# 获取操作系统信息
declare -r OS_INFO_FILE="/etc/os-release"
# nfs服务端配置所需变量
declare -r NFS_CONFIG_FILE="/etc/exports"
declare -r NFS_USER="nobody"
declare -r NFS_DATA_DIR="/nfsdata"
declare -r NFS_IP_CONFIG="172.16.1.0/24(rw,root_squash,sync,no_subtree_check,no_root_squash)"
# 初始化环境
init_env() {
  # shellcheck source=/etc/os-release
  [ -f "${OS_INFO_FILE}" ] &&  source "${OS_INFO_FILE}"
}

# 安装所需的服务
install_services() {
  case "${ID}" in
     centos | kylin | rhel | rocky | almalinux ):
     yum install -y "${SERVICES[*]}" >/dev/null 2>&1
     ;;
     ubuntu | debian | kali):
        apt update >/dev/null 2>&1
        apt install -y "${SERVICES[*]}" >/dev/null 2>&1
     ;;
     *)
       echo "不支持的操作系统"
       exit 1
     ;;
  esac
  echo "nfs服务已安装完成..."
  # 设置开机自启动并启动
  systemctl enable rpcbind >/dev/null 2>&1 && systemctl start rpcbind
  systemctl enable nfs >/dev/null 2>&1 && systemctl start nfs
  echo "nfs和rpcbind服务已启动..."
}
# 配置nfs服务端
server_config () {
  mkdir -p "${NFS_DATA_DIR}"
  chown -R "${NFS_USER}.${NFS_USER}" "${NFS_DATA_DIR}"

  echo "${NFS_DATA_DIR}  ${NFS_IP_CONFIG}" >> "${NFS_CONFIG_FILE}"

  systemctl reload nfs
}

main() {
  init_env
  install_services
  echo "配置nfs服务端配置..."
  server_config
}

main "$@"
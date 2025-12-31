#!/bin/bash
: '
  description: openssh秘钥生成和分发脚本
'
declare  -r SSH_KEY_DIR="/root/.ssh/"
declare -r SSH_KEY_TYPE="rsa"
declare -r SSH_KEY_FILE_NAME="id_rsa"


declare -r SSH_KEY_PASSWORD="Wjk990921"
declare -r HOST_PORT="22"
declare -ar SSH_DISTRIBUTE_HOSTS=(
    "10.0.0.193"
    "10.0.0.194"
    "10.0.0.195"
    "10.0.0.196"
)

# 生成ssh秘钥
generate_ssh_key() {
  echo "生成ssh秘钥..."
  [ -f "${SSH_KEY_DIR}/${SSH_KEY_FILE_NAME}" ] && return

  ssh-keygen -t "${SSH_KEY_TYPE}"  -f "${SSH_KEY_DIR}/${SSH_KEY_FILE_NAME}" -P '' > /dev/null 2>&1
}
# 分发ssh秘钥
distribute_ssh_key() {
  echo "分发ssh秘钥..."
  for host in "${SSH_DISTRIBUTE_HOSTS[@]}"; do
    echo "分发到${host}..."
    sshpass -p "${SSH_KEY_PASSWORD}" ssh-copy-id -i "${SSH_KEY_DIR}/${SSH_KEY_FILE_NAME}" -p "${HOST_PORT}" root@${host} > /dev/null 2>&1
  done
  echo "分发完成..."
}
main() {
  generate_ssh_key
  distribute_ssh_key
}

main "$@"
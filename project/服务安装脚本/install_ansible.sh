#!/bin/bash
: '
  auth: peppa-pig
  desc: 安装ansible
'
set -aeuo pipefail
declare  OS_NAME=""
declare  OS_RELEASE_FILE="/etc/os-release"

declare -r pip_url="https://bootstrap.pypa.io/pip/3.7/get-pip.py"

trap clean_up EXIT INT TERM
clean_up() {
  echo "正在进行数据清理..."
  [[ -f "get-pip.py" ]] && rm -f get-pip.py
  echo "数据清理完毕..."
}
get_base_info() {
  if [ ! -f "${OS_RELEASE_FILE}" ]; then
    exit 1
  fi
  # shellcheck disable=SC1090
  source "${OS_RELEASE_FILE}"
  OS_NAME="${ID}"
}
install_ansible() {
  if python3 -m pip -V >/dev/null; then
    python3 -m pip install ansible
  else
    curl  "${pip_url}" -o get-pip.py
    python3 get-pip.py
  fi

  pip3 config set global.index-url https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple

  # 安装ansible的包
  python3 -m pip install --user ansible

  # 添加自动补全功能
  python3 -m pip install  argcomplete
  # 全局配置
  activate-global-python-argcomplete --user

  # 测试
  if ansible --version >/dev/null; then
    echo "安装成功"
  else
    echo "安装失败"
  fi
}

main() {
  install_ansible
}

main
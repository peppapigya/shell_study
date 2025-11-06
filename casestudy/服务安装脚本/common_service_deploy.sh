#!/bin/bash

set -Eeou pipefail
trap clean_data  EXIT

trap after_update_openssh SIGTERM ERR SIGINT SIGHUP
new_openssh_dir="/usr/local/tools"
openssh_install_log="/var/log/openssh9.log"

# 通用安装软件方法
common_install_software(){
  if [ $# -le 0 ]; then
    echo "请输入要安装的软件"
    exit 1
  fi
 for i in "$@"
 do
  dpkg -l "${i}">/dev/null 2>&1 && echo "已安装${i}" && continue
  echo "正在安装$i..."
  if apt install -y "${i}" >/dev/null 2>&1;then
    echo "${i}安装成功"
  else
    echo "${i}安装失败"
  fi
 done
}

back_dir="/backup"
# 编辑配置文件
adit_source(){
  cd "${back_dir}" || mkdir -p "${back_dir}"
  # 备份文件
  cp -a /etc/apt/sources.list "${back_dir}"

  cat > /etc/apt/sources.list <<EOF
 deb https://mirrors.aliyun.com/ubuntu/ jammy main restricted universe multiverse
deb-src https://mirrors.aliyun.com/ubuntu/ jammy main restricted universe multiverse

deb https://mirrors.aliyun.com/ubuntu/ jammy-security main restricted universe multiverse
deb-src https://mirrors.aliyun.com/ubuntu/ jammy-security main restricted universe multiverse

deb https://mirrors.aliyun.com/ubuntu/ jammy-updates main restricted universe multiverse
deb-src https://mirrors.aliyun.com/ubuntu/ jammy-updates main restricted universe multiverse

# deb https://mirrors.aliyun.com/ubuntu/ jammy-proposed main restricted universe multiverse
# deb-src https://mirrors.aliyun.com/ubuntu/ jammy-proposed main restricted universe multiverse

deb https://mirrors.aliyun.com/ubuntu/ jammy-backports main restricted universe multiverse
deb-src https://mirrors.aliyun.com/ubuntu/ jammy-backports main restricted universe multiverse
EOF
   # 更新脚本信息
   apt update
}

# 准备工作
before_update_openssh() {
  # 安装telnet服务器，方便后期ssh不能连接了用telnet连接
  common_install_software "telnetd"

  systemctl start inetd
  local status=""
  if ss -lntup | grep -q "inetd" ; then
    echo "inetd服务已启动"
  else
    echo "inetd服务未启动"
    systemctl start inetd
    read -rn 1 -p "是否继续执行脚本" status
    if [[ "${status}" == "" || "${status}" == "n" ]]; then
      exit 1
    fi
  fi

  # 安装编译所需的基础工具包
  common_install_software "zlib1g-dev" "gcc" "build-essential" "make" "libssl-dev" "openssl" "pkg-config"
  if [ ! -d "${new_openssh_dir}" ]; then
    mkdir -p "${new_openssh_dir}"
  fi
}
update_openssh() {
  before_update_openssh
  cd /tmp  && \
  # 下载openssh包
  wget https://mirrors.aliyun.com/pub/OpenBSD/OpenSSH/portable/openssh-9.9p2.tar.gz
  tar -xzf openssh-9.9p2.tar.gz >>"${openssh_install_log}"
  cd openssh-9.9p2/ && \
  pwd
  ./configure --prefix=/usr/local/tools/openssh-9.9p2 >>/dev/null 2>&1 && echo "配置成功" >>"${openssh_install_log}" || echo "配置失败" >>"${openssh_install_log}" exit 1
  make -j "$(nproc)" >/dev/null 2>&1
  make install >/dev/null 2>&1 && echo "编译成功" >>"${openssh_install_log}" || echo "编译失败" >>"${openssh_install_log}"
  cd "${new_openssh_dir}" &&\
  # 创建软连接
  if [ -L "/usr/local/tools/openssh" ]; then
     ln -sfn /usr/local/tools/openssh-9.9p2  /usr/local/tools/openssh
  else
    ln -s /usr/local/tools/openssh-9.9p2  /usr/local/tools/openssh
  fi
  cp -a /usr/local/tools/openssh/etc/sshd_config "${back_dir}"
  sed -ri '/^Port/s/^#?(Port) +([0-9]+)/\1 52113/g' /usr/local/tools/openssh/etc/sshd_config

  # 配置环境变量
    echo "export PATH=/usr/local/tools/openssh/:/usr/local/tools/openssh/bin/:/usr/local/tools/openssh/sbin/:/usr/local/tools/openssh/libexec/:$PATH" >> /etc/profile
  source  /etc/profile
  # 将ssh服务交给systemd管理
  cp -a /lib/systemd/system/ssh.service /lib/systemd/system/sshd9.service
  sed -i  's#/usr/#/usr/local/tools/openssh/#g' /lib/systemd/system/sshd9.service
  systemctl daemon-reload

  systemctl start sshd9

  if systemctl start sshd9 >>/dev/null ;then
    echo "sshd9启动成功"
  else
    echo "sshd9启动失败"
    exit 1
  fi
}
## 安装tomcat
#install_tomcat(){
#
#}
after_update_openssh(){
  echo "正在进行数据恢复..."
  cp -a "${back_dir}/sources.list" /etc/apt/sources.list
  cp -a "${back_dir}/sshd_config" /usr/local/tools/openssh/etc/sshd_config
  echo "正在清除旧版openssh..."
  clean_data
  echo "清理完成"
}
clean_data(){
  echo "正在清理数据..."
  apt autoremove >/dev/null 2>&1
   rm -rf /tmp/openssh-9.9p2* >>/dev/null 2>&1
  echo "清理完成"
}


main() {
  adit_source
  common_install_software "nginx" "mysql-server"
  update_openssh
}


main "$@"



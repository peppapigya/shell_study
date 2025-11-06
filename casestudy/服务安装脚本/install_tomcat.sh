#!/bin/bash

set -Eeuo pipefail




# 定义我们全局需要安装的依赖包
declare -ar dependency_packages=(pv)
declare -r tools_dir="/usr/local/tools" package_dir="/tmp" backup_dir="/tmp/backup"
# 华为云，官方链接https://download.java.net/openjdk/jdk17.0.0.1/ri/openjdk-17.0.0.1+2_linux-x64_bin.tar.gz
jdk17_url="https://mirrors.huaweicloud.com/openjdk/17.0.1/openjdk-17.0.1_linux-x64_bin.tar.gz"
declare -r tomcat9_version_url="https://mirrors.tuna.tsinghua.edu.cn/apache/tomcat/tomcat-9/v9.0.109/bin/apache-tomcat-9.0.109.tar.gz"
declare -r  tomcat10_version_url="https://mirrors.tuna.tsinghua.edu.cn/apache/tomcat/tomcat-10/v10.1.48/bin/apache-tomcat-10.1.48.tar.gz"
declare -r tomcat11_version_url="https://mirrors.tuna.tsinghua.edu.cn/apache/tomcat/tomcat-11/v11.0.10/bin/apache-tomcat-11.0.10.tar.gz"
real_install_tomcat_name=""
JAVA_HOME=""
declare -i tomcat_version_num=1
OS_NAME=""
# 麒麟系统安装需要加入一下参数，后期将他移入只有麒麟系统才会去设置
USER_LS_COLORS=""
LC_ALL=""
BASHRCSOURCED='Y'
init() {
  . /etc/os-release
  OS_NAME=${ID}
}

# 安装基础依赖包
dependency_package_install() {
  echo "正在安装系统所需基础依赖包..."
  for package in "${dependency_packages[@]}"
  do
    case "${OS_NAME}" in
      kylin)
        yum install -y "${package}" > /dev/null 2>&1
        ;;
      ubuntu|debian)
       echo "正在安装系统依赖包${package}"
        apt install -y "${package}" > /dev/null 2>&1
        ;;
      *)
        echo "暂不支持该系统:${OS_NAME}"
        exit 1
    esac
  done
  echo "所有依赖包安装完成"
}

info_msg() {
cat<<EOF
  请选择要安装的Tomcat版本：
  1. Tomcat 11.0.x
  2. Tomcat 10.0.x
  3. Tomcat 9.0.x
EOF
  read -t 10 -rp "请输入选项：" tomcat_version_num
  tomcat_version_num=${tomcat_version_num:-1}
}
get_package(){
  cd "${package_dir}" &&\
  info_msg
  install_jdk
  echo "正在下载Tomcat安装包..."
  local real_install_tomcat_url=""
  case ${tomcat_version_num} in
    1)
      real_install_tomcat_url="${tomcat11_version_url}"
      wget "${tomcat11_version_url}"  2>&1 | pv -N "下载进度：" >> /dev/null 2>&1
      version=$(echo "${tomcat11_version_url}" | awk -F '/' '{print$6}')
      echo "已获取Tomcat安装包，版本为： ${version}"
      ;;
    2)
      real_install_tomcat_url="${tomcat10_version_url}"
      wget "${tomcat10_version_url}"  2>&1 | pv -N "下载进度：" >> /dev/null 2>&1
      version=$(echo "${tomcat10_version_url}" | awk -F '/' '{print$6}')
      echo "已获取Tomcat安装包，版本为： ${version}"
      ;;
    3)
      real_install_tomcat_url="${tomcat9_version_url}"
      wget "${tomcat9_version_url}"  2>&1 | pv -N "下载进度：" >> /dev/null 2>&1
      version=$(echo "${tomcat9_version_url}" | awk -F '/' '{print$6}')
      echo "已获取Tomcat安装包，版本为： ${version}"
      ;;
    *)
      echo "输入错误"
      exit 1
  esac
  real_install_tomcat_name=$(echo "${real_install_tomcat_url}" | sed -r 's#.*/##g')
}

install_jdk() {
  echo "正在安装jdk..."
  case ${OS_NAME} in
      kylin)
         yum_install_jdk17
        ;;
      ubuntu|debian)
          apt  update
          apt install -y openjdk-17-jdk 2>&1 | pv -N "下载进度：" >> /dev/null 2>&1
          java -version >>/dev/null 2>&1
        ;;
      *)
        echo "暂不支持该系统:${OS_NAME}"
        exit 1
  esac
  echo "jdk安装成功"
}
# yum去安装jdk17
yum_install_jdk17() {
  cd "${package_dir}" && \
  tar_name=$(echo "${jdk17_url}" | sed -r 's#.*/##g')
  [ ! -e "${tar_name}" ]&&{
    wget "${jdk17_url}"  2>&1 | pv -N "下载进度：" >> /dev/null 2>&1
  }

  [ -d "${tools_dir}" ] || mkdir  "${tools_dir}"
  tar_name=$(echo "${jdk17_url}" | sed -r 's#.*/##g')

  echo "正在解压压缩包..."
  # 解压jdk17x
  tar -zxvf "${tar_name}"  -C "${tools_dir}" >/dev/null 2>&1
  # 这里注意不是将.tar.gz去掉，而是将_linux-x64.tar.gz去掉才是解压后的
  jdk_dir_name=$(echo "${tar_name}" | sed -r 's#[_].*##g')
  echo "解压成功"
  cd "${tools_dir}" &&\
  ln -sfn "${tools_dir}/jdk-17.0.1" "${tools_dir}/java"

  [ -d ${backup_dir} ] || mkdir "${backup_dir}"
  cp -a "/etc/profile" "${backup_dir}/profile.bak"

  # todo 将原来的关于java相关的配置进行删除，然后在写入或者修改
  # 运行这个的时候PATH变量中有JAVA_HOME就会把PATH也给删除了
  sed -r '/JAVA_HOME/d' /etc/profile

  echo "export JAVA_HOME=${tools_dir}/java" >> /etc/profile
  echo "export PATH=\${JAVA_HOME}/bin:\$PATH" >> /etc/profile
  source /etc/profile &&\
  java -version
  JAVA_HOME="${tools_dir}/java"
}
# 配置tomcat之前的工作
before_config_tomcat() {
  [ -d "${tools_dir}" ] || mkdir "${tools_dir}"
  [ -n "${real_install_tomcat_name}" ] || false
  tar -xzvf "${real_install_tomcat_name}" -C "${tools_dir}" >/dev/null 2>&1
  tomcat_dir_name=$(echo "${real_install_tomcat_name}" | sed -r 's#.tar.gz##g')
  cd "${tools_dir}"
  ln -sfn "${tools_dir}/${tomcat_dir_name}" "${tools_dir}/tomcat"
}

config_tomcat() {
  echo "正在配置Tomcat..."
  service_dir=$(get_tomcat_service_name)
  cat > "${service_dir}/tomcat.service" << EOF
  [Unit]
Description=tomcat server daemon
After=network.target

[Service]
Type=forking
Environment='JAVA_HOME=${JAVA_HOME}'

ExecStart='${tools_dir}/tomcat/bin/startup.sh'
ExecStop='${tools_dir}/tomcat/bin/shutdown.sh'

[Install]
WantedBy=multi-user.target
EOF

 systemctl daemon-reload
 systemctl enable --now tomcat.service
 echo "Tomcat安装成功"
}

trap  after_install_success EXIT
# todo 如果二次安装脚本的时候，如果遇到错误或者主动退出会将之前安装目录的文件全部删除，导致已有的服务无法使用
trap rollback ERR SIGTERM SIGINT
after_install_success() {
  cd "${package_dir}" &&\
  rm -f --  ./*tomcat*.tar.gz ./*jdk*.tar.gz
}
rollback() {
  echo "Tomcat安装失败"
  echo "正在回滚进行数据回滚..."
  cd "${tools_dir}" &&\
  rm -rf ./*tomcat* ./*java* ./*jdk*
  cd "${backup_dir}" &&\
  rm -f  ./profile.bak
  [ -f "${backup_dir}/profile.bak" ] &&  mv "${backup_dir}/profile.bak" /etc/profile
  echo "数据回滚成功"
}


get_tomcat_service_name() {
  local service_dir=""
  case ${OS_NAME} in
    kylin)
      service_dir="/usr/lib/systemd/system"
      ;;
    ubuntu|debian)
      service_dir="/lib/systemd/system"
      ;;
    *)
      echo "暂不支持该系统:${OS_NAME}"
      exit 1
  esac
  echo "${service_dir}"
}


main() {
  # todo 将旧版的tomcat还有旧版jdk进行删除，再去执行安装
  init
  dependency_package_install
  get_package
  before_config_tomcat
  config_tomcat
}

main "$@"
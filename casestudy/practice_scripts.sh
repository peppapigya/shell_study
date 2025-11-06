#!/bin/bash
: '
  李导脚本练习册
'

set -auo pipefail

. /etc/os-release
OS_NAME="${ID}"

# 格式化输出
print(){
  local RED='\033[0;31m'
  local BLUE='\033[0;34m'
  local NC='\033[0m'
#  info=$(sed 's/：/:/g' "$1")
  echo "$1"  | awk -v red="$RED" -v blue="$BLUE" -v nc="$NC" '{
    if (match($0,/[:：]/)) {
      before=substr($0,1,RSTART-1)
      after=substr($0,RSTART+1)
      print red before nc ":" blue after nc
    }else{
      print $0
    }
  }'
}

# 1. 检查指定的文件脚本
check_file() {
  if [ $# -ne 1 ]; then
    echo "格式错误：请参照：command /etc/passwd"
    exit 1
  fi
  if [ ! -f "$1" ]; then
    echo "文件 $1 不存在，或者该文件不是普通文件"
    exit 1
  fi
  echo "文件名：$1"
  echo "文件大小：$(find "$1" -printf "%s" | awk '{ printf "%.2fK\n", $1/1024 }')"
  echo "权限：$(find "$1" -printf "%M")"
  echo "硬链接数：$(find "$1" -printf "%n")"
  echo "所属用户：$(find "$1" -printf "%u")"
  echo "所属用户组：$(find "$1" -printf "%g")"
  echo "修改时间：$(find "$1" -printf "%TY-%Tm-%Td %TH:%TM")"
}
# 2. 检查指定目录
check_dir() {
  if [ $# -ne 1 ]; then
    echo "格式错误：请参照：command /etc"
    exit 1
  fi
  if [ ! -d "$1" ]; then
    echo "目录 $1 不存在，或者该目录不是普通目录"
    exit 1
  fi
  echo "目录名：$1"
  echo "目录大小：$(du -sh "$1" | cut -f1)"
  echo "权限：$(find "$1" -maxdepth 0 -printf "%M")"
  echo "硬链接数：$(find "$1" -maxdepth 0 -printf "%n")"
  echo "所属用户：$(find "$1" -maxdepth 0 -printf "%u")"
  echo "所属用户组：$(find "$1" -maxdepth 0 -printf "%g")"
  echo "修改时间：$(find "$1" -maxdepth 0 -printf "%TY-%Tm-%Td %TH:%TM")"
}
# 3. 检查文件或目录
check_file_or_dir() {
  if [ $# -ne 1 ];then
    echo "格式错误：请参照：command /etc/passwd"
    exit 1
  fi
  local file="$1"
  if [ -f "${file}" ]; then
    check_file "${file}"
  elif [ -d "${file}" ]; then
    check_dir "${file}"
  else
    echo "不支持的文件类型"
    exit 1
  fi
}
# 4. 打包备份
tar_backup() {
  if [ $# -ne 1 ];then
    echo "格式错误：请参照：command /etc/passwd"
    exit 1
  fi
  local backup_dir="/backup"
  if [ ! -d "${backup_dir}" ];then
    mkdir -p "${backup_dir}"
  fi
  local file_name="$1"
  #  校验文件或目录是否存在
  check_file_or_dir_exist "${file_name}"
  local name=""
  name="$(basename "${file_name}")"
  local tar_file_name=""
  tar_file_name="${backup_dir}"/"${name}_$(date +%F_%T)".tar.gz
  if tar -czvf "${tar_file_name}"  "${file_name}" >/dev/null 2>&1;then
    echo "备份成功:存放位置为：${tar_file_name}"
  else
    # 避免tar失败了还有残留的打包文件
    rm -rf "${tar_file_name}"
    echo "备份失败"
    exit 1
  fi
}

# 5. 各种时间格式
date_format() {
  echo "年：$(date +%Y)"
  echo "月：$(date +%m)"
  echo "日：$(date +%d)"
  echo "时：$(date +%H)"
  echo "分：$(date +%M)"
  echo "秒：$(date +%S)"
  echo "周几：$(date +%w)"
  echo "完整格式：$(date +%Y%m%d-%H:%M:%S_%w)"
}

# 6. 用户检查脚本
check_user() {
  local virtual_user_num user_total
  # 用户总数
  user_total=$(wc -l < /etc/passwd )
  # 虚拟用户数
  virtual_user_num=$( grep -cv "/bin/bash" /etc/passwd)
  # 普通用户
  local normal_user_num
  normal_user_num=$((user_total-virtual_user_num))
  echo "用户总数：${user_total}"
  echo "虚拟用户数：${virtual_user_num}"
  echo "普通用户数：${normal_user_num}"
  echo "${normal_user_num}"
}

# 7. 登录用户检查脚本
check_login_user() {
   check_user
  local user_login_names
  user_login_names=$(grep "/bin/bash" /etc/passwd | cut -d: -f1 | tr "\n" " ")
  echo "普通用户的名字：${user_login_names}"
  # 获取可登录系统的用户
  local can_login_array=()
  mapfile -t can_login_array < <(cut -d: -f1,2 /etc/shadow | awk -F: '/\$6|\$1/ {print $1}')
  print "可登录系统的用户：${can_login_array[*]}"
  echo "可登录系统的用户数量：${#can_login_array[@]}"
}
# 8. 虚拟用户检查脚本
check_virtual_user(){
  mapfile -t virtual_users < <(grep -v "/bin/bash" /etc/passwd | cut -d: -f1)
  print "虚拟用户的名字：${virtual_users[*]}"
  echo "虚拟用户的数量：${#virtual_users[@]}"
}
# 9. 最近登录用户检查脚本
check_recently_login_user() {
  local user_infos=() login_status=""
  mapfile -t user_infos < <(last | head -1 | tr -s ' ' '\n')
  print "最近登录的用户：${user_infos[0]}"
  print "登录的ip地址：${user_infos[2]}"

  login_status="${user_infos[7]} ${user_infos[8]} ${user_infos[9]}"
  if [[ "${login_status}" == "still logged in" ]]; then
    echo "持续登录中"
  else
    print "登录时间：${user_infos[3]} ${user_infos[4]} ${user_infos[5]} ${user_infos[6]} - ${user_infos[8]}"
  fi
}
# 10. 系统sudo权限用户
check_sudo_user() {
  local sudo_users=()
  mapfile -t sudo_users < <(awk  '$2 == "ALL=(ALL)" && !/^$|#|Defaults/{print $1}' /etc/sudoers)
  print "具有sudo权限的用户数量: ${#sudo_users[@]}"
  print "具有sudo权限的用户名: ${sudo_users[*]}"
}
# 11.软件包是否存在检查脚本
check_package_is_exist() {
  if [ $# -ne 1 ];then
    exit 1
  fi
  if check_command_is_exist "dpkg"; then
    if dpkg -L "$1" >/dev/null 2>&1; then
      echo "软件包 $1 存在"
      else
        echo "软件包 $1 不存在"
    fi
  elif check_command_is_exist "rpm"; then
    if rpm -q "$1" >/dev/null 2>&1; then
      echo "软件包 $1 存在"
    else
      echo "软件包 $1 不存在"
    fi
  else
    echo "软件包 $1 不存在"
  fi
}
# 12.权限和属性检查脚本获取文件或目录 名字 类型 权限
check_file_or_dir_attr() {
  local file_name="$1" file_type=""
  # 获取文件类型
  if [ -L "${file_name}" ];then
    file_type="软链接"
  elif [ -d "${file_name}" ];then
    file_type="目录"
  elif [ -f "${file_name}" ];then
    file_type="文件"
  fi
  print "文件名：$(find "${file_name}" -maxdepth 0 -printf "%p")"
  print "文件类型：${file_type}"
  print "文件权限：$(find "${file_name}" -maxdepth 0 -printf "%M")"
}
# 13,14.secure日志过滤与分析脚本
analyze_log(){
  if [ $# -ne 2 ];then
    echo "格式错误：请参照：command start_time end_time"
    exit 1
  fi
  local start_time="$1" end_time="$2" file_name="/peppapig/access.log"
  # 判断开始时间是否存在
  if ! grep -q "${start_time}" "${file_name}"; then
    echo "在文件中没有找到${start_time}的日志"
    exit 1
  fi
  # 判断结束时间日志是否存在
  if ! grep -q "${end_time}" "${file_name}"; then
    echo "在文件中没有找到${end_time}的日志"
    exit 1
  fi

  sed -n "/${start_time}/,/${end_time}/p" "${file_name}"
}

# 15.系统安全脚本软件包数量，系统是否有命令变化
check_security_software() {
  local software_total=0 software_change=() cmd1="" cmd2=""

  case "${OS_NAME}" in
      "kylin"|"centos"|"rocky")
           cmd1="rpm -qa"
           cmd2="rpm -aV"
           ;;
         "ubuntu"|"debian")
           cmd1="dpkg -l"
           cmd2="dpkg -V"
           ;;
          *)
            echo "不支持的操作系统：${OS_NAME}"
            exit 1
            ;;
  esac
  software_total=$( ${cmd1} | wc -l)
  mapfile -t software_change < <(${cmd2} | grep /bin/ |  awk '{
          split($2,parts,"/")
          print parts[length(parts)]
         }')
  print "软件包数量：${software_total}"
  if [ ${#software_change[@]} -eq 0 ];then
    echo "发生变化的命令数量为：0"
  else
    print "发生变化的命令数量为:${#software_change[@]}"
    print "发生变化的命令：${software_change[*]}"
  fi
}

# 判断系统名称

# 判断命令是否存在
check_command_is_exist() {
  if [ $# -ne 1 ];then
    exit 1
  fi
  if command -v "$1" >/dev/null 2>&1; then
      return 0
  else
      return 1
  fi
}
#辅助函数判断文件或目录是否存在
check_file_or_dir_exist() {
  if [ $# -ne 1 ];then
    exit 1
  fi
  local file=0
  if [ -d "$1" ]; then
     file=1
  elif [ -f "$1" ]; then
     file=1
  fi
  if [ ! ${file} -eq 1 ]; then
    echo "文件或目录不存在"
    exit 1
  fi
}
main() {
  #check_file "$@"
  #check_dir "$@"
  #check_file_or_dir "$@"
  #tar_backup "$@"
  #date_format "$@"
  #check_user "$@"
  #check_login_user "$@"
  #check_virtual_user "$@"
  #check_recently_login_user
  #check_sudo_user "$@"
  #check_package_is_exist "$@"
  #check_file_or_dir_attr "$@"
  #analyze_log "$@"
  check_security_software "$@"
}

main "$@"
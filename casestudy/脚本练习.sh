#!/bin/bash
: '
  author: peppa-pig
  description: 所有的练习脚本
'

# 检测命令是否存在
command_exist(){
  command -v "$1" > /dev/null 2>&1
}

function install() {
  # 待安装包name
  local pkg_name=$1 # local是一个生命局部变量
  local pkg_manager=""
  # 判断安装源
  # todo

}
function create_random_file() {
  if ! rpm -qa | grep pwgen >> /dev/null ; then
    echo "正在安装pwgen..."
    yum install -y pwgen
  fi
  echo "脚本已安装"
}

# 1. 批量生成随机字符文件名案例
generate_random_file() {
  local dir="/peppapig/clsn"
  [ -d "${dir}" ] || mkdir -p ${dir}
  create_random_file
  # \表示换行符，如果cd ${dir}失败，则不会执行后续操作
  cd ${dir} &&\
  for i in {1..10}
  do
    echo "正在生成第${i}文件.."
    file_name=$(pwgen -1A0)
    touch "${file_name}_clsn".txt || exit 1
  done
}

# 2. 批量改名特殊案例
# 将clsn改为znix
update_file_name(){
  local dir="/peppapig/clsn"
  cd ${dir} &&\
  file_names=$(find . -type f -printf "%f ")
  for name in ${file_names}
  do
#      mod_file_name=$(echo "${name}" | sed 's/clsn/znix/g')
# bash内置的替换方法，效率更高
      mod_file_name="${name//clsn/znix}"
      mv "${name}" "${mod_file_name}" || echo "${name} 改名失败"
  done
  echo "文件改名完成"
}

test(){
   text="I am oldboy teacher,welcome to oldboy training class."
   echo "${text}" |  awk '{
     for (i=0;i<=NF;i++) {
       if (length($i)<=6) {
          print $i
       }
     }
   }'
}

audit(){
  local  audit_log_file="/tmp/audit.log"
  com=$(history 1 | tr -s '' | cut -d " " --complement -f1,2,3)
  local_date=$(date +"%Y-%m-%d %H:%M:%S")
  echo "${local_date} ${USER} : ${com} " >> ${audit_log_file} 2>&1
}


curl_test() {
declare -r url="https://apis.tianapi.com/pet/index"
  cat << EOF
  请选择查询类别
  0. 猫科
  1. 犬类
  2. 爬行类
  3. 小宠物类
  4. 水族类
EOF
read -rp "请输出查询动物类别：" type
 json=$(curl -X POST \
 -H "Content-Type:application/x-www-form-urlencoded" \
 -d "key=960d199fa1f8b7e40193f80f942ced8b&page=1&num=${type}" \
 "${url}")
  echo "所有数据：$(echo ${json} | jq -r '.result.list')"


}

main(){
  #create_random_file
  #generate_random_file
  # update_file_name
  update_file_name
}

main "$@"
#!/bin/bash

set -aeuo pipefail

: '
  一键启动或重启jar包脚本
  1. 支持启动某些jar包，jar包需要给出绝对路径
  2. 支持一键启动所有的jar包（默认路径下的jar）
'
: '
  TODO@2025.11.05 peppa-pig
  1. 后续加上排除列表，排除某些jar包
  2. 支持get_opt
  3. 自定义启动参数
'
# jar包下的目录，需要使用find递归去找
declare -r jar_dir="/usr/local/home/backend/"
# 设置jar包的启动环境，prod,dev,local,test
declare -r start_environment="prod"
declare -a start_success_list=()
declare -a start_fail_list=()
declare -a jar_list=()
declare  -a pids=()
# 检查启动jar包的环境
# shellcheck disable=SC2120
  check() {
    # 如果不为空则需要判断对应的jdk的版本，必须大于指定版本
    if [ ! $# -eq 0 ];then
      echo "todo 后续加上"
      exit 1
    fi
    if ! java -version >/dev/null 2>&1; then
      echo "请安装jdk..."
      exit 1
    fi
  }
# 获取所有jar包列表
get_jar_list() {
  # 如果没有传递参数，那就默认启动所有jar包
   if [ $# -eq 0 ]; then
      mapfile -t jar_list < <(find "${jar_dir}" -name "*.jar")
   else
     for param in "$@"; do
       jar_list+=("${param}")
     done
    fi
}

# 停止所有的jar包
stop_all_jar() {
  for jar_name in "${jar_list[@]}"; do
    base_name=$(basename "${jar_name}")
    local pid
    pid=$(jps | grep -i  "${base_name}" | awk '{print $1}')
    pids+=("${pid}")
  done
  # 一次新删除所有进程
  if [ "${#pids[@]}" -gt 0 ]; then
    echo "正在停止所有进程..."
    kill  "${pids[@]}"
    sleep 2
  fi
}
# 启动所有的jar包
start_all_jar() {
  pids=()
  echo "正在启动所有jar包..."
  for jar_name in "${jar_list[@]}"; do
    # 判断文件是否存在
    [ ! -f "${jar_name}" ] && continue
    # 必须得进入目录才能加载对应配置文件，要不就是用代码里面指定的配置文件
    cd "$(dirname "${jar_name}")" && \
    nohup java -jar "${jar_name}" --spring.profiles.active="${start_environment}" >/dev/null 2>&1 &
     pids+=("$!")
  done
  sleep 3

  for pid in "${pids[@]}"; do
    if ps -p "${pid}" >/dev/null; then
      start_success_list+=("${pid}")
    else
      start_fail_list+=("${pid}")
    fi
  done
}
# 打印启动结果
print_result() {
  echo "########## 启动结果 ##########"
  echo "启动成功的jar包数量：${#start_success_list[@]}"
  echo "启动失败的jar包数量：${#start_fail_list[@]}"
  echo "########## 启动成功jar包列表 ##########"
  for pid in "${start_success_list[@]}"; do
     jps | grep "${pid}"
   done
  if [ "${#start_fail_list[@]}" -gt 0 ]; then
     echo "########## 启动失败jar包列表 ##########"
     echo "${start_fail_list[@]}"
   fi
}

main() {
   check
   get_jar_list "$@"
   stop_all_jar
   start_all_jar
   print_result

}
 main "$@"


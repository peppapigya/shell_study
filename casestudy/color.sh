#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'
# 日志级别提供给外部函数使用
ERROR="ERROR"
SUCCESS="SUCCESS"
INFO="INFO"
WARNING="WARNING"
# 正确日志
success_log() {
  local num="$#" level="${SUCCESS}" message="$2" line=${3:-""}
  case $num in
       2)
         print  "${level}" "${message}" "${GREEN}"
         ;;
       3)
         print_with_line "${level}" "${message}" "${GREEN}" "${line}"
         ;;
  esac
}
# param 1日志级别 2. 日志信息 3. 颜色
print(){
  timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  local level=${1:-INFO} message=${2:- ""} color=$3
  echo -e "[${color}${timestamp} ${level}${NC}]:${message}"
}
# param 1日志级别 2. 日志信息 3.行号
print_with_line(){
  local level=${1:-INFO} message=${2:- ""} color="$3" line=${4:-""}
  echo -e "[${timestamp} ${level}] [line: ${line}]:${message}"
}
# 错误日志信息
error_log(){
  local num="$#" level="${ERROR}" message="$2" line=${3:-""}
  case $num in
       2)
         print  "${level}" "${message}" "${RED}"
         ;;
       3)
         print_with_line "${level}" "${message}" "${RED}" "${line}"
         ;;
  esac
}
# 警告日志信息
warning_log(){
  local num="$#" level="${WARNING}" message="$2" line=${3:-""}
  case $num in
       2)
         print  "${level}" "${message}" "${YELLOW}"
         ;;
       3)
         print_with_line "${level}" "${message}" "${YELLOW}" "${line}"
         ;;
  esac
}
# 普通日志信息
info_log(){
  local num="$#" level="${INFO}" message="$2" line=${3:-""}
  case $num in
       2)
         print  "${level}" "${message}" "${BLUE}"
         ;;
       3)
         print_with_line "${level}" "${message}" "${BLUE}" "${line}"
         ;;
  esac
}
# 主方法
log(){
  case $1 in
    s|sucess)
      success_log "$@"
      ;;
    e|error)
      error_log "$@"
      ;;
    w|warning)
      warning_log "$@"
      ;;
    *)
      info_log "$@"
      ;;
  esac
}
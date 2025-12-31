#!/bin/bash
: '
  检查https证书有效期
'
opt=$1
url=$2

# 检查域名过期
check_domain() {
  local expire_data=`whois "${url}" | egrep "Expiry|Expiration" | awk -F ":" '{print $2}' | awk '{print $2}'`
  local expire_data_seconds=$(date -d "${expire_data}" +%s)
  local now_data_seonds=$(date +%s)
  local date_expire_days=$(echo "(${expire_data_seconds}-${now_data_seonds})/86400" | bc)
  ehco "${url}证书有效期剩余${date_expire_days}天"
}

# 检查证书是否过期

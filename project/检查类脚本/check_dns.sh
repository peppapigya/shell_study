#!/bin/bash
: '
  检查DNS是否正常
'
url=$1
if which nslookup &>>/dev/null ; then
	  yum install -y bind-utils
fi

if nslookup $url &>/dev/null; then
  echo  "1"
else
  echo "0"
fi
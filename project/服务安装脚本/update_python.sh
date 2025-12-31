#!/bin/bash
yum install -y gcc openssl-devel bzip2-devel libffi-devel zlib-devel
tar xf  Python-3.11.14.tar.xz
cd Python-3.11.14
./configure --enable-optimizations --with-ssl
#--enable-optimizations自动进行优化(python)
#--with-ssl支持ssl模块，功能。
#编译-生成二进制文件
make -j `nproc`
#安装 创建目录,复制文件等操作.
make install
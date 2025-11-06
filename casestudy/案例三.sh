#!/bin/bash
export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin
config_file=$1
source $config_file
BASE_DIR=$(pwd)
LOG=$BASE_DIR/run_benchmark_"$(date +"%Y%m%d%H%M%S")".log
result_dir=${result_dir%/}
result_data=$result_dir/result_data_"$(date +"%Y%m%d%H%M%S")".txt
result_html=$result_dir/result_data_"$(date +"%Y%m%d%H%M%S")".html

params="rds_host test_host remote_host test_type result_dir use_yum fio_ioengine fio_direct fio_size fio_block_size fio_iodepth_iops fio_numjobs_iops fio_iodepth_latency fio_numjobs_latency fio_runtime fio_filename fio_rwmixread  sysbench_mysql_port sysbench_mysql_user sysbench_mysql_cipher sysbench_legacy sysbench_time sysbench_table_count sysbench_tablesize sysbench_report_interval sysbench_threads sysbench_forced_shutdown  os_collector_switch sysbench_mysql_table_engine sysbench_rand_type sysbench_percentile sysbench_type sysbench_db_ps_mode sysbench_sleep_time"

ssh_tunnel=`cat $BASE_DIR/ssh.cnf | grep ssh_tunnel | awk -F '=' '{print $2}'`
remote_user=`cat $BASE_DIR/ssh.cnf | grep remote_user | awk -F '=' '{print $2}'`

function main_pro(){
    check_local_env
    case $test_type in
        0)
        if [ $remote_host == $test_host ]
          then
                        check_fio_env
                        check_sysbench_env
                        get_machine_metrics
                        run_os_collector
                        fio_test
                        print_machine_result
                        sysbench_test
                        print_sysbench_result
                        kill_os_collector

                else
                        ssh_tunnel=`cat $BASE_DIR/ssh.cnf | grep ssh_tunnel | awk -F '=' 'print $2'`
                        if [  ssh_tunnel -eq 0  ]
                        then
                        logger "ERROR" "remote_host != test_host and ssh tunnel is not available, test_type should not be 0,process exits."
                        exit 1
                        fi
                fi
            : ;;
        1)
                        check_fio_env
                        get_machine_metrics
                        run_os_collector
                        fio_test
                        print_machine_result
                        kill_os_collector
            : ;;
        2)
                        check_sysbench_env
                        run_os_collector
                        sysbench_test
                        print_sysbench_result
                        kill_os_collector
            : ;;
        *)
            : ;;
    esac
    ensure_ssh_transfer_result_pri
}

function run_os_collector()
{
   if [ ${os_collector_switch} == 'on'  ]
    then
   result_dir=${result_dir%/}
   os_result_name="os_statistics_"$(date +"%Y%m%d%H%M%S")".txt"
   logger "INFO" "os_collector_switch is open, start to collect os performance result and the it will be exported in ${result_dir}/${os_result_name}."
   python ${BASE_DIR}/os_collector_linux.py 1 2 > ${result_dir}/${os_result_name} 2>&1 & echo $! > ${BASE_DIR}/pidfile
   fi
}

function kill_os_collector()
{
   if [ $(ps -ef | grep  "os_collector_linux.py" | grep -v grep | wc -l) -gt 0 ]
    then
        logger "INFO" "test finished, stop collecting os performance result."
    #ps -ef | grep  "os_collector_linux.py" | grep -v grep | awk '{print $2}' | xargs kill -9 > /dev/null
 kill $(cat ${BASE_DIR}/pidfile)
   fi
}

function logger()
{
        local level=$1
        local msg=$2
        local DATE=`date +"%F %X"`
        echo "${level}: ${DATE} ${msg}" >> ${LOG}
}

function check_local_env(){
 while read line; do
  line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//; /^#/d')
  if [ -z "$line" ]; then
    continue
  fi

  key=$(echo "$line" | cut -d= -f1)
  if ! echo "$params" | grep -qw "$key"; then
    echo "Invalid parameter name: $key"
    logger "ERROR" "Invalid parameter name: $key"
    exit 1
fi

  # 检查是否有值
  value=$(echo "$line" | cut -d= -f2)
  if [ -z "$value" ]; then
    echo "$key is missing a value."
    logger "ERROR" "$key is missing a value."
    exit 1
  fi
done < ${config_file}

    logger "INFO" "All parameters are present and have values."

  if [ -d ${result_dir} ]; then
    logger "INFO" "check result dir ${result_dir} success, ${result_dir} already exists."
  else
    logger "INFO" "result dir ${result_dir} doesn't exist, try to create this directory."
    mkdir -p  ${result_dir}
    logger "INFO" "${result_dir} created."
  fi

if [  $use_yum == 1 ]
then
  cd /etc/yum.repos.d/
  if [  -d bak/  ]
  then
    mv bak/*.repo .
  fi
  PACKAGES="make automake libtool pkgconfig libaio-devel mariadb-devel openssl-devel"
  logger "INFO" "start to check $PACKAGES."
  for pkg in $PACKAGES; do
    if  ! rpm -q $pkg  > /dev/null; then
        logger "INFO" "$pkg not installed, start to install $pkg."
        yum -y install $pkg  > /dev/null
                if [ $? -eq 0 ]
                then
                 logger "INFO" "install $pkg success."
                else
                 logger "ERROR" "install $pkg falied."
                 exit 1
                fi
    fi
  done
  logger "INFO" "check yum package finished."
else
  logger "INFO" "try to replace origin yum repo."
  cd /etc/yum.repos.d/
   mkdir -p bak/
if [ $(ls -l | grep ".repo" | wc -l ) -gt 0  ] ; then
  mv *.repo bak/
fi
cd ${BASE_DIR}
  mkdir -p pkg
  tar -zxf pkg.tgz -C pkg/
  cd ${BASE_DIR}/pkg/pkg
  yum localinstall *x86_64.rpm  --skip-broken -y     > /dev/null   2>&1
  if [ $? -eq 0 ]
    then
          logger "INFO" "localinstall rpm pkg success."
    else
     logger "ERROR" "localinstall rpm pkg falied."
         #exit 1
  fi
 fi

}

function check_fio_env(){
  logger "INFO" "start to check fio tool."
  if [ ! -f "/usr/local/fio-3.18/fio" ]
  then
    logger "INFO" "fio 3.18 tool doesn't exists, start to install fio tool."
    install_fio
  else
   logger "INFO" "fio 3.18 tool exists."
     fi
   logger "INFO" "check fio tool finished."
}

function check_sysbench_env(){
  logger "INFO" "start to check sysbench tool."
  if [[  -f  $BASE_DIR/sysbench-1.0.20/src/sysbench ]]
  then
    logger "INFO" "sysbench 1.0.20 tool exists."
  else
   logger "INFO" "sysbench 1.0.20 tool doesn't exists, start to install sysbench tool."
    install_sysbench
  fi
  logger "INFO" "check sysbench tool finished."
}


function install_fio(){
pkg='libaio-devel'
if  ! rpm -q $pkg  > /dev/null; then
 cd $BASE_DIR
 mkdir -p pkg
 tar -zxf pkg.tgz -C pkg/
 cd pkg/pkg
 yum localinstall libaio*x86_64.rpm  -y > /dev/null
   fi

tar -xzf $BASE_DIR/fio-3.18.tar.gz -C /usr/local/
cd /usr/local/fio-3.18
./configure >/dev/null
make -j 4 >/dev/null
make install >/dev/null
 if [ -f "/usr/local/fio-3.18/fio" ]
  then
   fio_version=`/usr/local/fio-3.18/fio --version`
   if [ $fio_version == "fio-3.18" ]
    then
         logger "INFO" "install fio tool success."
        else
        logger "ERROR" "fio tool install failed."
  exit 1
  fi
  else
  logger "ERROR" "fio tool install failed."
  exit 1
  fi
}


function install_sysbench(){
tar -xzf $BASE_DIR/sysbench-1.0.20.tgz -C $BASE_DIR
cd $BASE_DIR/sysbench-1.0.20
#./autogen.sh >/dev/null
#./configure >/dev/null
#make -j 4 >/dev/null  2>&1
#make install >/dev/null
if [[  -f  $BASE_DIR/sysbench-1.0.20/src/sysbench ]]
 then
 logger "INFO" "install sysbench success."
 else
  logger "ERROR" "sysbench install failed."
  exit 1
  fi
}


function sysbench_test(){
#配置sysbench压测脚本
benchshell=$BASE_DIR/sysbench-1.0.20/bench.sh
originshell==$BASE_DIR/sysbench-1.0.20/bench_origin.sh
if [ -f $originshell ]; then
    logger "INFO" "check sysbench script exists."
else
   tar -xzf $BASE_DIR/sysbench-1.0.20.tgz
   [ $? -ne 0 ] && logger "ERROR" "check sysbench script doesn't exists."  && exit 1
fi
cd $BASE_DIR/sysbench-1.0.20
cp -rf  bench_origin.sh bench.sh

sed -i "s/PORT/${sysbench_mysql_port}/g" $benchshell
sed -i 's/HOST/'${rds_host}'/g' $benchshell
sed -i 's/USER/'${sysbench_mysql_user}'/g' $benchshell
new_cipher=$(sed 's/[\/&]/\\&/g' <<< "$sysbench_mysql_cipher")
sed -i 's/\*\*\*\*\*\*\*\*/'${new_cipher}'/g' $benchshell
sed -i "s/LEGACY/${sysbench_legacy}/g" $benchshell
sed -i "s/TIME/${sysbench_time}/g" $benchshell
sed -i "s/TABLES/${sysbench_table_count}/g" $benchshell
sed -i "s/TBSIZE/${sysbench_tablesize}/g" $benchshell
sed -i "s/INTERVAL/${sysbench_report_interval}/g" $benchshell
sed -i "s/FORCEDSHUTDOWN/${sysbench_forced_shutdown}/g" $benchshell

sed -i "s/TABLEENGINE/${sysbench_mysql_table_engine}/g" $benchshell
sed -i "s/RANDTYPE/${sysbench_rand_type}/g" $benchshell
sed -i "s/PERCENTILE/${sysbench_percentile}/g" $benchshell
sed -i "s/SYSBENCHTYPE/${sysbench_type}/g" $benchshell
sed -i "s/SYSBENCHDBPSMODE/${sysbench_db_ps_mode}/g" $benchshell
sed -i "s/SYSBENCHSLEEP/${sysbench_sleep_time}/g" $benchshell

#执行压测
logger "INFO" "start to run sysbench."
result_dir=${result_dir%/}
sysbench_output=$result_dir/run_sysbench_"$(date +"%Y%m%d%H%M%S")".log
logger "INFO" "sysbench origin result will be loaded in ${sysbench_output}."
sysbench_thread=`echo ${sysbench_threads} | sed 's/,/ /g'`
sh ${benchshell} ${sysbench_thread} > ${sysbench_output}
if [ $? -eq 0 ]
then
 logger "INFO" "run sysbench success."
#获取thread数：
thread_list=`cat ${sysbench_output} | grep 'thread' | grep "==" | sed 's/[^0-9]*\([0-9]\+\).*/\1/'`
thread_arr=($thread_list)
 [ $? -ne 0 ]  && logger "ERROR" "get sysbench thread result wrong."  && exit 1
#获取TPS：
tps_list=`cat ${sysbench_output} | grep 'transactions' | awk -F '(' '{print $2}'| awk '{print $1}'`
tps_arr=($tps_list)
 [ $? -ne 0 ]  && logger "ERROR" "get sysbench TPS result wrong."  && exit 1
#获取QPS：
qps_list=`cat ${sysbench_output} | grep 'queries' | awk -F '(' '{print $2}'| awk '{print $1}'`
qps_arr=($qps_list)
[ $? -ne 0 ]  && logger "ERROR" "get sysbench QPS result wrong."  && exit 1
#获取xx%响应延时
latency_list=`cat ${sysbench_output} | grep 'th percentile' | awk -F ':' '{print $2}' |sed  's/ //g'`
latency_arr=($latency_list)
[ $? -ne 0 ]  && logger "ERROR" "get sysbench latency result wrong."  && exit 1
#获取读次数
read_count_list=`cat ${sysbench_output} | grep 'read:' | awk -F ':' '{print $2}' |sed  's/ //g'`
read_count_arr=($read_count_list)
[ $? -ne 0 ]  && logger "ERROR" "get sysbench read count result wrong."  && exit 1
#获取写次数
write_count_list=`cat ${sysbench_output} | grep 'write:' | awk -F ':' '{print $2}' |sed  's/ //g'`
write_count_arr=($write_count_list)
[ $? -ne 0 ]  && logger "ERROR" "get sysbench write count result wrong."  && exit 1
#获取压测时间
start_time_list=`cat ${sysbench_output} | grep 'start bench:' | awk -F ': ' '{print $2}' `
start_time_arr=($start_time_list)
[ $? -ne 0 ]  && logger "ERROR" "get sysbench start time wrong."  && exit 1
stop_time_list=`cat ${sysbench_output} | grep 'stop bench:' | awk -F ': ' '{print $2}' `
stop_time_arr=($stop_time_list)
[ $? -ne 0 ]  && logger "ERROR" "get sysbench stop time wrong."  && exit 1


else
 logger "ERROR" "run sysbench failed."
  exit 1
fi

}


function fio_test(){
logger "INFO" "start to run fio randread test."
result_dir=${result_dir%/}
fio_output=$result_dir/run_fio_"$(date +"%Y%m%d%H%M%S")".log
logger "INFO" "fio test origin result will be loaded in ${fio_output}."

logger "INFO" "start to run fio randread test for IOPS."
 fio_command="/usr/local/fio-3.18/fio -ioengine=${fio_ioengine} -bs=${fio_block_size} -direct=${fio_direct} -thread -rw=randread -filename=${fio_filename} -size=${fio_size} -name='${fio_block_size} randread test' -iodepth=${fio_iodepth_iops} -numjobs=${fio_numjobs_iops} -group_reporting -runtime=${fio_runtime}  "
 echo "fio randread test for IOPS command: $fio_command "> ${fio_output}
 eval ${fio_command} >> ${fio_output}
 if [ $? -eq 0 ]
 then
  logger "INFO"  "fio randread test success."
 else
  logger "ERROR"  "fio randread test failed."
  exit 1
 fi

logger "INFO" "start to run fio randwrite test for IOPS."
 fio_command="/usr/local/fio-3.18/fio -ioengine=${fio_ioengine} -bs=${fio_block_size} -direct=${fio_direct} -thread -rw=randwrite -filename=${fio_filename} -size=${fio_size} -name='${fio_block_size} randwrite test' -iodepth=${fio_iodepth_iops} -numjobs=${fio_numjobs_iops} -group_reporting -runtime=${fio_runtime}  "
echo "fio randwrite test for IOPS command: $fio_command ">> ${fio_output}
eval ${fio_command} >> ${fio_output}
 if [ $? -eq 0 ]
 then
  logger "INFO"  "fio randwrite test success."
 else
  logger "ERROR"  "fio randwrite test failed."
  exit 1
 fi

logger "INFO" "start to run fio ${fio_rwmixread} rwmixread test for IOPS."
 fio_command="/usr/local/fio-3.18/fio -ioengine=${fio_ioengine} -bs=${fio_block_size} -direct=${fio_direct} -thread -rw=randrw -rwmixread=${fio_rwmixread} -filename=${fio_filename} -size=${fio_size} -name='${fio_block_size} rwmixread test' -iodepth=${fio_iodepth_iops} -numjobs=${fio_numjobs_iops} -group_reporting -runtime=${fio_runtime}  "
echo "fio rwmixread test for IOPS command: $fio_command ">> ${fio_output}
eval ${fio_command} >> ${fio_output}
 if [ $? -eq 0 ]
 then
  logger "INFO"  "fio rwmixread test success."
 else
  logger "ERROR"  "fio rwmixread test failed."
  exit 1
 fi


logger "INFO" "start to run fio randread test for latency."
 fio_command="/usr/local/fio-3.18/fio -ioengine=${fio_ioengine} -bs=${fio_block_size} -direct=${fio_direct} -thread -rw=randread -filename=${fio_filename} -size=${fio_size} -name='${fio_block_size} randread test' -iodepth=${fio_iodepth_latency} -numjobs=${fio_numjobs_latency} -group_reporting -runtime=${fio_runtime}  "
echo "fio randread test for latency command: $fio_command ">> ${fio_output}
eval ${fio_command} >> ${fio_output}
 if [ $? -eq 0 ]
 then
  logger "INFO"  "fio randread test success."
 else
  logger "ERROR"  "fio randread test failed."
  exit 1
 fi

logger "INFO" "start to run fio randwrite test for latency."
 fio_command="/usr/local/fio-3.18/fio -ioengine=${fio_ioengine} -bs=${fio_block_size} -direct=${fio_direct} -thread -rw=randwrite -filename=${fio_filename} -size=${fio_size} -name='${fio_block_size} randwrite test' -iodepth=${fio_iodepth_latency} -numjobs=${fio_numjobs_latency} -group_reporting -runtime=${fio_runtime}  "
echo "fio randwrite test for latency command: $fio_command ">> ${fio_output}
eval ${fio_command} >> ${fio_output}
 if [ $? -eq 0 ]
 then
  logger "INFO"  "fio randwrite test success."
 else
  logger "ERROR"  "fio randwrite test failed."
  exit 1
 fi

logger "INFO" "start to run fio ${fio_rwmixread} rwmixread test for latency."
 fio_command="/usr/local/fio-3.18/fio -ioengine=${fio_ioengine} -bs=${fio_block_size} -direct=${fio_direct} -thread -rw=randrw -rwmixread=${fio_rwmixread} -filename=${fio_filename} -size=${fio_size} -name='${fio_block_size} rwmixread test' -iodepth=${fio_iodepth_latency} -numjobs=${fio_numjobs_latency} -group_reporting -runtime=${fio_runtime}  "
echo "fio rwmixread test for latency command: $fio_command ">> ${fio_output}
eval ${fio_command} >> ${fio_output}
 if [ $? -eq 0 ]
 then
  logger "INFO"  "fio rwmixread test success."
 else
  logger "ERROR"  "fio rwmixread test failed."
  exit 1
 fi

logger "INFO" "start to run fio read test for IOPS."
 fio_command="/usr/local/fio-3.18/fio -ioengine=${fio_ioengine} -bs=${fio_block_size} -direct=${fio_direct} -thread -rw=read -filename=${fio_filename} -size=${fio_size} -name='${fio_block_size} read test' -iodepth=${fio_iodepth_iops} -numjobs=${fio_numjobs_iops} -group_reporting -runtime=${fio_runtime}  "
 echo "fio read test for IOPS and Throughput command: $fio_command ">> ${fio_output}
 eval ${fio_command} >> ${fio_output}
 if [ $? -eq 0 ]
 then
  logger "INFO"  "fio read test success."
 else
  logger "ERROR"  "fio read test failed."
  exit 1
 fi

logger "INFO" "start to run fio write test for IOPS."
 fio_command="/usr/local/fio-3.18/fio -ioengine=${fio_ioengine} -bs=${fio_block_size} -direct=${fio_direct} -thread -rw=write -filename=${fio_filename} -size=${fio_size} -name='${fio_block_size} write test' -iodepth=${fio_iodepth_iops} -numjobs=${fio_numjobs_iops} -group_reporting -runtime=${fio_runtime}  "
echo "fio write test for IOPS and Throughput command: $fio_command ">> ${fio_output}
eval ${fio_command} >> ${fio_output}
 if [ $? -eq 0 ]
 then
  logger "INFO"  "fio write test success."
 else
  logger "ERROR"  "fio write test failed."
  exit 1
 fi


#获取IOPS：
fio_iops=`cat ${fio_output} | grep  "IOPS="  | awk -F '=' '{print $2}' | sed 's/, BW//'`
fio_bw=`cat ${fio_output} | grep  "IOPS="  | awk -F '[()]' '{print $2}'`
#平均延时：
fio_lat=`cat ${fio_output} |grep  "lat (" | grep -vE "slat|clat" | grep -E "usec|msec"   | grep avg | awk -F '=' '{print $4}'  | sed 's/, stdev//'`
#获取平均延时单位
fio_lat_unit=`cat ${fio_output} |grep  "lat (" | grep -vE "slat|clat" | grep -E "usec|msec"   | grep avg | grep -oE '\(([^)]+)\)' | sed 's/[()]//g'`
fio_iops_array=($fio_iops)
fio_bw_array=($fio_bw)
fio_lat_array=($fio_lat)
fio_lat_unit_array=($fio_lat_unit)
[ $? -ne 0 ]  && logger "ERROR" "get fio result wrong."  && exit 0
#echo ${fio_iops_array[@]}
#echo ${fio_lat_array[@]}
}


function get_machine_metrics(){
#获取数据文件路径
#mysql_data_dir=`ps -ef | grep mysqld | grep ${sysbench_mysql_port} | grep datadir | awk -F 'datadir=' '{print $2}' | awk -F ' ' '{print $1}'`
#获取数据文件挂载盘：
#mount_dir=`df ${mysql_data_dir} | sed -n '2p'   | awk '{print $NF}'`
#mount_dir=`df ${fio_filename} | sed -n '2p'   | awk '{print $NF}'`
#获取挂载盘所在分区
#disk_partition=`lsblk | grep ${mount_dir} | awk '{print $1}' | sed 's/[^a-zA-Z]//g' | tr -d '[:space:]'`
#获取分区磁盘类型（返回0：SSD盘，返回1：SATA盘）
#disk_code=`lsblk -d -o name,rota | grep ${disk_partition} | awk '{print $NF}'`
#if [  $disk_code == '0' ]
#then
#  disk_type='SSD'
#else
#  disk_type='SATA'
#fi
#cpu的核数
cpu_core_num=`lscpu | grep '^CPU(s):' | awk '{print $2}'`
#cpu的主频
cpu_hz=`lscpu | grep 'CPU MHz' | awk '{print $3}'`
#获取内存总大小
total_mem=`free -h | grep 'Mem:' | awk '{print $2}' `
#获取操作系统版本
os_version=`cat /etc/system-release| sed 's/ /_/g' | sed 's/_$//'`
#获取操作系统内核版本
kernel_version=`uname -r`
#获取网络时延
network_latency=`ping -c 5 ${rds_host} | grep rtt | cut -d " " -f 4 | awk -F '/' '{print $2}'`

}

function print_machine_result(){
logger "INFO" "tabular machine data will be exported in ${result_data}."
printf "========================================测试环境========================================\n" > ${result_data}
echo "开始: $(date +%F_%T)"  >> ${result_data}
echo "RDS机器IP                       ${rds_host}
测试机IP                        ${test_host}
系统版本                        ${os_version}
内核版本                        ${kernel_version}
CPU核数                         ${cpu_core_num}
CPU主频                         ${cpu_hz} MHz
机器内存                        ${total_mem}
磁盘随机读${fio_block_size}iops               ${fio_iops_array[0]}(${fio_bw_array[0]})
磁盘随机读${fio_block_size}时延               ${fio_lat_array[4]} ${fio_lat_unit_array[4]}
磁盘随机写${fio_block_size}iops               ${fio_iops_array[1]}(${fio_bw_array[1]})
磁盘随机写${fio_block_size}时延               ${fio_lat_array[5]} ${fio_lat_unit_array[5]}
${fio_rwmixread}%读混合写/读iops              ${fio_iops_array[2]}(${fio_bw_array[2]})
${fio_rwmixread}%读混合写/读时延              ${fio_lat_array[6]} ${fio_lat_unit_array[6]}
${fio_rwmixread}%读混合写/写iops              ${fio_iops_array[3]}(${fio_bw_array[3]})
${fio_rwmixread}%读混合写/写时延              ${fio_lat_array[7]} ${fio_lat_unit_array[7]}
磁盘顺序读${fio_block_size}吞吐量              ${fio_iops_array[8]}(${fio_bw_array[8]})
磁盘顺序写${fio_block_size}吞吐量              ${fio_iops_array[9]}(${fio_bw_array[9]}) "   >> ${result_data}

if [ $rds_host != $test_host ]
 then
echo "ping RDS ip 网络时延                  ${network_latency} ms" >> ${result_data}
fi

echo "结束: $(date +%F_%T) " >> ${result_data}
[ $? -eq 0 ] && logger "INFO" "tabular machine data is exported."

logger "INFO" "html machine data will be exported in ${result_html}."
echo "<head>
        <title>测试报告</title>
        <style>
                table, th, td {
                        border: 1px solid black;
                        border-collapse: collapse;
                        padding: 5px;
                }
        </style>
</head>"  > $result_html
echo "<h1>测试环境信息</h1>
        <table>
                <tr>
                        <th>项目</th>
                        <th>值</th>
                </tr>
                <tr>
                        <td>RDS机器IP</td>
                        <td>${rds_host}</td>
                </tr>
                <tr>
                        <td>测试机IP</td>
                        <td>${test_host}</td>
                </tr>
                <tr>
                        <td>系统版本</td>
                        <td>${os_version}</td>
                </tr>
                <tr>
                        <td>内核版本</td>
                        <td>${kernel_version}</td>
                </tr>
                <tr>
                        <td>CPU核数</td>
                        <td>${cpu_core_num}</td>
                        </td>
                </tr>
                <tr>
                        <td>CPU主频</td>
                        <td>${cpu_hz} MHz</td>
                </tr>
                <tr>
                        <td>机器内存</td>
                        <td>${total_mem}</td>
                </tr>
                <tr>
                        <td>磁盘随机读${fio_block_size}iops</td>
                        <td>${fio_iops_array[0]}(${fio_bw_array[0]})</td>
                </tr>
                <tr>
                        <td>磁盘随机读${fio_block_size}时延</td>
                        <td>${fio_lat_array[4]} ${fio_lat_unit_array[4]}</td>
                </tr>
                <tr>
                        <td>磁盘随机写${fio_block_size}iops</td>
                        <td>${fio_iops_array[1]}(${fio_bw_array[1]})</td>
                </tr>
                <tr>
                        <td>磁盘随机写${fio_block_size}时延</td>
                        <td>${fio_lat_array[5]} ${fio_lat_unit_array[5]}</td>
                </tr>
                <tr>
                        <td>${fio_rwmixread}%读混合写/读iops</td>
                        <td>${fio_iops_array[2]}(${fio_bw_array[2]})</td>
                </tr>
                <tr>
                        <td>${fio_rwmixread}%读混合写/读时延</td>
                        <td>${fio_lat_array[6]} ${fio_lat_unit_array[6]}</td>
                </tr>
                <tr>
                        <td>${fio_rwmixread}%读混合写/写iops</td>
                        <td>${fio_iops_array[3]}(${fio_bw_array[3]})</td>
                </tr>
                <tr>
                        <td>${fio_rwmixread}%读混合写/写时延</td>
                        <td>${fio_lat_array[7]} ${fio_lat_unit_array[7]}</td>
                </tr>
                <tr>
                        <td>磁盘顺序读${fio_block_size}吞吐量 </td>
                        <td>${fio_iops_array[8]}(${fio_bw_array[8]})</td>
                </tr>
                <tr>
                        <td>磁盘顺序写${fio_block_size}吞吐量 </td>
                        <td>${fio_iops_array[9]}(${fio_bw_array[9]})</td>
                </tr>
        </table>"  >> $result_html
        [ $? -eq 0 ] && logger "INFO" "html machine data is exported."
}

function print_sysbench_result(){

#打印mysql关键参数
line_start=$(grep -n "critical parameter" ${sysbench_output} | cut -d ":" -f 1)
line_start=$((line_start+1))
line_end=$(grep -n "prepare command:" ${sysbench_output} | cut -d ":" -f 1)
printf "=====================================mysql关键参数======================================\n" >> ${result_data}
sed -n "$((line_start+1)),$((line_end-1))p" ${sysbench_output}   >> ${result_data}
sed -n "$((line_start+1)),$((line_end-1))p" ${sysbench_output}   > /tmp/mysql_para.txt
# 初始化数组
mysql_para_name=()
mysql_para_value=()
# 逐行读取文本内容
while read -r mysql_para_name_val mysql_para_value_val; do
  # 将值添加到相应的数组中
  mysql_para_name+=("$mysql_para_name_val")
  mysql_para_value+=("$mysql_para_value_val")
done < /tmp/mysql_para.txt

printf "====================================sysbench关键参数====================================\n" >> ${result_data}
echo "oltp-tables-count    ${sysbench_table_count}
oltp-table-size      ${sysbench_tablesize}
mysql-table-engine   ${sysbench_mysql_table_engine}
time                 $sysbench_time
report-interval      $sysbench_report_interval
oltp-test-mode       complex
rand-type            $sysbench_rand_type
threads              $sysbench_thread
events               0
percentile           $sysbench_percentile
forced-shutdown      $sysbench_forced_shutdown
压测类型             ${sysbench_type}  " >> ${result_data}

logger "INFO" "tabular sysbench data will be exported in ${result_data}."
bench_num=$((${#latency_arr[@]} - 1))
printf "===================================sysbench压测结果=====================================\n" >> ${result_data}
printf "%-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s\n" "机器IP" "端口" "thread" "TPS" "QPS" "${sysbench_percentile}%分位数RT(ms)" "read" "write" "开始" "结束" >> ${result_data}
for i in `seq 0 $bench_num`
do
printf "%-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s\n" ${rds_host} ${sysbench_mysql_port} ${thread_arr[$i]} ${tps_arr[$i]} ${qps_arr[$i]} ${latency_arr[$i]} ${read_count_arr[$i]} ${write_count_arr[$i]} ${start_time_arr[$i]} ${stop_time_arr[$i]}>> ${result_data}
done
[ $? -eq 0 ] && logger "INFO" "tabular sysbench data is exported."

logger "INFO" "html sysbench data will be exported in ${result_html}."

if [ ${test_type} -eq 2  ]
then
echo "<head>
        <title>测试报告</title>
        <style>
                table, th, td {
                        border: 1px solid black;
                        border-collapse: collapse;
                        padding: 5px;
                }
        </style>
</head>"  >> $result_html
fi

echo "<h1>mysql关键参数</h1>
        <table> "  >> $result_html
  mysql_para_num=$((${#mysql_para_value[@]} - 1))
for i in `seq 0 $mysql_para_num`
do
echo "<tr>
                        <th>${mysql_para_name[$i]}</th>
                        <th>${mysql_para_value[$i]}</th>
                </tr>"   >> $result_html
done
echo "</table>"  >> $result_html

echo "<h1>sysbench关键参数</h1>
        <table>
                <tr>
                        <th>参数</th>
                        <th>值</th>
                </tr>
                <tr>
                        <td>oltp-tables-count</td>
                        <td>${sysbench_table_count}</td>
                </tr>
                <tr>
                        <td>oltp-table-size</td>
                        <td>${sysbench_tablesize}</td>
                </tr>
                <tr>
                        <td>mysql-table-engine</td>
                        <td>${sysbench_mysql_table_engine}</td>
                </tr>
                <tr>
                        <td>time</td>
                        <td>${sysbench_time}</td>
                </tr>
                <tr>
                        <td>report-interval</td>
                        <td>${sysbench_report_interval}</td>
                        </td>
                </tr>
                <tr>
                        <td>oltp-test-mode</td>
                        <td>complex</td>
                </tr>
                <tr>
                        <td>rand-type</td>
                        <td>${sysbench_rand_type}</td>
                </tr>
                <tr>
                        <td>threads</td>
                        <td>${sysbench_thread}</td>
                </tr>
                <tr>
                        <td>events</td>
                        <td>0</td>
                </tr>
                <tr>
                        <td>percentile</td>
                        <td>${sysbench_percentile}</td>
                </tr>
                <tr>
                        <td>forced-shutdown</td>
                        <td>${sysbench_forced_shutdown}</td>
                </tr>
                <tr>
                        <td>压测类型</td>
                        <td>${sysbench_type}</td>
                </tr>
        </table>"  >> $result_html



echo "<h1>sysbench压测结果</h1>
        <table>
                <tr>
                        <th>机器IP</th>
                        <th>端口</th>
                        <th>线程数</th>
                        <th>TPS</th>
                        <th>QPS</th>
                        <th>平均响应时间(ms)</th>
                        <th>read</th>
                        <th>write</th>
                        <th>开始</th>
                        <th>结束</th>
                </tr> " >> $result_html
    for i in `seq 0 $bench_num`
    do
     echo "<tr>
                        <td>${rds_host}</td>
                        <td>${sysbench_mysql_port}</td>
                        <td>${thread_arr[$i]}</td>
                        <td>${tps_arr[$i]}</td>
                        <td>${qps_arr[$i]}</td>
                        <td>${latency_arr[$i]}</td>
                        <td>${read_count_arr[$i]}</td>
                        <td>${write_count_arr[$i]}</td>
                        <td>${start_time_arr[$i]}</td>
                        <td>${stop_time_arr[$i]}</td>
                </tr> " >> $result_html
        done
   echo "  </table>"  >> $result_html

[ $? -eq 0 ] && logger "INFO" "html sysbench data is exported."

}


function ensure_ssh_transfer_result_pri(){
 if [  `cat  /etc/passwd | grep -w ${remote_user} | wc -l ` -eq 1   ]  && [ `id -gn ${remote_user} | grep ${remote_user} | wc -l` -eq 1   ]
   then
      chown -R ${remote_user}.${remote_user}  ${result_dir}/
 fi
}

main_pro

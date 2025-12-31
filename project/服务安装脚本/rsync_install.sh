#!/bin/bash
########################################################
# File: rsync_install.sh
# Version: V2.1
# Author: lidong
# Description: 安全安装rsync
# 依赖: 需要root权限，支持Debian/Ubuntu/CentOS/Rocky
########################################################

# 输出变成英文
export LANG=en_US.UTF-8
# 生效系统版本文件
source /etc/os-release

# 全局变量
RESERVED_USERS=("root" "bin" "daemon" "mail") # 系统预留用户
SECRETS_FILE="/etc/rsync.password"            # 认证文件
MODULE_NAME="data"                            # rsync模块名
DATA_PATH="/backup"                           # 默认数据路径
SERVICE_USER="rsync"                          # 服务用户名
RSYNC_NAME="rsync"                            # rsync不同版本中的名字,默认值rsync
AUTH_USER="rsync_backup"                      # 默认的认证用户名
QUICK_INSTALL=false                           # 快速安装标志
AUTH_PASSWORD=Lidong007                       # 默认认证密码

# 颜色函数
recho() { echo -e "\e[1;31m[ERROR] $*\e[0m"; }
gecho() { echo -e "\e[1;32m[INFO] $*\e[0m"; }
yecho() { echo -e "\e[1;33m[QUQ] $*\e[0m"; }
becho() { echo -e "\e[1;34m[INPUT] $*\e[0m"; }

# 是否有版本文件
if [ ! -s /etc/os-release ]; then
    recho "没有版本文件"
    exit 1
fi

# 是否为root
if [ $EUID -ne 0 ]; then
    recho "请使用root或sudo执行脚本"
    exit 1
fi

#rsync不同版本中的名字
case "$ID" in
ubuntu | debian)
    RSYNC_NAME=rsync
    ;;
centos | rocky | kylin)
    RSYNC_NAME=rsyncd
    ;;
*)
    recho "不支持的系统：$ID"
    exit 1
    ;;
esac

# 选择安装模式
select_install_mode() {
    cat <<EOF
请选择安装模式:
    1. 无聊到爆的快速安装 (使用所有默认值)
    2. 非常炫酷的自定义DIY安装 (逐步配置各项参数)
EOF
    while true; do
        read -rep "$(yecho "请选择安装模式 (1/2): ")" choice
        case "$choice" in
        1)
            QUICK_INSTALL=true
            gecho "已选择快速默认安装模式"
            return 0
            ;;
        2)
            QUICK_INSTALL=false
            gecho "已选择自定义安装模式"
            return 0
            ;;
        *)
            recho "请输入正确的选择 (1 或 2)"
            ;;
        esac
    done
}

# 安装rsync
install_rsync() {
    if command -v rsync &>/dev/null; then
        gecho "rsync已安装,版本：$(rsync --version | head -n1)"
        return 0
    fi

    yecho "开始安装rsync..."
    case "$ID" in
    ubuntu | debian)
        apt-get update &>/dev/null
        apt-get install -y rsync &>/dev/null
        ;;
    centos | rocky | kylin)
        yum install -y rsync &>/dev/null
        ;;
    *)
        recho "不支持的系统：$ID"
        exit 1
        ;;
    esac

    # 安装后校验
    if command -v rsync &>/dev/null; then
        gecho "rsync安装成功"
    else
        recho "rsync安装失败,请检查系统源"
        exit 1
    fi
}

# 用户名校验
validate_username() {
    local username="$1"
    [[ -z "$username" ]] && {
        recho "用户名不能为空"
        return 1
    }

    # 长度校验（1-32字符）
    local len=${#username}
    [[ $len -lt 1 || $len -gt 32 ]] && {
        recho "用户名长度必须为1-32字符(当前$len)"
        return 1
    }

    # 格式校验（首字符+字符集）
    [[ ! "$username" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]] && {
        recho "用户名需以字母/下划线开头,仅含字母、数字、_-"
        return 1
    }

    # 纯数字校验
    [[ "$username" =~ ^[0-9]+$ ]] && {
        recho "不能是纯数字"
        return 1
    }

    # 预留用户校验
    for reserved in "${RESERVED_USERS[@]}"; do
        [[ "$username" == "$reserved" ]] && {
            recho "禁止使用系统预留用户：$username"
            return 1
        }
    done

    # 存在性校验
    if id "$username" &>/dev/null; then
        if [ "$username" = "rsync" ]; then
            return 0
        fi
        recho "用户已存在：$username"
        return 1
    fi
    return 0
}

# 获取用户名
get_valid_username() {
    # 快速安装模式下直接使用默认值
    if [ "$QUICK_INSTALL" = true ]; then
        gecho "使用默认用户名: $SERVICE_USER"
        return 0
    fi

    local username=""
    while true; do
        read -rep "$(yecho "请输入用户名(默认: $SERVICE_USER,直接回车使用): ")" input
        if [[ -z "$input" ]]; then
            username=$SERVICE_USER
        else
            username="$input"
        fi

        if validate_username "$username"; then
            gecho "用户名校验通过：$username"
            SERVICE_USER="$username" # 设置全局变量
            return 0
        fi
        yecho "请重新输入符合规则的用户名"
    done
}

# 创建服务用户
create_service_user() {
    local username="$SERVICE_USER"
    if [ "$username" = "rsync" ]; then
        if id rsync &>/dev/null; then
            return 0
        else
            :
        fi
    fi
    gecho "创建系统用户：$username"
    if useradd -M -s /sbin/nologin -r "$username" &>/dev/null; then
        gecho "用户创建成功：$username(无家目录,不可登录)"
    else
        recho "创建用户失败，请检查权限"
        exit 1
    fi
}

# 认证文件
auth_file() {
    # 快速安装模式下直接使用默认值
    if [ "$QUICK_INSTALL" = true ]; then
        gecho "使用默认认证文件路径: $SECRETS_FILE"
        return 0
    fi

    local num=""
    read -rep "$(yecho "请输入认证文件路径(默认: $SECRETS_FILE,直接回车使用): ")" authfile
    if [[ -z "$authfile" ]]; then
        authfile="$SECRETS_FILE"
    fi
    while true; do
        if [ -f "$authfile" ]; then
            yecho "文件已存在,是否使用该文件?"
            yecho "(会清空文件内容)"
        else
            break
        fi
        cat <<EOF
        1.继续使用
        2.不使用
EOF
        read -rep "请选择: " num
        case "$num" in
        1)
            break
            ;;
        2)
            read -rep "$(yecho "请输入认证文件路径(默认: $SECRETS_FILE,直接回车使用): ")" authfile
            if [[ -z "$authfile" ]]; then
                authfile="$SECRETS_FILE"
            fi
            continue
            ;;
        *)
            recho "请输入正确的数字"
            continue
            ;;
        esac

    done
    SECRETS_FILE="$authfile" # 更新全局变量
    gecho "认证文件路径设置为: $SECRETS_FILE"
}

# 认证用户和密码并写入密码文件和修改文件权限
auth_user() {
    # 快速安装模式
    if [ "$QUICK_INSTALL" = true ]; then
        gecho "使用默认认证用户名: $AUTH_USER"
        gecho "使用默认密码: $AUTH_PASSWORD"
        # 创建认证文件目录
        mkdir -p "$(dirname "$SECRETS_FILE")" &>/dev/null

        # 写入认证文件
        if echo "${AUTH_USER}:${AUTH_PASSWORD}" >"$SECRETS_FILE"; then
            gecho "认证用户,认证密码,写入文件成功"
        else
            recho "认证用户,认证密码,写入文件失败"
            exit 1
        fi
        # 修改文件权限
        if chmod 600 "$SECRETS_FILE"; then
            gecho "修改密码文件权限600成功: $SECRETS_FILE"
        else
            recho "修改密码文件权限600失败"
            exit 1
        fi
        return 0
    fi
    local auth_user_input=""
    local auth_password=""
    # 交互模式
    # 认证用户名
    while true; do
        read -rep "$(yecho "请输入认证用户名(默认: $AUTH_USER,直接回车使用): ")" auth_user_input
        if [[ -z "$auth_user_input" ]]; then
            auth_user_input="$AUTH_USER"
        fi

        if validate_username "$auth_user_input"; then
            AUTH_USER="$auth_user_input" # 更新全局变量
            gecho "认证用户设置成功：$AUTH_USER"
            break
        else
            yecho "请重新输入符合规则的用户名"
        fi
    done

    # 认证密码
    while true; do
        read -resp "$(yecho "请输入认证密码: ")" auth_password
        echo
        if [[ -z "$auth_password" ]]; then
            recho "密码不能为空"
        else
            break
        fi
    done

    # 创建认证文件目录
    mkdir -p "$(dirname "$SECRETS_FILE")" &>/dev/null

    # 写入认证文件
    if echo "${AUTH_USER}:${auth_password}" >"$SECRETS_FILE"; then
        gecho "认证用户,认证密码,写入文件成功"
    else
        recho "认证用户,认证密码,写入文件失败"
        exit 1
    fi
    # 修改文件权限
    if chmod 600 "$SECRETS_FILE"; then
        gecho "修改密码文件权限600成功: $SECRETS_FILE"
    else
        recho "修改密码文件权限600失败"
        exit 1
    fi

}

# 模组部分,定义模组名字和路径,创建路径,并修改属主属组
module() {
    # 快速安装模式
    if [ "$QUICK_INSTALL" = true ]; then
        module_names=("$MODULE_NAME")
        module_paths=("$DATA_PATH")
        gecho "使用默认模组: $MODULE_NAME, 路径: $DATA_PATH"
        # 创建目录并设置权限
        gecho "开始创建目录并设置权限..."
        # 检查目录是否已存在
        if [[ -d "$DATA_PATH" ]]; then
            yecho "目录已存在: $DATA_PATH"
        else
            # 尝试创建目录
            if mkdir -p "$DATA_PATH" 2>/dev/null; then
                gecho "目录创建成功: $DATA_PATH"
            else
                recho "目录创建失败: $DATA_PATH (可能是权限不足或路径无效)"
                exit 1
            fi
        fi

        # 设置目录权限给服务用户
        if chown -R "$SERVICE_USER:$SERVICE_USER" "$DATA_PATH" 2>/dev/null; then
            gecho "目录权限设置成功: $DATA_PATH -> $SERVICE_USER"
        else
            recho "目录权限设置失败: $DATA_PATH (可能是用户不存在或权限不足)"
        fi
        return 0
    fi
    # 交互模式
    module_names=()
    module_paths=()

    # 第一次输入，使用默认值
    read -rep "$(yecho "请输入模组名称(默认: $MODULE_NAME,直接回车使用): ")" input_name
    read -rep "$(yecho "请输入模组共享路径(默认: $DATA_PATH,直接回车使用): ")" input_path

    # 使用默认值如果用户输入为空
    local current_name=${input_name:-$MODULE_NAME}
    local current_path=${input_path:-$DATA_PATH}

    # 将第一次输入的值添加到数组
    module_names+=("$current_name")
    module_paths+=("$current_path")

    gecho "已添加模组: $current_name, 路径: $current_path"

    # 循环添加更多模组
    while true; do
        cat <<EOF
        1.继续添加
        2.不继续
EOF
        read -rep "$(yecho "是否继续添加: ")" choose_num

        case "$choose_num" in
        1)
            # 继续添加，没有默认值

            while true; do
                read -rep "$(yecho "请输入模组名称: ")" current_name
                if [ -z "$current_name" ]; then
                    recho "模组名,不能为空,请重新输入"
                    continue
                fi
                # 检查模组名称是否已存在
                local name_exists=false
                for name in "${module_names[@]}"; do
                    if [[ "$name" == "$current_name" ]]; then
                        recho "模组名称 '$current_name' 已存在，请使用其他名称"
                        name_exists=true
                        break
                    fi
                done

                # 如果名称不存在，跳出内层循环
                if [[ "$name_exists" == false ]]; then
                    break
                fi
            done
            while true; do
                read -rep "$(yecho "请输入模组共享路径: ")" current_path
                if [ -z "$current_path" ]; then
                    recho "共享路径,不能为空,请重新输入"
                else
                    break
                fi
            done

            # 将新值添加到数组
            module_names+=("$current_name")
            module_paths+=("$current_path")

            gecho "已添加模组: $current_name, 路径: $current_path"
            ;;
        2)
            gecho "模组添加完成"
            break
            ;;
        *)
            recho "请输入正确的数字"
            ;;
        esac
    done

    # 创建目录并设置权限
    gecho "开始创建目录并设置权限..."
    for i in "${!module_paths[@]}"; do
        local path="${module_paths[$i]}"
        local name="${module_names[$i]}"

        # 检查目录是否已存在
        if [[ -d "$path" ]]; then
            yecho "目录已存在: $path"
        else
            # 尝试创建目录
            if mkdir -p "$path" 2>/dev/null; then
                gecho "目录创建成功: $path"
            else
                recho "目录创建失败: $path (可能是权限不足或路径无效)"
                exit 1
            fi
        fi

        # 设置目录权限给服务用户
        if chown -R "$SERVICE_USER:$SERVICE_USER" "$path" 2>/dev/null; then
            gecho "目录权限设置成功: $path -> $SERVICE_USER"
        else
            recho "目录权限设置失败: $path (可能是用户不存在或权限不足)"
        fi
    done
}

# 生成rsync配置文件
generate_config() {
    gecho "生成rsync配置文件: /etc/rsyncd.conf"
    cat >/etc/rsyncd.conf <<EOF
#created by oldboy 15:01 2009-6-5
##rsyncd.conf start##
fake super =yes 
uid = $SERVICE_USER
gid = $SERVICE_USER
use chroot = no
max connections = 2000
timeout = 600
pid file = /var/run/rsyncd.pid
lock file = /var/run/rsync.lock
log file = /var/log/rsyncd.log
ignore errors
read only = false
list = false
#hosts allow = 172.16.1.0/24
#hosts deny = 0.0.0.0/32
auth users = $AUTH_USER
secrets file = $SECRETS_FILE
#####################################

EOF
    # 遍历模组数组，为每个模组生成配置段
    for i in "${!module_names[@]}"; do
        local name="${module_names[$i]}"
        local path="${module_paths[$i]}"

        cat >>/etc/rsyncd.conf <<EOF
[$name]
comment = www by old0boy 14:18 2012-1-13
path = $path

EOF
    done
    gecho "rsync配置文件生成完成"
}

# 启动
start() {
    gecho "服务启动中,请稍后-----"
    systemctl enable --now $RSYNC_NAME &>/dev/nnull
    systemctl restart $RSYNC_NAME &>/dev/nnull
    sleep 5
}

check() {
    #服务状态
    is_active=$(systemctl is-active $RSYNC_NAME)
    is_enable=$(systemctl is-enabled $RSYNC_NAME)
    if [[ "$is_active" = "active" && "$is_enable" = "enabled" ]]; then
        gecho "服务启动中"
        gecho "开机自启状态    :$is_enable"
        gecho "当前运行状态    :$is_active"
    else
        recho "服务未能成功启动"
        recho "开机自启状态    :$is_enable"
        recho "当前运行状态    :$is_active"
    fi
    #进程
    if pgrep rsync &>/dev/null; then
        gecho "进程已经运行"
    else
        recho "未检测到进程"
    fi
    #端口
    echo "=== 873端口检查 ==="
    if ss -lntup | grep -q ":873 "; then
        if ss -lntup | grep ":873 " | grep -q "rsync"; then
            gecho "✓ rsync正在监听873端口"
        else
            recho "✗ 873端口被其他进程占用"
            ss -lntup | grep ":873 "
            exit 17
        fi
    else
        yecho "! 873端口未被占用(rsync可能未启动或配置了其他端口)"
    fi
}
# 主函数
main() {
    gecho "开始安装和配置rsync服务"
    # 选择安装模式
    select_install_mode

    # 安装rsync
    install_rsync

    # 获取并创建用户
    get_valid_username
    create_service_user

    # 认证文件
    auth_file
    auth_user

    # 模组配置
    module
    generate_config
    # 启动和检查
    start
    check
    # 输出配置
    gecho "rsync服务配置完成!"
    gecho "服务用户:   $SERVICE_USER"
    gecho "认证文件:   $SECRETS_FILE"
    gecho "认证用户名: $AUTH_USER"
    gecho "配置文件: /etc/rsyncd.conf"

    # 提醒
    if [ "$QUICK_INSTALL" = true ]; then
        echo
        yecho "重要提示：请妥善保存密码！"
        yecho "您可以在 $SECRETS_FILE 文件中查看密码"
    fi
}

# 执行主函数
main

#!/bin/bash

# 代理服务器一键安装脚本
# 支持HTTP/SOCKS5代理，带用户认证功能
# 适用于Ubuntu系统

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误：请使用root用户运行此脚本${PLAIN}"
        exit 1
    fi
}

# 检查系统环境
check_system() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "${ID}" != "ubuntu" ]]; then
            echo -e "${RED}错误：此脚本仅支持Ubuntu系统${PLAIN}"
            exit 1
        fi
        echo -e "${GREEN}系统检测通过：${ID} ${VERSION_ID}${PLAIN}"
    else
        echo -e "${RED}错误：无法确定操作系统类型${PLAIN}"
        exit 1
    fi
}

# 更新系统并安装依赖
install_dependencies() {
    echo -e "${BLUE}正在更新系统并安装依赖...${PLAIN}"
    apt update -y
    apt install -y curl wget net-tools ufw
    echo -e "${GREEN}依赖安装完成${PLAIN}"
}

# 安装SOCKS5代理服务器(Dante)
install_dante() {
    echo -e "${BLUE}正在安装SOCKS5代理服务器(Dante)...${PLAIN}"
    apt install -y dante-server
    
    # 备份原配置文件
    if [[ -f /etc/danted.conf ]]; then
        mv /etc/danted.conf /etc/danted.conf.bak
    fi
    
    # 获取主网卡名称
    INTERFACE=$(ip -o -4 route show to default | awk '{print $5}')
    
    # 创建新的配置文件
    cat > /etc/danted.conf << EOF
# Dante SOCKS5代理服务器配置
logoutput: syslog
user.privileged: root
user.unprivileged: nobody

# 监听地址和端口
internal: 0.0.0.0 port=10808

# 出口网卡
external: ${INTERFACE}

# 认证方法：用户名密码认证
socksmethod: username

# 客户端认证方法
clientmethod: none

# 客户端规则
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
}

# SOCKS规则
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
}
EOF
    
    # 重启Dante服务
    systemctl restart danted.service
    systemctl enable danted.service
    
    echo -e "${GREEN}SOCKS5代理服务器(Dante)安装完成${PLAIN}"
}

# 安装HTTP代理服务器(Squid)
install_squid() {
    echo -e "${BLUE}正在安装HTTP代理服务器(Squid)...${PLAIN}"
    apt install -y squid apache2-utils
    
    # 备份原配置文件
    if [[ -f /etc/squid/squid.conf ]]; then
        mv /etc/squid/squid.conf /etc/squid/squid.conf.bak
    fi
    
    # 创建密码文件
    touch /etc/squid/passwd
    chmod 777 /etc/squid/passwd
    
    # 创建新的配置文件
    cat > /etc/squid/squid.conf << EOF
# Squid HTTP代理服务器配置

# 基本设置
http_port 3128
visible_hostname proxy.local

# 访问控制
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic realm Proxy Authentication
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all

# 其他设置
request_header_access Via deny all
request_header_access X-Forwarded-For deny all
request_header_access From deny all
forwarded_for delete
EOF
    
    # 重启Squid服务
    systemctl restart squid
    systemctl enable squid
    
    echo -e "${GREEN}HTTP代理服务器(Squid)安装完成${PLAIN}"
}

# 配置防火墙
configure_firewall() {
    echo -e "${BLUE}正在配置防火墙...${PLAIN}"
    
    # 检查防火墙状态
    ufw status | grep -q "Status: active"
    if [[ $? -ne 0 ]]; then
        ufw --force enable
    fi
    
    # 开放代理端口
    ufw allow 10808/tcp
    ufw allow 3128/tcp
    
    echo -e "${GREEN}防火墙配置完成${PLAIN}"
}

# 创建代理用户
create_proxy_user() {
    echo -e "${BLUE}正在创建代理用户...${PLAIN}"
    
    # 提示用户输入用户名和密码
    read -p "请输入SOCKS5代理用户名: " SOCKS_USER
    read -s -p "请输入SOCKS5代理密码: " SOCKS_PASS
    echo ""
    
    # 创建SOCKS5代理用户
    useradd -r -s /bin/false ${SOCKS_USER} 2>/dev/null || true
    echo "${SOCKS_USER}:${SOCKS_PASS}" | chpasswd
    
    # 创建HTTP代理用户
    htpasswd -bc /etc/squid/passwd ${SOCKS_USER} ${SOCKS_PASS}
    
    echo -e "${GREEN}代理用户创建完成${PLAIN}"
}

# 显示代理信息
show_proxy_info() {
    # 获取服务器IP
    SERVER_IP=$(curl -s https://api.ipify.org)
    if [[ -z "${SERVER_IP}" ]]; then
        SERVER_IP=$(ip -4 addr | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "127.0.0.1" | head -n 1)
    fi
    
    echo -e "\n${CYAN}========== 代理服务器信息 ==========${PLAIN}"
    echo -e "${GREEN}服务器IP地址：${SERVER_IP}${PLAIN}"
    echo -e "${GREEN}SOCKS5代理端口：10808${PLAIN}"
    echo -e "${GREEN}HTTP代理端口：3128${PLAIN}"
    echo -e "${GREEN}用户名：${SOCKS_USER}${PLAIN}"
    echo -e "${GREEN}密码：${SOCKS_PASS}${PLAIN}"
    echo -e "${CYAN}====================================${PLAIN}"
    
    # 创建使用说明文件
    cat > /root/proxy_info.txt << EOF
========== 代理服务器信息 ==========
服务器IP地址：${SERVER_IP}
SOCKS5代理端口：10808
HTTP代理端口：3128
用户名：${SOCKS_USER}
密码：${SOCKS_PASS}
====================================

使用方法：
1. SOCKS5代理：
   - 地址：${SERVER_IP}
   - 端口：10808
   - 用户名：${SOCKS_USER}
   - 密码：${SOCKS_PASS}

2. HTTP代理：
   - 地址：${SERVER_IP}
   - 端口：3128
   - 用户名：${SOCKS_USER}
   - 密码：${SOCKS_PASS}
EOF
    
    echo -e "\n${YELLOW}使用说明已保存至 /root/proxy_info.txt${PLAIN}"
}

# 主函数
main() {
    clear
    echo -e "${CYAN}========== HTTP/SOCKS5代理服务器一键安装脚本 ==========${PLAIN}"
    echo -e "${CYAN}支持：Ubuntu系统${PLAIN}"
    echo -e "${CYAN}功能：安装HTTP和SOCKS5代理服务器，支持用户认证${PLAIN}"
    echo -e "${CYAN}=======================================================${PLAIN}\n"
    
    # 检查root权限
    check_root
    
    # 检查系统环境
    check_system
    
    # 安装依赖
    install_dependencies
    
    # 安装SOCKS5代理(Dante)
    install_dante
    
    # 安装HTTP代理(Squid)
    install_squid
    
    # 配置防火墙
    configure_firewall
    
    # 创建代理用户
    create_proxy_user
    
    # 显示代理信息
    show_proxy_info
    
    echo -e "\n${GREEN}HTTP/SOCKS5代理服务器安装完成！${PLAIN}"
}

# 执行主函数
main

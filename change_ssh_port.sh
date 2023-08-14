#!/bin/bash

# 函数：打印错误信息并继续
print_error() {
    echo "错误：$1"
}

# 函数：验证端口号输入
validate_port_number() {
    if ! [[ "$1" =~ ^[0-9]+$ ]]  (( "$1" < 1  "$1" > 65535 )); then
        print_error "无效的端口号。请输入1到65535之间的有效端口号。"
        return 1
    fi
    return 0
}

echo "欢迎使用SSH端口配置脚本，请根据我的提示来进行操作"

# 检查脚本是否以root权限运行
if [ "$EUID" -ne 0 ]; then
    print_error "此脚本必须以root权限运行。"
    exit 1
fi

# 检测系统发行版
if [ -f /etc/os-release ]; then
    source /etc/os-release
    if [ "$ID" == "centos" ] || [ "$ID" == "rocky" ]; then
        # CentOS 或 Rocky Linux
        system_type="centos"
    elif [ "$ID" == "ubuntu" ]; then
        # Ubuntu
        system_type="ubuntu"
    else
        print_error "不支持的系统。仅支持CentOS、Rocky Linux和Ubuntu。"
        exit 1
    fi
else
    print_error "无法获取系统信息。"
    exit 1
fi

# 提示用户是否允许root登录
allow_root=""
while [[ "$allow_root" != "y" && "$allow_root" != "n" ]]; do
    read -p "是否允许root登录 (y/n)？ " allow_root
    if [[ "$allow_root" != "y" && "$allow_root" != "n" ]]; then
        print_error "无效的输入。请输入'y'或'n'。"
    fi
done

if [ "$allow_root" = "y" ]; then
    sed -i 's/PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    echo "已允许root登录。"
elif [ "$allow_root" = "n" ]; then
    sed -i 's/PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    echo "已禁止root登录。"
fi

# 读取当前SSH端口号
current_port=$(grep -E "^Port" /etc/ssh/sshd_config | awk '{print $2}')

# 提示用户输入新的SSH端口号
while true; do
    read -p "请输入新的SSH端口号： " new_port
    if validate_port_number "$new_port"; then
        break
    fi
done

# 修改sshd_config中的SSH端口号
sed -i "s/Port $current_port/Port $new_port/" /etc/ssh/sshd_config
echo "SSH端口号已更改为：$new_port。"

# 重启SSH服务
if [ "$system_type" = "centos" ] || [ "$system_type" = "rocky" ]; then
    systemctl restart sshd
else
    service ssh restart
fi

# 检查 iptables 是否运行
if command -v iptables &>/dev/null; then
    # 使用iptables
    iptables_running=$(systemctl is-active iptables)
    if [ "$iptables_running" = "active" ]; then
        iptables -D INPUT -p tcp --dport "$current_port" -j ACCEPT
        iptables -A INPUT -p tcp --dport "$new_port" -j ACCEPT
        service iptables save
        service iptables restart
    fi
fi

# 检查 firewalld 是否运行
if [ "$system_type" = "centos" ] || [ "$system_type" = "rocky" ] && command -v firewall-cmd &>/dev/null; then
    if systemctl is-active --quiet firewalld; then
        firewall-cmd --zone=public --remove-port="$current_port"/tcp
        firewall-cmd --zone=public --add-port="$new_port"/tcp --permanent
        firewall-cmd --reload
    fi
fi

# 检查 ufw 是否运行
if [ "$system_type" = "ubuntu" ] && command -v ufw &>/dev/null; then
    if ! ufw status | grep -q "Status: active"; then
        apt-get install ufw -y
        ufw enable
    fi
    ufw delete allow "$current_port"/tcp
    ufw allow "$new_port"/tcp
    ufw reload
fi

echo "防火墙已配置。"

echo "SSH端口已更改为：$new_port。"
echo "您现在可以使用： ssh 用户名@主机IP地址 -p $new_port"

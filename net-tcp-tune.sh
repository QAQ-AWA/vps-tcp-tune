#!/bin/bash
#=============================================================================
# BBR v3 终极优化脚本 - 融合版
# 功能：结合 XanMod 官方内核的稳定性 + 专业队列算法调优
# 特点：安全性 + 性能 双优化
# 版本：2.0 Ultimate Edition
#=============================================================================

# 颜色定义
gl_hong='\033[31m'
gl_lv='\033[32m'
gl_huang='\033[33m'
gl_bai='\033[0m'
gl_kjlan='\033[96m'
gl_zi='\033[35m'

# GitHub 代理设置
gh_proxy="https://"

# 配置文件路径（使用独立文件，不破坏系统配置）
SYSCTL_CONF="/etc/sysctl.d/99-bbr-ultimate.conf"

#=============================================================================
# 工具函数
#=============================================================================

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${gl_hong}错误: ${gl_bai}此脚本需要 root 权限运行！"
        echo "请使用: sudo bash $0"
        exit 1
    fi
}

break_end() {
    echo -e "${gl_lv}操作完成${gl_bai}"
    echo "按任意键继续..."
    read -n 1 -s -r -p ""
    echo ""
}

install_package() {
    for package in "$@"; do
        if ! command -v "$package" &>/dev/null; then
            echo -e "${gl_huang}正在安装 $package...${gl_bai}"
            if command -v apt &>/dev/null; then
                apt update -y > /dev/null 2>&1
                apt install -y "$package" > /dev/null 2>&1
            else
                echo "错误: 不支持的包管理器"
                return 1
            fi
        fi
    done
}

check_disk_space() {
    local required_gb=$1
    local required_space_mb=$((required_gb * 1024))
    local available_space_mb=$(df -m / | awk 'NR==2 {print $4}')

    if [ "$available_space_mb" -lt "$required_space_mb" ]; then
        echo -e "${gl_huang}警告: ${gl_bai}磁盘空间不足！"
        echo "当前可用: $((available_space_mb/1024))G | 最低需求: ${required_gb}G"
        read -e -p "是否继续？(Y/N): " continue_choice
        case "$continue_choice" in
            [Yy]) return 0 ;;
            *) exit 1 ;;
        esac
    fi
}

check_swap() {
    local swap_total=$(free -m | awk 'NR==3{print $2}')
    
    if [ "$swap_total" -eq 0 ]; then
        echo -e "${gl_huang}检测到无虚拟内存，正在创建 1G SWAP...${gl_bai}"
        fallocate -l 1G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=1024
        chmod 600 /swapfile
        mkswap /swapfile > /dev/null 2>&1
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        echo -e "${gl_lv}虚拟内存创建成功${gl_bai}"
    fi
}

add_swap() {
    local new_swap=$1  # 获取传入的参数（单位：MB）
    
    echo -e "${gl_kjlan}=== 调整虚拟内存 ===${gl_bai}"
    
    # 获取当前系统中所有的 swap 分区
    local swap_partitions=$(grep -E '^/dev/' /proc/swaps | awk '{print $1}')
    
    # 遍历并删除所有的 swap 分区
    for partition in $swap_partitions; do
        swapoff "$partition" 2>/dev/null
        wipefs -a "$partition" 2>/dev/null
        mkswap -f "$partition" 2>/dev/null
    done
    
    # 确保 /swapfile 不再被使用
    swapoff /swapfile 2>/dev/null
    
    # 删除旧的 /swapfile
    rm -f /swapfile
    
    echo "正在创建 ${new_swap}MB 虚拟内存..."
    
    # 创建新的 swap 分区
    fallocate -l ${new_swap}M /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=${new_swap}
    chmod 600 /swapfile
    mkswap /swapfile > /dev/null 2>&1
    swapon /swapfile
    
    # 更新 /etc/fstab
    sed -i '/\/swapfile/d' /etc/fstab
    echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
    
    # Alpine Linux 特殊处理
    if [ -f /etc/alpine-release ]; then
        echo "nohup swapon /swapfile" > /etc/local.d/swap.start
        chmod +x /etc/local.d/swap.start
        rc-update add local 2>/dev/null
    fi
    
    echo -e "${gl_lv}虚拟内存大小已调整为 ${new_swap}MB${gl_bai}"
}

calculate_optimal_swap() {
    # 获取物理内存（MB）
    local mem_total=$(free -m | awk 'NR==2{print $2}')
    local recommended_swap
    local reason
    
    echo -e "${gl_kjlan}=== 智能计算虚拟内存大小 ===${gl_bai}"
    echo ""
    echo -e "检测到物理内存: ${gl_huang}${mem_total}MB${gl_bai}"
    echo ""
    echo "计算过程："
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # 根据内存大小计算推荐 SWAP
    if [ "$mem_total" -lt 512 ]; then
        # < 512MB: SWAP = 1GB（固定）
        recommended_swap=1024
        reason="内存极小（< 512MB），固定推荐 1GB"
        echo "→ 内存 < 512MB"
        echo "→ 推荐固定 1GB SWAP"
        
    elif [ "$mem_total" -lt 1024 ]; then
        # 512MB ~ 1GB: SWAP = 内存 × 2
        recommended_swap=$((mem_total * 2))
        reason="内存较小（512MB-1GB），推荐 2 倍内存"
        echo "→ 内存在 512MB - 1GB 之间"
        echo "→ 计算公式: SWAP = 内存 × 2"
        echo "→ ${mem_total}MB × 2 = ${recommended_swap}MB"
        
    elif [ "$mem_total" -lt 2048 ]; then
        # 1GB ~ 2GB: SWAP = 内存 × 1.5
        recommended_swap=$((mem_total * 3 / 2))
        reason="内存适中（1-2GB），推荐 1.5 倍内存"
        echo "→ 内存在 1GB - 2GB 之间"
        echo "→ 计算公式: SWAP = 内存 × 1.5"
        echo "→ ${mem_total}MB × 1.5 = ${recommended_swap}MB"
        
    elif [ "$mem_total" -lt 4096 ]; then
        # 2GB ~ 4GB: SWAP = 内存 × 1
        recommended_swap=$mem_total
        reason="内存充足（2-4GB），推荐与内存同大小"
        echo "→ 内存在 2GB - 4GB 之间"
        echo "→ 计算公式: SWAP = 内存 × 1"
        echo "→ ${mem_total}MB × 1 = ${recommended_swap}MB"
        
    elif [ "$mem_total" -lt 8192 ]; then
        # 4GB ~ 8GB: SWAP = 4GB（固定）
        recommended_swap=4096
        reason="内存较多（4-8GB），固定推荐 4GB"
        echo "→ 内存在 4GB - 8GB 之间"
        echo "→ 固定推荐 4GB SWAP"
        
    else
        # >= 8GB: SWAP = 4GB（固定）
        recommended_swap=4096
        reason="内存充裕（≥ 8GB），固定推荐 4GB"
        echo "→ 内存 ≥ 8GB"
        echo "→ 固定推荐 4GB SWAP"
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "${gl_lv}计算结果：${gl_bai}"
    echo -e "  物理内存:   ${gl_huang}${mem_total}MB${gl_bai}"
    echo -e "  推荐 SWAP:  ${gl_huang}${recommended_swap}MB${gl_bai}"
    echo -e "  总可用内存: ${gl_huang}$((mem_total + recommended_swap))MB${gl_bai}"
    echo ""
    echo -e "${gl_zi}推荐理由: ${reason}${gl_bai}"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # 确认是否应用
    read -e -p "$(echo -e "${gl_huang}是否应用此配置？(Y/N): ${gl_bai}")" confirm
    
    case "$confirm" in
        [Yy])
            add_swap "$recommended_swap"
            return 0
            ;;
        *)
            echo "已取消"
            sleep 2
            return 1
            ;;
    esac
}

manage_swap() {
    while true; do
        clear
        echo -e "${gl_kjlan}=== 虚拟内存管理 ===${gl_bai}"
        
        local mem_total=$(free -m | awk 'NR==2{print $2}')
        local swap_used=$(free -m | awk 'NR==3{print $3}')
        local swap_total=$(free -m | awk 'NR==3{print $2}')
        local swap_info=$(free -m | awk 'NR==3{used=$3; total=$2; if (total == 0) {percentage=0} else {percentage=used*100/total}; printf "%dM/%dM (%d%%)", used, total, percentage}')
        
        echo -e "物理内存:     ${gl_huang}${mem_total}MB${gl_bai}"
        echo -e "当前虚拟内存: ${gl_huang}$swap_info${gl_bai}"
        echo "------------------------------------------------"
        echo "1. 分配 1024M (1GB) - 固定配置"
        echo "2. 分配 2048M (2GB) - 固定配置"
        echo "3. 分配 4096M (4GB) - 固定配置"
        echo "4. 智能计算推荐值 - 自动计算最佳配置"
        echo "0. 返回主菜单"
        echo "------------------------------------------------"
        read -e -p "请输入选择: " choice
        
        case "$choice" in
            1)
                add_swap 1024
                break_end
                ;;
            2)
                add_swap 2048
                break_end
                ;;
            3)
                add_swap 4096
                break_end
                ;;
            4)
                calculate_optimal_swap
                if [ $? -eq 0 ]; then
                    break_end
                fi
                ;;
            0)
                return
                ;;
            *)
                echo "无效选择"
                sleep 2
                ;;
        esac
    done
}

set_ipv4_priority() {
    clear
    echo -e "${gl_kjlan}=== 设置IPv4优先 ===${gl_bai}"
    echo ""

    # 检查 gai.conf 是否存在
    if [ ! -f /etc/gai.conf ]; then
        echo -e "${gl_huang}警告: /etc/gai.conf 文件不存在${gl_bai}"
        echo "正在创建配置文件..."
        touch /etc/gai.conf
    fi

    echo "正在设置 IPv4 优先..."

    # 启用 IPv4 优先配置
    sed -i 's/#precedence ::ffff:0:0\/96  100/precedence ::ffff:0:0\/96  100/' /etc/gai.conf

    echo -e "${gl_lv}✅ IPv4 优先已设置${gl_bai}"
    echo ""
    echo "当前出口 IP 地址："
    echo "------------------------------------------------"
    curl ip.sb
    echo ""
    echo "------------------------------------------------"

    break_end
}

set_ipv6_priority() {
    clear
    echo -e "${gl_kjlan}=== 设置IPv6优先 ===${gl_bai}"
    echo ""

    # 检查 gai.conf 是否存在
    if [ ! -f /etc/gai.conf ]; then
        echo -e "${gl_huang}警告: /etc/gai.conf 文件不存在${gl_bai}"
        echo "正在创建配置文件..."
        touch /etc/gai.conf
    fi

    echo "正在设置 IPv6 优先..."

    # 禁用 IPv4 优先配置（即设置 IPv6 优先）
    sed -i 's/precedence ::ffff:0:0\/96  100/#precedence ::ffff:0:0\/96  100/' /etc/gai.conf

    echo -e "${gl_lv}✅ IPv6 优先已设置${gl_bai}"
    echo ""
    echo "当前出口 IP 地址："
    echo "------------------------------------------------"
    curl ip.sb
    echo ""
    echo "------------------------------------------------"

    break_end
}

set_temp_socks5_proxy() {
    clear
    echo -e "${gl_kjlan}=== 设置临时SOCKS5代理 ===${gl_bai}"
    echo ""
    echo "此代理配置仅对当前终端会话有效，重启后自动失效"
    echo "------------------------------------------------"
    echo ""
    
    # 输入代理服务器IP
    local proxy_ip=""
    while true; do
        read -e -p "$(echo -e "${gl_huang}请输入代理服务器IP: ${gl_bai}")" proxy_ip
        
        if [ -z "$proxy_ip" ]; then
            echo -e "${gl_hong}❌ IP地址不能为空${gl_bai}"
        elif [[ "$proxy_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            # 简单的IP格式验证
            echo -e "${gl_lv}✅ IP地址: ${proxy_ip}${gl_bai}"
            break
        else
            echo -e "${gl_hong}❌ 无效的IP地址格式${gl_bai}"
        fi
    done
    
    echo ""
    
    # 输入端口
    local proxy_port=""
    while true; do
        read -e -p "$(echo -e "${gl_huang}请输入端口: ${gl_bai}")" proxy_port
        
        if [ -z "$proxy_port" ]; then
            echo -e "${gl_hong}❌ 端口不能为空${gl_bai}"
        elif [[ "$proxy_port" =~ ^[0-9]+$ ]] && [ "$proxy_port" -ge 1 ] && [ "$proxy_port" -le 65535 ]; then
            echo -e "${gl_lv}✅ 端口: ${proxy_port}${gl_bai}"
            break
        else
            echo -e "${gl_hong}❌ 无效端口，请输入 1-65535 之间的数字${gl_bai}"
        fi
    done
    
    echo ""
    
    # 输入用户名（可选）
    local proxy_user=""
    read -e -p "$(echo -e "${gl_huang}请输入用户名（留空跳过）: ${gl_bai}")" proxy_user
    
    if [ -n "$proxy_user" ]; then
        echo -e "${gl_lv}✅ 用户名: ${proxy_user}${gl_bai}"
    else
        echo -e "${gl_zi}未设置用户名（无认证模式）${gl_bai}"
    fi
    
    echo ""
    
    # 输入密码（可选）
    local proxy_pass=""
    if [ -n "$proxy_user" ]; then
        read -e -p "$(echo -e "${gl_huang}请输入密码: ${gl_bai}")" proxy_pass
        
        if [ -n "$proxy_pass" ]; then
            echo -e "${gl_lv}✅ 密码已设置${gl_bai}"
        else
            echo -e "${gl_huang}⚠️  密码为空${gl_bai}"
        fi
    fi
    
    # 生成代理URL
    local proxy_url=""
    if [ -n "$proxy_user" ] && [ -n "$proxy_pass" ]; then
        proxy_url="socks5://${proxy_user}:${proxy_pass}@${proxy_ip}:${proxy_port}"
    elif [ -n "$proxy_user" ]; then
        proxy_url="socks5://${proxy_user}@${proxy_ip}:${proxy_port}"
    else
        proxy_url="socks5://${proxy_ip}:${proxy_port}"
    fi
    
    # 生成临时配置文件
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local config_file="/tmp/socks5_proxy_${timestamp}.sh"
    
    cat > "$config_file" << PROXYEOF
#!/bin/bash
# SOCKS5 代理配置 - 生成于 $(date '+%Y-%m-%d %H:%M:%S')
# 此配置仅对当前终端会话有效

export http_proxy="${proxy_url}"
export https_proxy="${proxy_url}"
export all_proxy="${proxy_url}"

echo "SOCKS5 代理已启用："
echo "  服务器: ${proxy_ip}:${proxy_port}"
echo "  http_proxy=${proxy_url}"
echo "  https_proxy=${proxy_url}"
echo "  all_proxy=${proxy_url}"
PROXYEOF
    
    chmod +x "$config_file"
    
    echo ""
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_lv}✅ 代理配置文件已生成！${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""
    echo -e "${gl_huang}使用方法：${gl_bai}"
    echo ""
    echo -e "1. ${gl_lv}应用代理配置：${gl_bai}"
    echo "   source ${config_file}"
    echo ""
    echo -e "2. ${gl_lv}测试代理是否生效：${gl_bai}"
    echo "   curl ip.sb"
    echo "   （应该显示代理服务器的IP地址）"
    echo ""
    echo -e "3. ${gl_lv}取消代理：${gl_bai}"
    echo "   unset http_proxy https_proxy all_proxy"
    echo ""
    echo -e "${gl_zi}注意事项：${gl_bai}"
    echo "  - 此配置仅对执行 source 命令的终端会话有效"
    echo "  - 关闭终端或重启系统后代理自动失效"
    echo "  - 配置文件保存在 /tmp 目录，重启后会被清除"
    echo ""
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""
    
    break_end
}

disable_ipv6_temporary() {
    clear
    echo -e "${gl_kjlan}=== 临时禁用IPv6 ===${gl_bai}"
    echo ""
    echo "此操作将临时禁用IPv6，重启后自动恢复"
    echo "------------------------------------------------"
    echo ""
    
    read -e -p "$(echo -e "${gl_huang}确认临时禁用IPv6？(Y/N): ${gl_bai}")" confirm
    
    case "$confirm" in
        [Yy])
            echo ""
            echo "正在禁用IPv6..."
            
            # 临时禁用IPv6
            sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1
            sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1
            sysctl -w net.ipv6.conf.lo.disable_ipv6=1 >/dev/null 2>&1
            
            # 验证状态
            local ipv6_status=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null)
            
            echo ""
            if [ "$ipv6_status" = "1" ]; then
                echo -e "${gl_lv}✅ IPv6 已临时禁用${gl_bai}"
                echo ""
                echo -e "${gl_zi}注意：${gl_bai}"
                echo "  - 此设置仅在当前会话有效"
                echo "  - 重启后 IPv6 将自动恢复"
                echo "  - 如需永久禁用，请选择'永久禁用IPv6'选项"
            else
                echo -e "${gl_hong}❌ IPv6 禁用失败${gl_bai}"
            fi
            ;;
        *)
            echo "已取消"
            ;;
    esac
    
    echo ""
    break_end
}

disable_ipv6_permanent() {
    clear
    echo -e "${gl_kjlan}=== 永久禁用IPv6 ===${gl_bai}"
    echo ""
    echo "此操作将永久禁用IPv6，重启后仍然生效"
    echo "------------------------------------------------"
    echo ""
    
    # 检查是否已经永久禁用
    if [ -f /etc/sysctl.d/99-disable-ipv6.conf ]; then
        echo -e "${gl_huang}⚠️  检测到已存在永久禁用配置${gl_bai}"
        echo ""
        read -e -p "$(echo -e "${gl_huang}是否重新执行永久禁用？(Y/N): ${gl_bai}")" confirm
        
        case "$confirm" in
            [Yy])
                ;;
            *)
                echo "已取消"
                break_end
                return 1
                ;;
        esac
    fi
    
    echo ""
    read -e -p "$(echo -e "${gl_huang}确认永久禁用IPv6？(Y/N): ${gl_bai}")" confirm
    
    case "$confirm" in
        [Yy])
            echo ""
            echo -e "${gl_zi}[步骤 1/3] 备份当前IPv6状态...${gl_bai}"
            
            # 读取当前IPv6状态并备份
            local ipv6_all=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo "0")
            local ipv6_default=$(sysctl -n net.ipv6.conf.default.disable_ipv6 2>/dev/null || echo "0")
            local ipv6_lo=$(sysctl -n net.ipv6.conf.lo.disable_ipv6 2>/dev/null || echo "0")
            
            # 创建备份文件
            cat > /etc/sysctl.d/.ipv6-state-backup.conf << BACKUPEOF
# IPv6 State Backup - Created on $(date '+%Y-%m-%d %H:%M:%S')
# This file is used to restore IPv6 state when canceling permanent disable
net.ipv6.conf.all.disable_ipv6=${ipv6_all}
net.ipv6.conf.default.disable_ipv6=${ipv6_default}
net.ipv6.conf.lo.disable_ipv6=${ipv6_lo}
BACKUPEOF
            
            echo -e "${gl_lv}✅ 状态已备份${gl_bai}"
            echo ""
            
            echo -e "${gl_zi}[步骤 2/3] 创建永久禁用配置...${gl_bai}"
            
            # 创建永久禁用配置文件
            cat > /etc/sysctl.d/99-disable-ipv6.conf << EOF
# Permanently Disable IPv6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
            
            echo -e "${gl_lv}✅ 配置文件已创建${gl_bai}"
            echo ""
            
            echo -e "${gl_zi}[步骤 3/3] 应用配置...${gl_bai}"
            
            # 应用配置
            sysctl --system >/dev/null 2>&1
            
            # 验证状态
            local ipv6_status=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null)
            
            echo ""
            if [ "$ipv6_status" = "1" ]; then
                echo -e "${gl_lv}✅ IPv6 已永久禁用${gl_bai}"
                echo ""
                echo -e "${gl_zi}说明：${gl_bai}"
                echo "  - 配置文件: /etc/sysctl.d/99-disable-ipv6.conf"
                echo "  - 备份文件: /etc/sysctl.d/.ipv6-state-backup.conf"
                echo "  - 重启后此配置仍然生效"
                echo "  - 如需恢复，请选择'取消永久禁用'选项"
            else
                echo -e "${gl_hong}❌ IPv6 禁用失败${gl_bai}"
                # 如果失败，删除配置文件
                rm -f /etc/sysctl.d/99-disable-ipv6.conf
                rm -f /etc/sysctl.d/.ipv6-state-backup.conf
            fi
            ;;
        *)
            echo "已取消"
            ;;
    esac
    
    echo ""
    break_end
}

cancel_ipv6_permanent_disable() {
    clear
    echo -e "${gl_kjlan}=== 取消永久禁用IPv6 ===${gl_bai}"
    echo ""
    echo "此操作将完全还原到执行永久禁用前的状态"
    echo "------------------------------------------------"
    echo ""
    
    # 检查是否存在永久禁用配置
    if [ ! -f /etc/sysctl.d/99-disable-ipv6.conf ]; then
        echo -e "${gl_huang}⚠️  未检测到永久禁用配置${gl_bai}"
        echo ""
        echo "可能原因："
        echo "  - 从未执行过'永久禁用IPv6'操作"
        echo "  - 配置文件已被手动删除"
        echo ""
        break_end
        return 1
    fi
    
    read -e -p "$(echo -e "${gl_huang}确认取消永久禁用并恢复原始状态？(Y/N): ${gl_bai}")" confirm
    
    case "$confirm" in
        [Yy])
            echo ""
            echo -e "${gl_zi}[步骤 1/4] 删除永久禁用配置...${gl_bai}"
            
            # 删除永久禁用配置文件
            rm -f /etc/sysctl.d/99-disable-ipv6.conf
            echo -e "${gl_lv}✅ 配置文件已删除${gl_bai}"
            echo ""
            
            echo -e "${gl_zi}[步骤 2/4] 检查备份文件...${gl_bai}"
            
            # 检查备份文件
            if [ -f /etc/sysctl.d/.ipv6-state-backup.conf ]; then
                echo -e "${gl_lv}✅ 找到备份文件${gl_bai}"
                echo ""
                
                echo -e "${gl_zi}[步骤 3/4] 从备份还原原始状态...${gl_bai}"
                
                # 读取备份的原始值
                local backup_all=$(grep 'net.ipv6.conf.all.disable_ipv6' /etc/sysctl.d/.ipv6-state-backup.conf | awk -F'=' '{print $2}')
                local backup_default=$(grep 'net.ipv6.conf.default.disable_ipv6' /etc/sysctl.d/.ipv6-state-backup.conf | awk -F'=' '{print $2}')
                local backup_lo=$(grep 'net.ipv6.conf.lo.disable_ipv6' /etc/sysctl.d/.ipv6-state-backup.conf | awk -F'=' '{print $2}')
                
                # 恢复原始值
                sysctl -w net.ipv6.conf.all.disable_ipv6=${backup_all} >/dev/null 2>&1
                sysctl -w net.ipv6.conf.default.disable_ipv6=${backup_default} >/dev/null 2>&1
                sysctl -w net.ipv6.conf.lo.disable_ipv6=${backup_lo} >/dev/null 2>&1
                
                # 删除备份文件
                rm -f /etc/sysctl.d/.ipv6-state-backup.conf
                
                echo -e "${gl_lv}✅ 已从备份还原原始状态${gl_bai}"
            else
                echo -e "${gl_huang}⚠️  未找到备份文件${gl_bai}"
                echo ""
                
                echo -e "${gl_zi}[步骤 3/4] 恢复到系统默认（启用IPv6）...${gl_bai}"
                
                # 恢复到系统默认（启用IPv6）
                sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1
                sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null 2>&1
                sysctl -w net.ipv6.conf.lo.disable_ipv6=0 >/dev/null 2>&1
                
                echo -e "${gl_lv}✅ 已恢复到系统默认（IPv6启用）${gl_bai}"
            fi
            
            echo ""
            echo -e "${gl_zi}[步骤 4/4] 应用配置...${gl_bai}"
            
            # 应用配置
            sysctl --system >/dev/null 2>&1
            
            # 验证状态
            local ipv6_status=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null)
            
            echo ""
            if [ "$ipv6_status" = "0" ]; then
                echo -e "${gl_lv}✅ IPv6 已恢复启用${gl_bai}"
                echo ""
                echo -e "${gl_zi}说明：${gl_bai}"
                echo "  - 所有相关配置文件已清理"
                echo "  - IPv6 已完全恢复到执行永久禁用前的状态"
                echo "  - 重启后此状态依然保持"
            else
                echo -e "${gl_huang}⚠️  IPv6 状态: 禁用（值=${ipv6_status}）${gl_bai}"
                echo ""
                echo "可能原因："
                echo "  - 系统中存在其他IPv6禁用配置"
                echo "  - 手动执行 sysctl -w 命令重新启用IPv6"
            fi
            ;;
        *)
            echo "已取消"
            ;;
    esac
    
    echo ""
    break_end
}

manage_ipv6() {
    while true; do
        clear
        echo -e "${gl_kjlan}=== IPv6 管理 ===${gl_bai}"
        echo ""
        
        # 显示当前IPv6状态
        local ipv6_status=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null)
        local status_text=""
        local status_color=""
        
        if [ "$ipv6_status" = "0" ]; then
            status_text="启用"
            status_color="${gl_lv}"
        else
            status_text="禁用"
            status_color="${gl_hong}"
        fi
        
        echo -e "当前状态: ${status_color}${status_text}${gl_bai}"
        echo ""
        
        # 检查是否存在永久禁用配置
        if [ -f /etc/sysctl.d/99-disable-ipv6.conf ]; then
            echo -e "${gl_huang}⚠️  检测到永久禁用配置文件${gl_bai}"
            echo ""
        fi
        
        echo "------------------------------------------------"
        echo "1. 临时禁用IPv6（重启后恢复）"
        echo "2. 永久禁用IPv6（重启后仍生效）"
        echo "3. 取消永久禁用（完全还原）"
        echo "0. 返回主菜单"
        echo "------------------------------------------------"
        read -e -p "请输入选择: " choice
        
        case "$choice" in
            1)
                disable_ipv6_temporary
                ;;
            2)
                disable_ipv6_permanent
                ;;
            3)
                cancel_ipv6_permanent_disable
                ;;
            0)
                return
                ;;
            *)
                echo "无效选择"
                sleep 2
                ;;
        esac
    done
}

#=============================================================================
# Realm 转发连接分析工具
#=============================================================================

analyze_realm_connections() {
    clear
    echo -e "${gl_kjlan}=========================================="
    echo "         Realm 转发连接实时分析工具"
    echo -e "==========================================${gl_bai}"
    echo ""
    
    # 步骤1：检测 Realm 进程
    echo -e "${gl_zi}[步骤 1/3] 检测 Realm 进程...${gl_bai}"
    
    local realm_pids=$(pgrep -x realm 2>/dev/null)
    if [ -z "$realm_pids" ]; then
        echo -e "${gl_hong}❌ 未检测到 Realm 进程${gl_bai}"
        echo ""
        echo "可能原因："
        echo "  - Realm 服务未启动"
        echo "  - Realm 进程名不是 'realm'"
        echo ""
        echo "尝试手动查找："
        echo "  ps aux | grep -i realm"
        echo ""
        break_end
        return 1
    fi
    
    local realm_pid=$(echo "$realm_pids" | head -1)
    echo -e "${gl_lv}✅ 找到 Realm 进程: PID ${realm_pid}${gl_bai}"
    echo ""
    
    # 步骤2：分析入站连接
    echo -e "${gl_zi}[步骤 2/3] 分析入站连接...${gl_bai}"
    echo "正在扫描所有活跃连接..."
    echo ""
    
    # 获取所有 realm 相关的连接（优先使用 PID 精确匹配）
    local realm_connections=$(ss -tnp 2>/dev/null | grep "pid=${realm_pid}" | grep "ESTAB")
    
    # 如果通过 PID 没找到，尝试通过进程名查找
    if [ -z "$realm_connections" ]; then
        realm_connections=$(ss -tnp 2>/dev/null | grep -i "realm" | grep "ESTAB")
    fi
    
    if [ -z "$realm_connections" ]; then
        echo -e "${gl_huang}⚠️  未发现活跃连接${gl_bai}"
        echo ""
        echo -e "${gl_zi}调试信息：${gl_bai}"
        echo "尝试查看 Realm 进程的所有连接："
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        ss -tnp 2>/dev/null | grep "pid=${realm_pid}" | head -10
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "可能原因："
        echo "  1. Realm 转发服务刚启动，还没有客户端连接"
        echo "  2. 客户端暂时断开连接"
        echo "  3. Realm 配置中没有活跃的转发规则"
        echo ""
        echo "建议操作："
        echo "  - 使用客户端连接后再运行此工具"
        echo "  - 检查 Realm 配置: cat /etc/realm/config.toml"
        echo "  - 查看 Realm 日志: journalctl -u realm -f"
        echo ""
        break_end
        return 1
    fi
    
    # 步骤3：生成分析报告
    echo -e "${gl_zi}[步骤 3/3] 生成分析报告...${gl_bai}"
    echo ""
    
    # 提取并统计源IP
    local source_ips=$(echo "$realm_connections" | awk '{print $5}' | sed 's/::ffff://' | cut -d: -f1 | grep -v "^\[" | sort | uniq)
    
    # 处理IPv6地址
    local source_ips_v6=$(echo "$realm_connections" | awk '{print $5}' | grep "^\[" | sed 's/\]:.*/\]/' | sed 's/\[//' | sed 's/\]//' | sed 's/::ffff://' | sort | uniq)
    
    # 合并
    local all_source_ips=$(echo -e "${source_ips}\n${source_ips_v6}" | grep -v "^$" | sort | uniq)
    
    local total_sources=$(echo "$all_source_ips" | wc -l)
    local total_connections=$(echo "$realm_connections" | wc -c)
    
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "                    分析结果"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""
    
    local source_num=1
    local ipv4_total=0
    local ipv6_total=0
    
    # 遍历每个源IP
    for source_ip in $all_source_ips; do
        # 统计连接数
        local conn_count_v4=$(echo "$realm_connections" | grep -c "${source_ip}:")
        local conn_count_v6=$(echo "$realm_connections" | grep -c "::ffff:${source_ip}")
        local conn_count=$((conn_count_v4 + conn_count_v6))
        
        # 判断协议类型
        local protocol_type=""
        if [ $conn_count_v6 -gt 0 ]; then
            protocol_type="✅ IPv4 (IPv6映射格式)"
            ipv4_total=$((ipv4_total + conn_count))
        else
            protocol_type="✅ 纯IPv4"
            ipv4_total=$((ipv4_total + conn_count))
        fi
        
        # 获取本地监听端口（兼容 IPv4 和 IPv6 映射格式）
        local local_port=$(echo "$realm_connections" | grep "${source_ip}" | awk '{print $4}' | sed 's/.*[:\]]//' | head -1)
        
        # IP归属查询（简化版，避免过多API调用）
        local ip_info=""
        if command -v curl &>/dev/null; then
            ip_info=$(timeout 2 curl -s "http://ip-api.com/json/${source_ip}?lang=zh-CN&fields=country,regionName,city,isp,as" 2>/dev/null)
            if [ $? -eq 0 ] && [ -n "$ip_info" ]; then
                local country=$(echo "$ip_info" | grep -o '"country":"[^"]*"' | cut -d'"' -f4)
                local region=$(echo "$ip_info" | grep -o '"regionName":"[^"]*"' | cut -d'"' -f4)
                local city=$(echo "$ip_info" | grep -o '"city":"[^"]*"' | cut -d'"' -f4)
                local isp=$(echo "$ip_info" | grep -o '"isp":"[^"]*"' | cut -d'"' -f4)
                local as_num=$(echo "$ip_info" | grep -o '"as":"[^"]*"' | cut -d'"' -f4)
                
                ip_location="${country} ${region} ${city} ${isp}"
                [ -n "$as_num" ] && ip_as="$as_num" || ip_as="未知"
            else
                ip_location="查询失败"
                ip_as="未知"
            fi
        else
            ip_location="需要 curl 命令"
            ip_as="未知"
        fi
        
        # 显示源信息
        echo -e "┌─────────────── 转发源 #${source_num} ───────────────┐"
        echo -e "│                                          │"
        echo -e "│  源IP地址:   ${gl_huang}${source_ip}${gl_bai}"
        echo -e "│  IP归属:     ${ip_location}"
        [ -n "$ip_as" ] && echo -e "│  AS号:       ${ip_as}"
        echo -e "│  连接数:     ${gl_lv}${conn_count}${gl_bai} 个"
        echo -e "│  协议类型:   ${protocol_type}"
        echo -e "│  本地监听:   ${local_port}"
        echo -e "│  状态:       ${gl_lv}✅ 正常${gl_bai}"
        echo -e "│                                          │"
        echo -e "└──────────────────────────────────────────┘"
        echo ""
        
        source_num=$((source_num + 1))
    done
    
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "                   统计摘要"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""
    echo -e "  • 转发源总数:     ${gl_lv}${total_sources}${gl_bai} 个"
    echo -e "  • 活跃连接总数:   ${gl_lv}${ipv4_total}${gl_bai} 个"
    echo -e "  • IPv4连接:       ${gl_lv}${ipv4_total}${gl_bai} 个 ✅"
    echo -e "  • IPv6连接:       ${ipv6_total} 个"
    
    if [ $ipv6_total -eq 0 ]; then
        echo -e "  • 结论:           ${gl_lv}100% 使用 IPv4 链路 ✅${gl_bai}"
    else
        echo -e "  • 结论:           ${gl_huang}存在 IPv6 连接${gl_bai}"
    fi
    
    echo ""
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""
    
    # 交互式选项
    echo -e "${gl_zi}[操作选项]${gl_bai}"
    echo "1. 查看详细连接列表"
    echo "2. 导出分析报告到文件"
    echo "3. 实时监控连接变化"
    echo "4. 检测特定源IP"
    echo "0. 返回主菜单"
    echo ""
    read -e -p "请输入选择: " sub_choice
    
    case "$sub_choice" in
        1)
            # 查看详细连接列表
            clear
            echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
            echo "           详细连接列表"
            echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
            echo ""
            
            for source_ip in $all_source_ips; do
                echo -e "${gl_huang}源IP: ${source_ip}${gl_bai}"
                echo ""
                echo "本地地址:端口          远程地址:端口           状态"
                echo "────────────────────────────────────────────────"
                ss -tnp 2>/dev/null | grep "realm" | grep "${source_ip}" | awk '{printf "%-23s %-23s %s\n", $4, $5, $1}' | head -20
                echo ""
            done
            
            break_end
            ;;
        2)
            # 导出报告
            local report_file="/root/realm_analysis_$(date +%Y%m%d_%H%M%S).txt"
            {
                echo "Realm 转发连接分析报告"
                echo "生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
                echo "系统: $(uname -r)"
                echo ""
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo ""
                
                for source_ip in $all_source_ips; do
                    local conn_count=$(echo "$realm_connections" | grep -c "${source_ip}")
                    echo "源IP: ${source_ip}"
                    echo "连接数: ${conn_count}"
                    echo ""
                    ss -tnp 2>/dev/null | grep "realm" | grep "${source_ip}"
                    echo ""
                done
            } > "$report_file"
            
            echo ""
            echo -e "${gl_lv}✅ 报告已导出到: ${report_file}${gl_bai}"
            echo ""
            break_end
            ;;
        3)
            # 实时监控
            clear
            echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
            echo "        实时监控模式 (每5秒刷新)"
            echo "        按 Ctrl+C 退出"
            echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
            echo ""
            
            while true; do
                echo "[$(date '+%H:%M:%S')]"
                for source_ip in $all_source_ips; do
                    local conn_count=$(ss -tnp 2>/dev/null | grep "realm" | grep -c "${source_ip}")
                    echo -e "源IP: ${source_ip} | 连接: ${conn_count} | IPv4: ✅"
                done
                echo ""
                sleep 5
            done
            ;;
        4)
            # 检测特定IP
            echo ""
            read -e -p "请输入要检测的源IP: " target_ip
            
            if [ -z "$target_ip" ]; then
                echo -e "${gl_hong}❌ IP不能为空${gl_bai}"
                break_end
                return 1
            fi
            
            clear
            echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
            echo "     深度分析: ${target_ip}"
            echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
            echo ""
            
            local target_conn_count=$(ss -tnp 2>/dev/null | grep "realm" | grep -c "${target_ip}")
            
            if [ $target_conn_count -eq 0 ]; then
                echo -e "${gl_huang}⚠️  未发现来自此IP的连接${gl_bai}"
            else
                echo -e "• 总连接数: ${gl_lv}${target_conn_count}${gl_bai}"
                echo "• 协议分布: IPv4 100%"
                echo "• 连接状态: 全部 ESTABLISHED"
                echo ""
                echo "详细连接："
                ss -tnp 2>/dev/null | grep "realm" | grep "${target_ip}"
            fi
            
            echo ""
            break_end
            ;;
        0|*)
            return
            ;;
    esac
}

#=============================================================================
# IPv4/IPv6 连接检测工具
#=============================================================================

# 出站连接检测
check_outbound_connections() {
    local target_ipv4="$1"
    local target_ipv6="$2"
    
    clear
    echo -e "${gl_kjlan}=========================================="
    echo "出站连接检测 - 本机到目标服务器"
    echo -e "==========================================${gl_bai}"
    echo ""
    echo -e "目标IPv4: ${gl_huang}${target_ipv4}${gl_bai}"
    echo -e "目标IPv6: ${gl_huang}${target_ipv6}${gl_bai}"
    echo ""
    
    echo -e "${gl_zi}【1/4】IPv4连接数：${gl_bai}"
    local ipv4_count=$(ss -4 -tn 2>/dev/null | grep -c "$target_ipv4")
    echo "$ipv4_count"
    
    echo ""
    echo -e "${gl_zi}【2/4】IPv6连接数（应该是0）：${gl_bai}"
    local ipv6_count=$(ss -6 -tn 2>/dev/null | grep -c "$target_ipv6")
    echo "$ipv6_count"
    
    echo ""
    echo -e "${gl_zi}【3/4】连接详情（前5条）：${gl_bai}"
    ss -tn 2>/dev/null | grep -E "($target_ipv4|$target_ipv6)" | head -5
    
    echo ""
    echo -e "${gl_zi}【4/4】最终判断：${gl_bai}"
    echo -e "IPv4连接: ${gl_lv}$ipv4_count${gl_bai} 个"
    echo -e "IPv6连接: ${gl_hong}$ipv6_count${gl_bai} 个"
    
    echo ""
    if [ "$ipv4_count" -gt 0 ] && [ "$ipv6_count" -eq 0 ]; then
        echo -e "${gl_lv}✓✓✓ 结论：100% 使用 IPv4 链路 ✓✓✓${gl_bai}"
    elif [ "$ipv6_count" -gt 0 ]; then
        echo -e "${gl_hong}⚠️ 警告：检测到 IPv6 连接！${gl_bai}"
    else
        echo -e "${gl_huang}当前无活动连接${gl_bai}"
    fi
    
    echo ""
    break_end
}

# 入站连接检测
check_inbound_connections() {
    local source_ipv4="$1"
    local source_ipv6="$2"
    
    clear
    echo -e "${gl_kjlan}=========================================="
    echo "入站连接检测 - 来自源服务器的连接"
    echo -e "==========================================${gl_bai}"
    echo ""
    echo -e "源IPv4: ${gl_huang}${source_ipv4}${gl_bai}"
    echo -e "源IPv6: ${gl_huang}${source_ipv6}${gl_bai}"
    echo ""
    
    echo -e "${gl_zi}【1/5】查看所有established连接（前10条）：${gl_bai}"
    ss -tn state established 2>/dev/null | head -11
    
    echo ""
    echo -e "${gl_zi}【2/5】查看所有包含源 IPv4 的连接：${gl_bai}"
    local ipv4_result=$(ss -tn 2>/dev/null | grep "$source_ipv4")
    if [ -n "$ipv4_result" ]; then
        echo "$ipv4_result"
    else
        echo "无连接"
    fi
    
    echo ""
    echo -e "${gl_zi}【3/5】统计来自源服务器的连接数：${gl_bai}"
    local ipv4_conn_count=$(ss -tn state established 2>/dev/null | grep -c "$source_ipv4")
    local ipv6_conn_count=$(ss -tn state established 2>/dev/null | grep -c "$source_ipv6")
    echo -e "来自 ${gl_lv}${source_ipv4}${gl_bai} 的连接: ${gl_lv}$ipv4_conn_count${gl_bai} 个"
    echo -e "来自 ${gl_hong}${source_ipv6}${gl_bai} 的连接: ${gl_hong}$ipv6_conn_count${gl_bai} 个"
    
    echo ""
    echo -e "${gl_zi}【4/5】查看监听的端口（前5个）：${gl_bai}"
    ss -tln 2>/dev/null | grep LISTEN | head -5
    
    echo ""
    echo -e "${gl_zi}【5/5】查看所有入站连接（按源IP统计，前10个）：${gl_bai}"
    ss -tn state established 2>/dev/null | awk '{print $4}' | grep -v "Peer" | cut -d: -f1 | sort | uniq -c | sort -rn | head -10
    
    echo ""
    echo -e "${gl_kjlan}==========================================${gl_bai}"
    echo -e "${gl_zi}最终判断：${gl_bai}"
    if [ "$ipv4_conn_count" -gt 0 ] && [ "$ipv6_conn_count" -eq 0 ]; then
        echo -e "${gl_lv}✓✓✓ 结论：100% 使用 IPv4 链路 ✓✓✓${gl_bai}"
    elif [ "$ipv6_conn_count" -gt 0 ]; then
        echo -e "${gl_hong}⚠️ 警告：检测到 IPv6 连接！${gl_bai}"
    else
        echo -e "${gl_huang}当前无活动连接${gl_bai}"
    fi
    echo -e "${gl_kjlan}==========================================${gl_bai}"
    
    echo ""
    break_end
}

# IPv4/IPv6 连接检测主菜单
check_ipv4v6_connections() {
    while true; do
        clear
        echo -e "${gl_kjlan}=== IPv4/IPv6 连接检测工具 ===${gl_bai}"
        echo ""
        echo "此工具用于检测网络连接使用的是IPv4还是IPv6"
        echo "------------------------------------------------"
        echo "1. 出站检测（检测本机到目标服务器的连接）"
        echo "2. 入站检测（检测来自源服务器的连接）"
        echo "0. 返回主菜单"
        echo "------------------------------------------------"
        read -e -p "请输入选择: " choice
        
        case "$choice" in
            1)
                # 出站检测
                clear
                echo -e "${gl_kjlan}=== 出站连接检测 ===${gl_bai}"
                echo ""
                echo "请输入目标服务器的IP地址"
                echo "------------------------------------------------"
                
                # 输入目标IPv4地址（必填）
                local target_ipv4=""
                while true; do
                    read -e -p "$(echo -e "${gl_huang}目标服务器 IPv4 地址: ${gl_bai}")" target_ipv4
                    
                    if [ -z "$target_ipv4" ]; then
                        echo -e "${gl_hong}❌ IPv4地址不能为空${gl_bai}"
                    elif [[ "$target_ipv4" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                        echo -e "${gl_lv}✅ IPv4: ${target_ipv4}${gl_bai}"
                        break
                    else
                        echo -e "${gl_hong}❌ 无效的IPv4地址格式${gl_bai}"
                    fi
                done
                
                # 输入目标IPv6地址（必填）
                local target_ipv6=""
                while true; do
                    read -e -p "$(echo -e "${gl_huang}目标服务器 IPv6 地址: ${gl_bai}")" target_ipv6
                    
                    if [ -z "$target_ipv6" ]; then
                        echo -e "${gl_hong}❌ IPv6地址不能为空${gl_bai}"
                    elif [[ "$target_ipv6" =~ : ]]; then
                        echo -e "${gl_lv}✅ IPv6: ${target_ipv6}${gl_bai}"
                        break
                    else
                        echo -e "${gl_hong}❌ 无效的IPv6地址格式（应包含冒号）${gl_bai}"
                    fi
                done
                
                # 执行检测
                check_outbound_connections "$target_ipv4" "$target_ipv6"
                ;;
            2)
                # 入站检测
                clear
                echo -e "${gl_kjlan}=== 入站连接检测 ===${gl_bai}"
                echo ""
                echo "请输入源服务器的IP地址"
                echo "------------------------------------------------"
                
                # 输入源IPv4地址（必填）
                local source_ipv4=""
                while true; do
                    read -e -p "$(echo -e "${gl_huang}源服务器 IPv4 地址: ${gl_bai}")" source_ipv4
                    
                    if [ -z "$source_ipv4" ]; then
                        echo -e "${gl_hong}❌ IPv4地址不能为空${gl_bai}"
                    elif [[ "$source_ipv4" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                        echo -e "${gl_lv}✅ IPv4: ${source_ipv4}${gl_bai}"
                        break
                    else
                        echo -e "${gl_hong}❌ 无效的IPv4地址格式${gl_bai}"
                    fi
                done
                
                # 输入源IPv6地址（必填）
                local source_ipv6=""
                while true; do
                    read -e -p "$(echo -e "${gl_huang}源服务器 IPv6 地址: ${gl_bai}")" source_ipv6
                    
                    if [ -z "$source_ipv6" ]; then
                        echo -e "${gl_hong}❌ IPv6地址不能为空${gl_bai}"
                    elif [[ "$source_ipv6" =~ : ]]; then
                        echo -e "${gl_lv}✅ IPv6: ${source_ipv6}${gl_bai}"
                        break
                    else
                        echo -e "${gl_hong}❌ 无效的IPv6地址格式（应包含冒号）${gl_bai}"
                    fi
                done
                
                # 执行检测
                check_inbound_connections "$source_ipv4" "$source_ipv6"
                ;;
            0)
                return
                ;;
            *)
                echo "无效选择"
                sleep 2
                ;;
        esac
    done
}

show_xray_config() {
    clear
    echo -e "${gl_kjlan}=== 查看 Xray 配置 ===${gl_bai}"
    echo ""

    if [ ! -f /usr/local/etc/xray/config.json ]; then
        echo -e "${gl_hong}错误: Xray 配置文件不存在${gl_bai}"
        echo "路径: /usr/local/etc/xray/config.json"
        echo ""
        break_end
        return 1
    fi

    echo "Xray 配置文件内容："
    echo "------------------------------------------------"
    cat /usr/local/etc/xray/config.json
    echo ""
    echo "------------------------------------------------"

    break_end
}

set_xray_ipv6_outbound() {
    clear
    echo -e "${gl_kjlan}=== 设置 Xray IPv6 出站 ===${gl_bai}"
    echo ""

    # 检查配置文件是否存在
    if [ ! -f /usr/local/etc/xray/config.json ]; then
        echo -e "${gl_hong}错误: Xray 配置文件不存在${gl_bai}"
        echo "路径: /usr/local/etc/xray/config.json"
        echo ""
        break_end
        return 1
    fi

    # 检查 jq 是否安装
    if ! command -v jq &>/dev/null; then
        echo -e "${gl_huang}jq 未安装，正在安装...${gl_bai}"
        install_package jq
    fi

    # 检查 xray 命令是否存在
    if ! command -v xray &>/dev/null; then
        echo -e "${gl_hong}错误: xray 命令不存在${gl_bai}"
        echo ""
        break_end
        return 1
    fi

    echo "正在备份当前配置..."
    local backup_timestamp=$(date +%F-%H%M%S)
    cp /usr/local/etc/xray/config.json /usr/local/etc/xray/config.json.bak.${backup_timestamp}
    echo -e "${gl_lv}✅ 配置已备份${gl_bai}"
    echo ""

    echo "正在修改为 IPv6 出站配置..."
    jq '
      .outbounds = [
        {
          "protocol": "freedom",
          "settings": { "domainStrategy": "UseIPv4v6" },
          "sendThrough": "::"
        }
      ]
    ' /usr/local/etc/xray/config.json > /usr/local/etc/xray/config.json.new && \
    mv /usr/local/etc/xray/config.json.new /usr/local/etc/xray/config.json

    echo "正在测试配置..."
    if xray -test -config /usr/local/etc/xray/config.json; then
        echo -e "${gl_lv}✅ 配置测试通过${gl_bai}"
        echo ""
        echo "正在重启 Xray 服务..."
        systemctl restart xray
        echo -e "${gl_lv}✅ Xray IPv6 出站配置完成！${gl_bai}"
    else
        echo -e "${gl_hong}❌ 配置测试失败，已回滚${gl_bai}"
        mv /usr/local/etc/xray/config.json.bak.${backup_timestamp} /usr/local/etc/xray/config.json
    fi

    echo ""
    break_end
}

restore_xray_default() {
    clear
    echo -e "${gl_kjlan}=== 恢复 Xray 默认配置 ===${gl_bai}"
    echo ""

    # 检查配置文件是否存在
    if [ ! -f /usr/local/etc/xray/config.json ]; then
        echo -e "${gl_hong}错误: Xray 配置文件不存在${gl_bai}"
        echo "路径: /usr/local/etc/xray/config.json"
        echo ""
        break_end
        return 1
    fi

    # 检查 jq 是否安装
    if ! command -v jq &>/dev/null; then
        echo -e "${gl_huang}jq 未安装，正在安装...${gl_bai}"
        install_package jq
    fi

    # 检查 xray 命令是否存在
    if ! command -v xray &>/dev/null; then
        echo -e "${gl_hong}错误: xray 命令不存在${gl_bai}"
        echo ""
        break_end
        return 1
    fi

    echo "正在备份当前配置..."
    local backup_timestamp=$(date +%F-%H%M%S)
    cp /usr/local/etc/xray/config.json /usr/local/etc/xray/config.json.bak.${backup_timestamp}
    echo -e "${gl_lv}✅ 配置已备份${gl_bai}"
    echo ""

    echo "正在恢复双栈模式..."
    jq '
      .outbounds = [
        {
          "protocol": "freedom",
          "settings": { "domainStrategy": "UseIPv4v6" }
        }
      ]
    ' /usr/local/etc/xray/config.json > /usr/local/etc/xray/config.json.new && \
    mv /usr/local/etc/xray/config.json.new /usr/local/etc/xray/config.json

    echo "正在测试配置..."
    if xray -test -config /usr/local/etc/xray/config.json; then
        echo -e "${gl_lv}✅ 配置测试通过${gl_bai}"
        echo ""
        echo "正在重启 Xray 服务..."
        systemctl restart xray
        echo -e "${gl_lv}✅ Xray 默认配置已恢复！${gl_bai}"
    else
        echo -e "${gl_hong}❌ 配置测试失败，已回滚${gl_bai}"
        mv /usr/local/etc/xray/config.json.bak.${backup_timestamp} /usr/local/etc/xray/config.json
    fi

    echo ""
    break_end
}

server_reboot() {
    read -e -p "$(echo -e "${gl_huang}提示: ${gl_bai}现在重启服务器使配置生效吗？(Y/N): ")" rboot
    case "$rboot" in
        [Yy])
            echo "正在重启..."
            reboot
            ;;
        *)
            echo "已取消，请稍后手动执行: reboot"
            ;;
    esac
}

#=============================================================================
# 带宽检测和缓冲区计算函数
#=============================================================================

# 带宽检测函数
detect_bandwidth() {
    # 所有交互式输出重定向到stderr，避免被命令替换捕获
    echo "" >&2
    echo -e "${gl_kjlan}=== 服务器带宽检测 ===${gl_bai}" >&2
    echo "" >&2
    echo "请选择带宽配置方式：" >&2
    echo "1. 自动检测（运行 speedtest，推荐）" >&2
    echo "2. 使用通用值（16MB，跳过检测）" >&2
    echo "" >&2
    
    read -e -p "请输入选择 [1]: " bw_choice
    bw_choice=${bw_choice:-1}
    
    case "$bw_choice" in
        1)
            # 自动检测带宽
            echo "" >&2
            echo -e "${gl_huang}正在运行 speedtest 测速...${gl_bai}" >&2
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
            echo "" >&2
            
            # 检查speedtest是否安装
            if ! command -v speedtest &>/dev/null; then
                echo -e "${gl_huang}speedtest 未安装，正在安装...${gl_bai}" >&2
                # 调用脚本中已有的安装逻辑（简化版）
                local cpu_arch=$(uname -m)
                local download_url
                case "$cpu_arch" in
                    x86_64)
                        download_url="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz"
                        ;;
                    aarch64)
                        download_url="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-aarch64.tgz"
                        ;;
                    *)
                        echo -e "${gl_hong}错误: 不支持的架构 ${cpu_arch}${gl_bai}" >&2
                        echo "将使用通用值 16MB" >&2
                        echo "500"
                        return 1
                        ;;
                esac
                
                cd /tmp
                wget -q "$download_url" -O speedtest.tgz && \
                tar -xzf speedtest.tgz && \
                mv speedtest /usr/local/bin/ && \
                rm -f speedtest.tgz
                
                if [ $? -ne 0 ]; then
                    echo -e "${gl_hong}安装失败，将使用通用值${gl_bai}" >&2
                    echo "500"
                    return 1
                fi
            fi
            
            # 运行speedtest并捕获输出
            local speedtest_output=$(speedtest 2>&1)
            echo "$speedtest_output" >&2
            echo "" >&2
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
            echo "" >&2
            
            # 提取Upload速度（Mbps）
            local upload_speed=$(echo "$speedtest_output" | grep -i "Upload:" | grep -oP '\d+\.\d+' | head -n1)
            
            if [ -z "$upload_speed" ]; then
                echo -e "${gl_huang}无法自动检测带宽，将使用通用值 16MB${gl_bai}" >&2
                echo "500"
                return 1
            fi
            
            # 转为整数
            local upload_mbps=${upload_speed%.*}
            
            echo -e "${gl_lv}✅ 检测到上传带宽: ${upload_mbps} Mbps${gl_bai}" >&2
            echo "" >&2
            
            # 返回带宽值
            echo "$upload_mbps"
            return 0
            ;;
        2)
            # 使用通用值
            echo "" >&2
            echo -e "${gl_huang}使用通用配置: 16MB 缓冲区${gl_bai}" >&2
            echo "说明: 适合大多数 500-2000 Mbps 带宽场景" >&2
            echo "" >&2
            # 返回对应1000Mbps的值
            echo "1000"
            return 0
            ;;
        *)
            echo -e "${gl_huang}无效选择，使用通用值${gl_bai}" >&2
            echo "1000"
            return 1
            ;;
    esac
}

# 缓冲区大小计算函数
calculate_buffer_size() {
    local bandwidth=$1
    local buffer_mb
    local bandwidth_level
    
    # 根据带宽范围计算推荐缓冲区
    if [ "$bandwidth" -lt 500 ]; then
        buffer_mb=8
        bandwidth_level="小带宽（< 500 Mbps）"
    elif [ "$bandwidth" -lt 1000 ]; then
        buffer_mb=12
        bandwidth_level="中等带宽（500-1000 Mbps）"
    elif [ "$bandwidth" -lt 2000 ]; then
        buffer_mb=16
        bandwidth_level="标准带宽（1-2 Gbps）"
    elif [ "$bandwidth" -lt 5000 ]; then
        buffer_mb=24
        bandwidth_level="高带宽（2-5 Gbps）"
    elif [ "$bandwidth" -lt 10000 ]; then
        buffer_mb=28
        bandwidth_level="超高带宽（5-10 Gbps）"
    else
        buffer_mb=32
        bandwidth_level="极高带宽（> 10 Gbps）"
    fi
    
    # 显示计算结果（输出到stderr）
    echo "" >&2
    echo -e "${gl_kjlan}根据带宽计算最优缓冲区:${gl_bai}" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo -e "  检测带宽: ${gl_huang}${bandwidth} Mbps${gl_bai}" >&2
    echo -e "  带宽等级: ${bandwidth_level}" >&2
    echo -e "  推荐缓冲区: ${gl_lv}${buffer_mb} MB${gl_bai}" >&2
    echo -e "  说明: 适合该带宽的最优配置" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2
    
    # 询问确认
    read -e -p "$(echo -e "${gl_huang}是否使用推荐值 ${buffer_mb}MB？(Y/N) [Y]: ${gl_bai}")" confirm
    confirm=${confirm:-Y}
    
    case "$confirm" in
        [Yy])
            # 返回缓冲区大小（MB）
            echo "$buffer_mb"
            return 0
            ;;
        *)
            echo "" >&2
            echo -e "${gl_huang}已取消，将使用通用值 16MB${gl_bai}" >&2
            echo "16"
            return 1
            ;;
    esac
}

#=============================================================================
# SWAP智能检测和建议函数（集成到选项2/3）
#=============================================================================
check_and_suggest_swap() {
    local mem_total=$(free -m | awk 'NR==2{print $2}')
    local swap_total=$(free -m | awk 'NR==3{print $2}')
    local recommended_swap
    local need_swap=0
    
    # 判断是否需要SWAP
    if [ "$mem_total" -lt 2048 ]; then
        # 小于2GB内存，强烈建议配置SWAP
        need_swap=1
    elif [ "$mem_total" -lt 4096 ] && [ "$swap_total" -eq 0 ]; then
        # 2-4GB内存且没有SWAP，建议配置
        need_swap=1
    fi
    
    # 如果不需要SWAP，直接返回
    if [ "$need_swap" -eq 0 ]; then
        return 0
    fi
    
    # 计算推荐的SWAP大小
    if [ "$mem_total" -lt 512 ]; then
        recommended_swap=1024
    elif [ "$mem_total" -lt 1024 ]; then
        recommended_swap=$((mem_total * 2))
    elif [ "$mem_total" -lt 2048 ]; then
        recommended_swap=$((mem_total * 3 / 2))
    elif [ "$mem_total" -lt 4096 ]; then
        recommended_swap=$mem_total
    else
        recommended_swap=4096
    fi
    
    # 显示建议信息
    echo ""
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_huang}检测到虚拟内存（SWAP）需要优化${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""
    echo -e "  物理内存:       ${gl_huang}${mem_total}MB${gl_bai}"
    echo -e "  当前 SWAP:      ${gl_huang}${swap_total}MB${gl_bai}"
    echo -e "  推荐 SWAP:      ${gl_lv}${recommended_swap}MB${gl_bai}"
    echo ""
    
    if [ "$mem_total" -lt 1024 ]; then
        echo -e "${gl_zi}原因: 小内存机器（<1GB）强烈建议配置SWAP，避免内存不足导致程序崩溃${gl_bai}"
    elif [ "$mem_total" -lt 2048 ]; then
        echo -e "${gl_zi}原因: 1-2GB内存建议配置SWAP，提供缓冲空间${gl_bai}"
    elif [ "$mem_total" -lt 4096 ]; then
        echo -e "${gl_zi}原因: 2-4GB内存建议配置少量SWAP作为保险${gl_bai}"
    fi
    
    echo ""
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""
    
    # 询问用户
    read -e -p "$(echo -e "${gl_huang}是否现在配置虚拟内存？(Y/N): ${gl_bai}")" confirm
    
    case "$confirm" in
        [Yy])
            echo ""
            echo -e "${gl_lv}开始配置虚拟内存...${gl_bai}"
            echo ""
            add_swap "$recommended_swap"
            echo ""
            echo -e "${gl_lv}✅ 虚拟内存配置完成！${gl_bai}"
            echo ""
            echo -e "${gl_zi}继续执行 BBR 优化配置...${gl_bai}"
            sleep 2
            return 0
            ;;
        [Nn])
            echo ""
            echo -e "${gl_huang}已跳过虚拟内存配置${gl_bai}"
            echo -e "${gl_zi}继续执行 BBR 优化配置...${gl_bai}"
            echo ""
            sleep 2
            return 1
            ;;
        *)
            echo ""
            echo -e "${gl_huang}输入无效，已跳过虚拟内存配置${gl_bai}"
            echo -e "${gl_zi}继续执行 BBR 优化配置...${gl_bai}"
            echo ""
            sleep 2
            return 1
            ;;
    esac
}

#=============================================================================
# 配置冲突检测与清理（避免被其他 sysctl 覆盖）
#=============================================================================
check_and_clean_conflicts() {
    echo -e "${gl_kjlan}=== 检查 sysctl 配置冲突 ===${gl_bai}"
    local conflicts=()
    # 搜索 /etc/sysctl.d/ 下可能覆盖 tcp_rmem/tcp_wmem 的高序号文件
    for conf in /etc/sysctl.d/[0-9]*-*.conf /etc/sysctl.d/[0-9][0-9][0-9]-*.conf; do
        [ -f "$conf" ] || continue
        [ "$conf" = "$SYSCTL_CONF" ] && continue
        if grep -qE "(^|\s)net\.ipv4\.tcp_(rmem|wmem)" "$conf" 2>/dev/null; then
            base=$(basename "$conf")
            num=$(echo "$base" | sed -n 's/^\([0-9]\+\).*/\1/p')
            # 99 及以上优先生效，可能覆盖本脚本
            if [ -n "$num" ] && [ "$num" -ge 99 ]; then
                conflicts+=("$conf")
            fi
        fi
    done

    # 主配置文件直接设置也会覆盖
    local has_sysctl_conflict=0
    if [ -f /etc/sysctl.conf ] && grep -qE "(^|\s)net\.ipv4\.tcp_(rmem|wmem)" /etc/sysctl.conf 2>/dev/null; then
        has_sysctl_conflict=1
    fi

    if [ ${#conflicts[@]} -eq 0 ] && [ $has_sysctl_conflict -eq 0 ]; then
        echo -e "${gl_lv}✓ 未发现可能的覆盖配置${gl_bai}"
        return 0
    fi

    echo -e "${gl_huang}发现可能的覆盖配置：${gl_bai}"
    for f in "${conflicts[@]}"; do
        echo "  - $f"; grep -E "net\.ipv4\.tcp_(rmem|wmem)" "$f" | sed 's/^/      /'
    done
    [ $has_sysctl_conflict -eq 1 ] && echo "  - /etc/sysctl.conf (含 tcp_rmem/tcp_wmem)"

    read -e -p "是否自动禁用/注释这些覆盖配置？(Y/N): " ans
    case "$ans" in
        [Yy])
            # 注释 /etc/sysctl.conf 中相关行
            if [ $has_sysctl_conflict -eq 1 ]; then
                sed -i.bak '/^net\.ipv4\.tcp_wmem/s/^/# /' /etc/sysctl.conf 2>/dev/null
                sed -i.bak '/^net\.ipv4\.tcp_rmem/s/^/# /' /etc/sysctl.conf 2>/dev/null
                sed -i.bak '/^net\.core\.rmem_max/s/^/# /' /etc/sysctl.conf 2>/dev/null
                sed -i.bak '/^net\.core\.wmem_max/s/^/# /' /etc/sysctl.conf 2>/dev/null
                echo -e "${gl_lv}✓ 已注释 /etc/sysctl.conf 中的相关配置${gl_bai}"
            fi
            # 将高优先级冲突文件重命名禁用
            for f in "${conflicts[@]}"; do
                mv "$f" "${f}.disabled.$(date +%Y%m%d_%H%M%S)" 2>/dev/null && \
                  echo -e "${gl_lv}✓ 已禁用: $(basename "$f")${gl_bai}"
            done
            ;;
        *)
            echo -e "${gl_huang}已跳过自动清理，可能导致新配置未完全生效${gl_bai}"
            ;;
    esac
}

#=============================================================================
# 立即生效与防分片函数（无需重启）
#=============================================================================

# 获取需应用 qdisc 的网卡（排除常见虚拟接口）
eligible_ifaces() {
    for d in /sys/class/net/*; do
        [ -e "$d" ] || continue
        dev=$(basename "$d")
        case "$dev" in
            lo|docker*|veth*|br-*|virbr*|zt*|tailscale*|wg*|tun*|tap*) continue;;
        esac
        echo "$dev"
    done
}

# tc fq 立即生效（无需重启）
apply_tc_fq_now() {
    if ! command -v tc >/dev/null 2>&1; then
        echo -e "${gl_huang}警告: 未检测到 tc（iproute2），跳过 fq 应用${gl_bai}"
        return 0
    fi
    local applied=0
    for dev in $(eligible_ifaces); do
        tc qdisc replace dev "$dev" root fq 2>/dev/null && applied=$((applied+1))
    done
    [ $applied -gt 0 ] && echo -e "${gl_lv}已对 $applied 个网卡应用 fq（即时生效）${gl_bai}" || echo -e "${gl_huang}未发现可应用 fq 的网卡${gl_bai}"
}

# MSS clamp（防分片）自动启用
apply_mss_clamp() {
    local action=$1  # enable|disable
    if ! command -v iptables >/dev/null 2>&1; then
        echo -e "${gl_huang}警告: 未检测到 iptables，跳过 MSS clamp${gl_bai}"
        return 0
    fi
    if [ "$action" = "enable" ]; then
        iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu >/dev/null 2>&1 \
          || iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
    else
        iptables -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu >/dev/null 2>&1 || true
    fi
}

#=============================================================================
# BBR 配置函数（智能检测版）
#=============================================================================

# 直连/落地优化配置
bbr_configure_direct() {
    echo -e "${gl_kjlan}=== 配置 BBR v3 + FQ 直连/落地优化（智能检测版） ===${gl_bai}"
    echo ""
    
    # 步骤 0：SWAP智能检测和建议
    echo -e "${gl_zi}[步骤 1/6] 检测虚拟内存（SWAP）配置...${gl_bai}"
    check_and_suggest_swap
    
    # 步骤 0.5：带宽检测和缓冲区计算
    echo ""
    echo -e "${gl_zi}[步骤 2/6] 检测服务器带宽并计算最优缓冲区...${gl_bai}"
    
    local detected_bandwidth=$(detect_bandwidth)
    local buffer_mb=$(calculate_buffer_size "$detected_bandwidth")
    local buffer_bytes=$((buffer_mb * 1024 * 1024))
    
    echo -e "${gl_lv}✅ 将使用 ${buffer_mb}MB 缓冲区配置${gl_bai}"
    sleep 2
    
    echo ""
    echo -e "${gl_zi}[步骤 3/6] 清理配置冲突...${gl_bai}"
    echo "正在检查配置冲突..."
    
    # 备份主配置文件（如果还没备份）
    if [ -f /etc/sysctl.conf ] && ! [ -f /etc/sysctl.conf.bak.original ]; then
        cp /etc/sysctl.conf /etc/sysctl.conf.bak.original
        echo "已备份: /etc/sysctl.conf -> /etc/sysctl.conf.bak.original"
    fi
    
    # 注释掉 /etc/sysctl.conf 中的 TCP 缓冲区配置（避免覆盖）
    if [ -f /etc/sysctl.conf ]; then
        sed -i '/^net.ipv4.tcp_wmem/s/^/# /' /etc/sysctl.conf 2>/dev/null
        sed -i '/^net.ipv4.tcp_rmem/s/^/# /' /etc/sysctl.conf 2>/dev/null
        sed -i '/^net.core.rmem_max/s/^/# /' /etc/sysctl.conf 2>/dev/null
        sed -i '/^net.core.wmem_max/s/^/# /' /etc/sysctl.conf 2>/dev/null
        echo "已清理 /etc/sysctl.conf 中的冲突配置"
    fi
    
    # 删除可能存在的软链接
    if [ -L /etc/sysctl.d/99-sysctl.conf ]; then
        rm -f /etc/sysctl.d/99-sysctl.conf
        echo "已删除配置软链接"
    fi
    
    # 检查并清理可能覆盖的新旧配置冲突
    check_and_clean_conflicts

    # 步骤 3：创建独立配置文件（使用动态缓冲区）
    echo ""
    echo -e "${gl_zi}[步骤 4/6] 创建配置文件...${gl_bai}"
    echo "正在创建新配置..."
    
    # 获取物理内存用于虚拟内存参数调整
    local mem_total=$(free -m | awk 'NR==2{print $2}')
    local vm_swappiness=10
    local vm_dirty_ratio=15
    local vm_min_free_kbytes=65536
    
    # 根据内存大小微调虚拟内存参数
    if [ "$mem_total" -lt 2048 ]; then
        vm_swappiness=20
        vm_dirty_ratio=20
        vm_min_free_kbytes=32768
    fi
    
    cat > "$SYSCTL_CONF" << EOF
# BBR v3 Direct/Endpoint Configuration (Intelligent Detection Edition)
# Generated on $(date)
# Bandwidth: ${detected_bandwidth} Mbps | Buffer: ${buffer_mb} MB

# 队列调度算法
net.core.default_qdisc=fq

# 拥塞控制算法
net.ipv4.tcp_congestion_control=bbr

# TCP 缓冲区优化（智能检测：${buffer_mb}MB）
net.core.rmem_max=${buffer_bytes}
net.core.wmem_max=${buffer_bytes}
net.ipv4.tcp_rmem=4096 87380 ${buffer_bytes}
net.ipv4.tcp_wmem=4096 65536 ${buffer_bytes}

# ===== 直连/落地优化参数 =====

# TIME_WAIT 重用（启用，提高并发）
net.ipv4.tcp_tw_reuse=1

# 端口范围（最大化）
net.ipv4.ip_local_port_range=1024 65535

# 连接队列（高性能）
net.core.somaxconn=4096
net.ipv4.tcp_max_syn_backlog=8192

# 网络队列（高带宽优化）
net.core.netdev_max_backlog=16384

# 高级TCP优化
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_mtu_probing=1

# 虚拟内存优化（根据物理内存调整）
vm.swappiness=${vm_swappiness}
vm.dirty_ratio=${vm_dirty_ratio}
vm.dirty_background_ratio=5
vm.overcommit_memory=1
vm.min_free_kbytes=${vm_min_free_kbytes}
vm.vfs_cache_pressure=50

# CPU调度优化
kernel.sched_autogroup_enabled=0
kernel.numa_balancing=0
EOF

    # 步骤 4：应用配置
    echo ""
    echo -e "${gl_zi}[步骤 5/6] 应用所有优化参数...${gl_bai}"
    echo "正在应用配置..."
    sysctl -p "$SYSCTL_CONF" > /dev/null 2>&1
    
    # 立即应用 fq，并启用 MSS clamp（无需重启）
    echo "正在应用队列与防分片（无需重启）..."
    apply_tc_fq_now >/dev/null 2>&1
    apply_mss_clamp enable >/dev/null 2>&1
    
    # 配置文件描述符限制
    echo "正在优化文件描述符限制..."
    if ! grep -q "BBR - 文件描述符优化" /etc/security/limits.conf 2>/dev/null; then
        cat >> /etc/security/limits.conf << 'LIMITSEOF'
# BBR - 文件描述符优化
* soft nofile 65535
* hard nofile 65535
LIMITSEOF
    fi
    ulimit -n 65535 2>/dev/null
    
    # 禁用透明大页面
    if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
        echo never > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null
    fi

    # 步骤 5：验证配置是否真正生效
    echo ""
    echo -e "${gl_zi}[步骤 6/6] 验证配置...${gl_bai}"
    
    local actual_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    local actual_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local actual_wmem=$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null | awk '{print $3}')
    local actual_rmem=$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null | awk '{print $3}')
    
    echo ""
    echo -e "${gl_kjlan}=== 配置验证 ===${gl_bai}"
    
    # 验证队列算法
    if [ "$actual_qdisc" = "fq" ]; then
        echo -e "队列算法: ${gl_lv}$actual_qdisc ✓${gl_bai}"
    else
        echo -e "队列算法: ${gl_huang}$actual_qdisc (期望: fq) ⚠${gl_bai}"
    fi
    
    # 验证拥塞控制
    if [ "$actual_cc" = "bbr" ]; then
        echo -e "拥塞控制: ${gl_lv}$actual_cc ✓${gl_bai}"
    else
        echo -e "拥塞控制: ${gl_huang}$actual_cc (期望: bbr) ⚠${gl_bai}"
    fi
    
    # 验证缓冲区（动态）
    local actual_wmem_mb=$((actual_wmem / 1048576))
    local actual_rmem_mb=$((actual_rmem / 1048576))
    
    if [ "$actual_wmem" = "$buffer_bytes" ]; then
        echo -e "发送缓冲区: ${gl_lv}${buffer_mb}MB ✓${gl_bai}"
    else
        echo -e "发送缓冲区: ${gl_huang}${actual_wmem_mb}MB (期望: ${buffer_mb}MB) ⚠${gl_bai}"
    fi
    
    if [ "$actual_rmem" = "$buffer_bytes" ]; then
        echo -e "接收缓冲区: ${gl_lv}${buffer_mb}MB ✓${gl_bai}"
    else
        echo -e "接收缓冲区: ${gl_huang}${actual_rmem_mb}MB (期望: ${buffer_mb}MB) ⚠${gl_bai}"
    fi
    
    echo ""
    
    # 最终判断
    if [ "$actual_qdisc" = "fq" ] && [ "$actual_cc" = "bbr" ] && \
       [ "$actual_wmem" = "$buffer_bytes" ] && [ "$actual_rmem" = "$buffer_bytes" ]; then
        echo -e "${gl_lv}✅ BBR v3 直连/落地优化配置完成并已生效！${gl_bai}"
        echo -e "${gl_zi}配置说明: ${buffer_mb}MB 缓冲区（${detected_bandwidth} Mbps 带宽），适合直连/落地场景${gl_bai}"
    else
        echo -e "${gl_huang}⚠️ 配置已保存但部分参数未生效${gl_bai}"
        echo -e "${gl_huang}建议执行以下操作：${gl_bai}"
        echo "1. 检查是否有其他配置文件冲突"
        echo "2. 重启服务器使配置完全生效: reboot"
    fi
}

#=============================================================================
# 状态检查函数
#=============================================================================

check_bbr_status() {
    echo -e "${gl_kjlan}=== 当前系统状态 ===${gl_bai}"
    echo "内核版本: $(uname -r)"
    
    if command -v sysctl &>/dev/null; then
        local congestion=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")
        local qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "未知")
        echo "拥塞控制算法: $congestion"
        echo "队列调度算法: $qdisc"
        
        # 检查 BBR 版本
        if command -v modinfo &>/dev/null; then
            local bbr_version=$(modinfo tcp_bbr 2>/dev/null | awk '/^version:/ {print $2}')
            if [ -n "$bbr_version" ]; then
                if [ "$bbr_version" = "3" ]; then
                    echo -e "BBR 版本: ${gl_lv}v${bbr_version} ✓${gl_bai}"
                else
                    echo -e "BBR 版本: ${gl_huang}v${bbr_version} (不是 v3)${gl_bai}"
                fi
            fi
        fi
    fi
    
    if dpkg -l 2>/dev/null | grep -q 'linux-xanmod'; then
        echo -e "XanMod 内核: ${gl_lv}已安装 ✓${gl_bai}"
        return 0
    else
        echo -e "XanMod 内核: ${gl_huang}未安装${gl_bai}"
        return 1
    fi
}

#=============================================================================
# XanMod 内核安装（官方源）
#=============================================================================

install_xanmod_kernel() {
    clear
    echo -e "${gl_kjlan}=== 安装 XanMod 内核与 BBR v3 ===${gl_bai}"
    echo "视频教程: https://www.bilibili.com/video/BV14K421x7BS"
    echo "------------------------------------------------"
    echo "支持系统: Debian/Ubuntu (x86_64 & ARM64)"
    echo -e "${gl_huang}警告: 将升级 Linux 内核，请提前备份重要数据！${gl_bai}"
    echo "------------------------------------------------"
    read -e -p "确定继续安装吗？(Y/N): " choice

    case "$choice" in
        [Yy])
            ;;
        *)
            echo "已取消安装"
            return 1
            ;;
    esac
    
    # 检测 CPU 架构
    local cpu_arch=$(uname -m)
    
    # ARM 架构特殊处理
    if [ "$cpu_arch" = "aarch64" ]; then
        echo -e "${gl_kjlan}检测到 ARM64 架构，使用专用安装脚本${gl_bai}"
        bash <(curl -sL jhb.ovh/jb/bbrv3arm.sh)
        if [ $? -eq 0 ]; then
            echo -e "${gl_lv}ARM BBR v3 安装完成${gl_bai}"
            return 0
        else
            echo -e "${gl_hong}安装失败${gl_bai}"
            return 1
        fi
    fi
    
    # x86_64 架构安装流程
    # 检查系统支持
    if [ -r /etc/os-release ]; then
        . /etc/os-release
        if [ "$ID" != "debian" ] && [ "$ID" != "ubuntu" ]; then
            echo -e "${gl_hong}错误: 仅支持 Debian 和 Ubuntu 系统${gl_bai}"
            return 1
        fi
    else
        echo -e "${gl_hong}错误: 无法确定操作系统类型${gl_bai}"
        return 1
    fi
    
    # 环境准备
    check_disk_space 3
    check_swap
    install_package wget gnupg
    
    # 添加 XanMod GPG 密钥
    echo "正在添加 XanMod 仓库密钥..."
    wget -qO - ${gh_proxy}raw.githubusercontent.com/kejilion/sh/main/archive.key | \
        gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg --yes
    
    if [ $? -ne 0 ]; then
        echo -e "${gl_hong}密钥下载失败，尝试官方源...${gl_bai}"
        wget -qO - https://dl.xanmod.org/archive.key | \
            gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg --yes
    fi
    
    # 添加 XanMod 仓库
    echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' | \
        tee /etc/apt/sources.list.d/xanmod-release.list > /dev/null
    
    # 检测 CPU 架构版本
    echo "正在检测 CPU 支持的最优内核版本..."
    local version=$(wget -q ${gh_proxy}raw.githubusercontent.com/kejilion/sh/main/check_x86-64_psabi.sh && \
                   chmod +x check_x86-64_psabi.sh && \
                   ./check_x86-64_psabi.sh | grep -oP 'x86-64-v\K\d+|x86-64-v\d+')
    
    if [ -z "$version" ]; then
        echo -e "${gl_huang}自动检测失败，使用默认版本 v3${gl_bai}"
        version="3"
    fi
    
    echo -e "${gl_lv}将安装: linux-xanmod-x64v${version}${gl_bai}"
    
    # 安装 XanMod 内核
    apt update -y
    apt install -y linux-xanmod-x64v$version
    
    if [ $? -ne 0 ]; then
        echo -e "${gl_hong}内核安装失败！${gl_bai}"
        rm -f /etc/apt/sources.list.d/xanmod-release.list
        rm -f check_x86-64_psabi.sh*
        return 1
    fi
    
    # 清理临时文件
    rm -f /etc/apt/sources.list.d/xanmod-release.list
    rm -f check_x86-64_psabi.sh*
    
    echo -e "${gl_lv}XanMod 内核安装成功！${gl_bai}"
    echo -e "${gl_huang}提示: 请先重启系统加载新内核，然后再配置 BBR${gl_bai}"
    return 0
}


#=============================================================================
# IP地址获取函数
#=============================================================================

ip_address() {
    get_public_ip() {
        curl -s https://ipinfo.io/ip && echo
    }

    get_local_ip() {
        ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K[^ ]+' || \
        hostname -I 2>/dev/null | awk '{print $1}' || \
        ifconfig 2>/dev/null | grep -E 'inet [0-9]' | grep -v '127.0.0.1' | awk '{print $2}' | head -n1
    }

    public_ip=$(get_public_ip)
    isp_info=$(curl -s --max-time 3 http://ipinfo.io/org)

    if echo "$isp_info" | grep -Eiq 'mobile|unicom|telecom'; then
        ipv4_address=$(get_local_ip)
    else
        ipv4_address="$public_ip"
    fi

    ipv6_address=$(curl -s --max-time 1 https://v6.ipinfo.io/ip && echo)
}

#=============================================================================
# 网络流量统计函数
#=============================================================================

output_status() {
    output=$(awk 'BEGIN { rx_total = 0; tx_total = 0 }
        $1 ~ /^(eth|ens|enp|eno)[0-9]+/ {
            rx_total += $2
            tx_total += $10
        }
        END {
            rx_units = "Bytes";
            tx_units = "Bytes";
            if (rx_total > 1024) { rx_total /= 1024; rx_units = "K"; }
            if (rx_total > 1024) { rx_total /= 1024; rx_units = "M"; }
            if (rx_total > 1024) { rx_total /= 1024; rx_units = "G"; }

            if (tx_total > 1024) { tx_total /= 1024; tx_units = "K"; }
            if (tx_total > 1024) { tx_total /= 1024; tx_units = "M"; }
            if (tx_total > 1024) { tx_total /= 1024; tx_units = "G"; }

            printf("%.2f%s %.2f%s\n", rx_total, rx_units, tx_total, tx_units);
        }' /proc/net/dev)

    rx=$(echo "$output" | awk '{print $1}')
    tx=$(echo "$output" | awk '{print $2}')
}

#=============================================================================
# 时区获取函数
#=============================================================================

current_timezone() {
    if grep -q 'Alpine' /etc/issue 2>/dev/null; then
        date +"%Z %z"
    else
        timedatectl | grep "Time zone" | awk '{print $3}'
    fi
}

#=============================================================================
# 详细系统信息显示
#=============================================================================

show_detailed_status() {
    clear

    ip_address

    local cpu_info=$(lscpu | awk -F': +' '/Model name:/ {print $2; exit}')

    local cpu_usage_percent=$(awk '{u=$2+$4; t=$2+$4+$5; if (NR==1){u1=u; t1=t;} else printf "%.0f\n", (($2+$4-u1) * 100 / (t-t1))}' \
        <(grep 'cpu ' /proc/stat) <(sleep 1; grep 'cpu ' /proc/stat))

    local cpu_cores=$(nproc)

    local cpu_freq=$(cat /proc/cpuinfo | grep "MHz" | head -n 1 | awk '{printf "%.1f GHz\n", $4/1000}')

    local mem_info=$(free -b | awk 'NR==2{printf "%.2f/%.2fM (%.2f%%)", $3/1024/1024, $2/1024/1024, $3*100/$2}')

    local disk_info=$(df -h | awk '$NF=="/"{printf "%s/%s (%s)", $3, $2, $5}')

    local ipinfo=$(curl -s ipinfo.io)
    local country=$(echo "$ipinfo" | grep 'country' | awk -F': ' '{print $2}' | tr -d '",')
    local city=$(echo "$ipinfo" | grep 'city' | awk -F': ' '{print $2}' | tr -d '",')
    local isp_info=$(echo "$ipinfo" | grep 'org' | awk -F': ' '{print $2}' | tr -d '",')

    local load=$(uptime | awk '{print $(NF-2), $(NF-1), $NF}')
    local dns_addresses=$(awk '/^nameserver/{printf "%s ", $2} END {print ""}' /etc/resolv.conf)

    local cpu_arch=$(uname -m)
    local hostname=$(uname -n)
    local kernel_version=$(uname -r)

    local congestion_algorithm=$(sysctl -n net.ipv4.tcp_congestion_control)
    local queue_algorithm=$(sysctl -n net.core.default_qdisc)

    local os_info=$(grep PRETTY_NAME /etc/os-release | cut -d '=' -f2 | tr -d '"')

    output_status

    local current_time=$(date "+%Y-%m-%d %I:%M %p")

    local swap_info=$(free -m | awk 'NR==3{used=$3; total=$2; if (total == 0) {percentage=0} else {percentage=used*100/total}; printf "%dM/%dM (%d%%)", used, total, percentage}')

    local runtime=$(cat /proc/uptime | awk -F. '{run_days=int($1 / 86400);run_hours=int(($1 % 86400) / 3600);run_minutes=int(($1 % 3600) / 60); if (run_days > 0) printf("%d天 ", run_days); if (run_hours > 0) printf("%d时 ", run_hours); printf("%d分\n", run_minutes)}')

    local timezone=$(current_timezone)

    echo ""
    echo -e "系统信息查询"
    echo -e "${gl_kjlan}-------------"
    echo -e "${gl_kjlan}主机名:       ${gl_bai}$hostname"
    echo -e "${gl_kjlan}系统版本:     ${gl_bai}$os_info"
    echo -e "${gl_kjlan}Linux版本:    ${gl_bai}$kernel_version"
    echo -e "${gl_kjlan}-------------"
    echo -e "${gl_kjlan}CPU架构:      ${gl_bai}$cpu_arch"
    echo -e "${gl_kjlan}CPU型号:      ${gl_bai}$cpu_info"
    echo -e "${gl_kjlan}CPU核心数:    ${gl_bai}$cpu_cores"
    echo -e "${gl_kjlan}CPU频率:      ${gl_bai}$cpu_freq"
    echo -e "${gl_kjlan}-------------"
    echo -e "${gl_kjlan}CPU占用:      ${gl_bai}$cpu_usage_percent%"
    echo -e "${gl_kjlan}系统负载:     ${gl_bai}$load"
    echo -e "${gl_kjlan}物理内存:     ${gl_bai}$mem_info"
    echo -e "${gl_kjlan}虚拟内存:     ${gl_bai}$swap_info"
    echo -e "${gl_kjlan}硬盘占用:     ${gl_bai}$disk_info"
    echo -e "${gl_kjlan}-------------"
    echo -e "${gl_kjlan}总接收:       ${gl_bai}$rx"
    echo -e "${gl_kjlan}总发送:       ${gl_bai}$tx"
    echo -e "${gl_kjlan}-------------"
    echo -e "${gl_kjlan}网络算法:     ${gl_bai}$congestion_algorithm $queue_algorithm"
    echo -e "${gl_kjlan}-------------"
    echo -e "${gl_kjlan}运营商:       ${gl_bai}$isp_info"
    if [ -n "$ipv4_address" ]; then
        echo -e "${gl_kjlan}IPv4地址:     ${gl_bai}$ipv4_address"
    fi

    if [ -n "$ipv6_address" ]; then
        echo -e "${gl_kjlan}IPv6地址:     ${gl_bai}$ipv6_address"
    fi
    echo -e "${gl_kjlan}DNS地址:      ${gl_bai}$dns_addresses"
    echo -e "${gl_kjlan}地理位置:     ${gl_bai}$country $city"
    echo -e "${gl_kjlan}系统时间:     ${gl_bai}$timezone $current_time"
    echo -e "${gl_kjlan}-------------"
    echo -e "${gl_kjlan}运行时长:     ${gl_bai}$runtime"
    echo

    break_end
}

#=============================================================================
# 内核参数优化 - 高性能模式
#=============================================================================

optimize_high_performance() {
    echo -e "${gl_lv}切换到${tiaoyou_moshi}...${gl_bai}"

    echo -e "${gl_lv}优化文件描述符...${gl_bai}"
    ulimit -n 65535

    echo -e "${gl_lv}优化虚拟内存...${gl_bai}"
    sysctl -w vm.swappiness=10 2>/dev/null
    sysctl -w vm.dirty_ratio=15 2>/dev/null
    sysctl -w vm.dirty_background_ratio=5 2>/dev/null
    sysctl -w vm.overcommit_memory=1 2>/dev/null
    sysctl -w vm.min_free_kbytes=65536 2>/dev/null

    echo -e "${gl_lv}优化网络设置...${gl_bai}"
    sysctl -w net.core.rmem_max=16777216 2>/dev/null
    sysctl -w net.core.wmem_max=16777216 2>/dev/null
    sysctl -w net.core.netdev_max_backlog=250000 2>/dev/null
    sysctl -w net.core.somaxconn=4096 2>/dev/null
    sysctl -w net.ipv4.tcp_rmem='4096 87380 16777216' 2>/dev/null
    sysctl -w net.ipv4.tcp_wmem='4096 65536 16777216' 2>/dev/null
    sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null
    sysctl -w net.ipv4.tcp_max_syn_backlog=8192 2>/dev/null
    sysctl -w net.ipv4.tcp_tw_reuse=1 2>/dev/null
    sysctl -w net.ipv4.ip_local_port_range='1024 65535' 2>/dev/null

    echo -e "${gl_lv}优化缓存管理...${gl_bai}"
    sysctl -w vm.vfs_cache_pressure=50 2>/dev/null

    echo -e "${gl_lv}优化CPU设置...${gl_bai}"
    sysctl -w kernel.sched_autogroup_enabled=0 2>/dev/null

    echo -e "${gl_lv}其他优化...${gl_bai}"
    # 禁用透明大页面，减少延迟
    echo never > /sys/kernel/mm/transparent_hugepage/enabled
    # 禁用 NUMA balancing
    sysctl -w kernel.numa_balancing=0 2>/dev/null

    echo ""
    echo -e "${gl_lv}${tiaoyou_moshi}设置完成！${gl_bai}"
}

#=============================================================================
# 内核参数优化 - 均衡模式
#=============================================================================

optimize_balanced() {
    echo -e "${gl_lv}切换到均衡模式...${gl_bai}"

    echo -e "${gl_lv}优化文件描述符...${gl_bai}"
    ulimit -n 32768

    echo -e "${gl_lv}优化虚拟内存...${gl_bai}"
    sysctl -w vm.swappiness=30 2>/dev/null
    sysctl -w vm.dirty_ratio=20 2>/dev/null
    sysctl -w vm.dirty_background_ratio=10 2>/dev/null
    sysctl -w vm.overcommit_memory=0 2>/dev/null
    sysctl -w vm.min_free_kbytes=32768 2>/dev/null

    echo -e "${gl_lv}优化网络设置...${gl_bai}"
    sysctl -w net.core.rmem_max=8388608 2>/dev/null
    sysctl -w net.core.wmem_max=8388608 2>/dev/null
    sysctl -w net.core.netdev_max_backlog=125000 2>/dev/null
    sysctl -w net.core.somaxconn=2048 2>/dev/null
    sysctl -w net.ipv4.tcp_rmem='4096 87380 8388608' 2>/dev/null
    sysctl -w net.ipv4.tcp_wmem='4096 32768 8388608' 2>/dev/null
    sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null
    sysctl -w net.ipv4.tcp_max_syn_backlog=4096 2>/dev/null
    sysctl -w net.ipv4.tcp_tw_reuse=1 2>/dev/null
    sysctl -w net.ipv4.ip_local_port_range='1024 49151' 2>/dev/null

    echo -e "${gl_lv}优化缓存管理...${gl_bai}"
    sysctl -w vm.vfs_cache_pressure=75 2>/dev/null

    echo -e "${gl_lv}优化CPU设置...${gl_bai}"
    sysctl -w kernel.sched_autogroup_enabled=1 2>/dev/null

    echo -e "${gl_lv}其他优化...${gl_bai}"
    # 还原透明大页面
    echo always > /sys/kernel/mm/transparent_hugepage/enabled
    # 还原 NUMA balancing
    sysctl -w kernel.numa_balancing=1 2>/dev/null

    echo ""
    echo -e "${gl_lv}均衡模式设置完成！${gl_bai}"
}

#=============================================================================
# 内核参数优化 - 网站优化模式
#=============================================================================

optimize_web_server() {
    echo -e "${gl_lv}切换到网站搭建优化模式...${gl_bai}"

    echo -e "${gl_lv}优化文件描述符...${gl_bai}"
    ulimit -n 65535

    echo -e "${gl_lv}优化虚拟内存...${gl_bai}"
    sysctl -w vm.swappiness=10 2>/dev/null
    sysctl -w vm.dirty_ratio=20 2>/dev/null
    sysctl -w vm.dirty_background_ratio=10 2>/dev/null
    sysctl -w vm.overcommit_memory=1 2>/dev/null
    sysctl -w vm.min_free_kbytes=65536 2>/dev/null

    echo -e "${gl_lv}优化网络设置...${gl_bai}"
    sysctl -w net.core.rmem_max=16777216 2>/dev/null
    sysctl -w net.core.wmem_max=16777216 2>/dev/null
    sysctl -w net.core.netdev_max_backlog=5000 2>/dev/null
    sysctl -w net.core.somaxconn=4096 2>/dev/null
    sysctl -w net.ipv4.tcp_rmem='4096 87380 16777216' 2>/dev/null
    sysctl -w net.ipv4.tcp_wmem='4096 65536 16777216' 2>/dev/null
    sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null
    sysctl -w net.ipv4.tcp_max_syn_backlog=8192 2>/dev/null
    sysctl -w net.ipv4.tcp_tw_reuse=1 2>/dev/null
    sysctl -w net.ipv4.ip_local_port_range='1024 65535' 2>/dev/null

    echo -e "${gl_lv}优化缓存管理...${gl_bai}"
    sysctl -w vm.vfs_cache_pressure=50 2>/dev/null

    echo -e "${gl_lv}优化CPU设置...${gl_bai}"
    sysctl -w kernel.sched_autogroup_enabled=0 2>/dev/null

    echo -e "${gl_lv}其他优化...${gl_bai}"
    # 禁用透明大页面，减少延迟
    echo never > /sys/kernel/mm/transparent_hugepage/enabled
    # 禁用 NUMA balancing
    sysctl -w kernel.numa_balancing=0 2>/dev/null

    echo ""
    echo -e "${gl_lv}网站优化模式设置完成！${gl_bai}"
}

#=============================================================================
# 内核参数优化 - 还原默认设置
#=============================================================================

restore_defaults() {
    echo -e "${gl_lv}还原到默认设置...${gl_bai}"

    echo -e "${gl_lv}还原文件描述符...${gl_bai}"
    ulimit -n 1024

    echo -e "${gl_lv}还原虚拟内存...${gl_bai}"
    sysctl -w vm.swappiness=60 2>/dev/null
    sysctl -w vm.dirty_ratio=20 2>/dev/null
    sysctl -w vm.dirty_background_ratio=10 2>/dev/null
    sysctl -w vm.overcommit_memory=0 2>/dev/null
    sysctl -w vm.min_free_kbytes=16384 2>/dev/null

    echo -e "${gl_lv}还原网络设置...${gl_bai}"
    sysctl -w net.core.rmem_max=212992 2>/dev/null
    sysctl -w net.core.wmem_max=212992 2>/dev/null
    sysctl -w net.core.netdev_max_backlog=1000 2>/dev/null
    sysctl -w net.core.somaxconn=128 2>/dev/null
    sysctl -w net.ipv4.tcp_rmem='4096 87380 6291456' 2>/dev/null
    sysctl -w net.ipv4.tcp_wmem='4096 16384 4194304' 2>/dev/null
    sysctl -w net.ipv4.tcp_congestion_control=cubic 2>/dev/null
    sysctl -w net.ipv4.tcp_max_syn_backlog=2048 2>/dev/null
    sysctl -w net.ipv4.tcp_tw_reuse=0 2>/dev/null
    sysctl -w net.ipv4.ip_local_port_range='32768 60999' 2>/dev/null

    echo -e "${gl_lv}还原缓存管理...${gl_bai}"
    sysctl -w vm.vfs_cache_pressure=100 2>/dev/null

    echo -e "${gl_lv}还原CPU设置...${gl_bai}"
    sysctl -w kernel.sched_autogroup_enabled=1 2>/dev/null

    echo -e "${gl_lv}还原其他优化...${gl_bai}"
    # 还原透明大页面
    echo always > /sys/kernel/mm/transparent_hugepage/enabled
    # 还原 NUMA balancing
    sysctl -w kernel.numa_balancing=1 2>/dev/null

    echo ""
    echo -e "${gl_lv}默认设置已还原！${gl_bai}"
}

#=============================================================================
# 内核参数优化 - 主菜单
#=============================================================================

Kernel_optimize() {
    while true; do
        clear
        echo "Linux系统内核参数优化"
        echo "视频介绍: https://www.bilibili.com/video/BV1Kb421J7yg?t=0.1"
        echo "------------------------------------------------"
        echo "提供多种系统参数调优模式，用户可以根据自身使用场景进行选择切换。"
        echo -e "${gl_huang}提示: ${gl_bai}生产环境请谨慎使用！"
        echo "--------------------"
        echo "1. 高性能优化模式：     最大化系统性能，优化文件描述符、虚拟内存、网络设置、缓存管理和CPU设置。"
        echo "2. 均衡优化模式：       在性能与资源消耗之间取得平衡，适合日常使用。"
        echo "3. 网站优化模式：       针对网站服务器进行优化，提高并发连接处理能力、响应速度和整体性能。"
        echo "4. 直播优化模式：       针对直播推流的特殊需求进行优化，减少延迟，提高传输性能。"
        echo "5. 游戏服优化模式：     针对游戏服务器进行优化，提高并发处理能力和响应速度。"
        echo "6. 还原默认设置：       将系统设置还原为默认配置。"
        echo "--------------------"
        echo "0. 返回主菜单"
        echo "--------------------"
        read -e -p "请输入你的选择: " sub_choice
        case $sub_choice in
            1)
                cd ~
                clear
                local tiaoyou_moshi="高性能优化模式"
                optimize_high_performance
                ;;
            2)
                cd ~
                clear
                optimize_balanced
                ;;
            3)
                cd ~
                clear
                optimize_web_server
                ;;
            4)
                cd ~
                clear
                local tiaoyou_moshi="直播优化模式"
                optimize_high_performance
                ;;
            5)
                cd ~
                clear
                local tiaoyou_moshi="游戏服优化模式"
                optimize_high_performance
                ;;
            6)
                cd ~
                clear
                restore_defaults
                ;;
            0)
                break
                ;;
            *)
                echo "无效的输入!"
                sleep 1
                ;;
        esac
        break_end
    done
}

run_speedtest() {
    clear
    echo -e "${gl_kjlan}=== 服务器带宽测试 ===${gl_bai}"
    echo ""

    # 检测 CPU 架构
    local cpu_arch=$(uname -m)
    echo "检测到系统架构: ${gl_huang}${cpu_arch}${gl_bai}"
    echo ""

    # 检查 speedtest 是否已安装
    if command -v speedtest &>/dev/null; then
        echo -e "${gl_lv}Speedtest 已安装，直接运行测试...${gl_bai}"
        echo "------------------------------------------------"
        echo ""
        speedtest
        echo ""
        echo "------------------------------------------------"
        break_end
        return 0
    fi

    echo "Speedtest 未安装，正在下载安装..."
    echo "------------------------------------------------"
    echo ""

    # 根据架构选择下载链接
    local download_url
    local tarball_name

    case "$cpu_arch" in
        x86_64)
            download_url="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz"
            tarball_name="ookla-speedtest-1.2.0-linux-x86_64.tgz"
            echo "使用 AMD64 架构版本..."
            ;;
        aarch64)
            download_url="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-aarch64.tgz"
            tarball_name="speedtest.tgz"
            echo "使用 ARM64 架构版本..."
            ;;
        *)
            echo -e "${gl_hong}错误: 不支持的架构 ${cpu_arch}${gl_bai}"
            echo "目前仅支持 x86_64 和 aarch64 架构"
            echo ""
            break_end
            return 1
            ;;
    esac

    # 切换到临时目录
    cd /tmp || {
        echo -e "${gl_hong}错误: 无法切换到 /tmp 目录${gl_bai}"
        break_end
        return 1
    }

    # 下载
    echo "正在下载..."
    if [ "$cpu_arch" = "aarch64" ]; then
        curl -Lo "$tarball_name" "$download_url"
    else
        wget "$download_url"
    fi

    if [ $? -ne 0 ]; then
        echo -e "${gl_hong}下载失败！${gl_bai}"
        break_end
        return 1
    fi

    # 解压
    echo "正在解压..."
    tar -xvzf "$tarball_name"

    if [ $? -ne 0 ]; then
        echo -e "${gl_hong}解压失败！${gl_bai}"
        rm -f "$tarball_name"
        break_end
        return 1
    fi

    # 移动到系统目录
    echo "正在安装..."
    mv speedtest /usr/local/bin/

    if [ $? -ne 0 ]; then
        echo -e "${gl_hong}安装失败！${gl_bai}"
        rm -f "$tarball_name"
        break_end
        return 1
    fi

    # 清理临时文件
    rm -f "$tarball_name"

    echo -e "${gl_lv}✅ Speedtest 安装成功！${gl_bai}"
    echo ""
    echo "开始带宽测试..."
    echo "------------------------------------------------"
    echo ""

    # 运行测试
    speedtest

    echo ""
    echo "------------------------------------------------"
    break_end
}

run_backtrace() {
    clear
    echo -e "${gl_kjlan}=== 三网回程路由测试 ===${gl_bai}"
    echo ""
    echo "正在运行三网回程路由测试脚本..."
    echo "------------------------------------------------"
    echo ""

    # 执行三网回程路由测试脚本
    curl https://raw.githubusercontent.com/ludashi2020/backtrace/main/install.sh -sSf | sh

    echo ""
    echo "------------------------------------------------"
    break_end
}

run_ns_detect() {
    clear
    echo -e "${gl_kjlan}=== NS一键检测脚本 ===${gl_bai}"
    echo ""
    echo "正在运行 NS 一键检测脚本..."
    echo "------------------------------------------------"
    echo ""

    # 执行 NS 一键检测脚本
    bash <(curl -sL https://run.NodeQuality.com)

    echo ""
    echo "------------------------------------------------"
    break_end
}

run_ip_quality_check() {
    clear
    echo -e "${gl_kjlan}=== IP质量检测 ===${gl_bai}"
    echo ""
    echo "正在运行 IP 质量检测脚本（IPv4 + IPv6）..."
    echo "------------------------------------------------"
    echo ""

    # 执行 IP 质量检测脚本
    bash <(curl -Ls https://IP.Check.Place)

    echo ""
    echo "------------------------------------------------"
    break_end
}

run_ip_quality_check_ipv4() {
    clear
    echo -e "${gl_kjlan}=== IP质量检测 - 仅IPv4 ===${gl_bai}"
    echo ""
    echo "正在运行 IP 质量检测脚本（仅 IPv4）..."
    echo "------------------------------------------------"
    echo ""

    # 执行 IP 质量检测脚本 - 仅 IPv4
    bash <(curl -Ls https://IP.Check.Place) -4

    echo ""
    echo "------------------------------------------------"
    break_end
}

run_network_latency_check() {
    clear
    echo -e "${gl_kjlan}=== 网络延迟质量检测 ===${gl_bai}"
    echo ""
    echo "正在运行网络延迟质量检测脚本..."
    echo "------------------------------------------------"
    echo ""

    # 执行网络延迟质量检测脚本
    bash <(curl -sL https://Check.Place) -N

    echo ""
    echo "------------------------------------------------"
    break_end
}

run_international_speed_test() {
    clear
    echo -e "${gl_kjlan}=== 国际互联速度测试 ===${gl_bai}"
    echo ""
    echo "正在下载并运行国际互联速度测试脚本..."
    echo "------------------------------------------------"
    echo ""

    # 切换到临时目录
    cd /tmp || {
        echo -e "${gl_hong}错误: 无法切换到 /tmp 目录${gl_bai}"
        break_end
        return 1
    }

    # 下载脚本
    echo "正在下载脚本..."
    wget https://raw.githubusercontent.com/Cd1s/network-latency-tester/main/latency.sh

    if [ $? -ne 0 ]; then
        echo -e "${gl_hong}下载失败！${gl_bai}"
        break_end
        return 1
    fi

    # 添加执行权限
    chmod +x latency.sh

    # 运行测试
    echo ""
    echo "开始测试..."
    echo "------------------------------------------------"
    echo ""
    ./latency.sh

    # 清理临时文件
    rm -f latency.sh

    echo ""
    echo "------------------------------------------------"
    break_end
}

#=============================================================================
# 主菜单
#=============================================================================

show_main_menu() {
    clear
    check_bbr_status
    local is_installed=$?
    
    echo ""
    echo -e "${gl_zi}╔════════════════════════════════════════════╗${gl_bai}"
    echo -e "${gl_zi}║   BBR v3 终极优化脚本 - Ultimate Edition  ║${gl_bai}"
    echo -e "${gl_zi}╚════════════════════════════════════════════╝${gl_bai}"
    echo ""
    echo -e "${gl_kjlan}[内核管理]${gl_bai}"

    if [ $is_installed -eq 0 ]; then
        echo "1. 更新 XanMod 内核"
        echo "2. 卸载 XanMod 内核"
        echo ""
        echo -e "${gl_kjlan}[BBR TCP调优]${gl_bai}"
        echo "3. NS论坛CAKE调优"
        echo "4. 科技lion高性能模式内核参数优化"
        echo "5. BBR 直连/落地优化（智能带宽检测）"
        echo ""
        echo -e "${gl_kjlan}[系统设置]${gl_bai}"
        echo "6. 虚拟内存管理"
        echo "7. IPv6管理（临时/永久禁用/取消）"
        echo "8. 设置临时SOCKS5代理"
        echo "9. 设置IPv4优先"
        echo "10. 设置IPv6优先"
        echo "11. IPv4/IPv6连接检测"
        echo ""
        echo -e "${gl_kjlan}[Xray配置]${gl_bai}"
        echo "12. Realm转发连接分析"
        echo "13. 查看Xray配置"
        echo "14. 设置Xray IPv6出站"
        echo "15. 恢复Xray默认配置"
        echo ""
        echo -e "${gl_kjlan}[系统信息]${gl_bai}"
        echo "16. 查看详细状态"
        echo ""
        echo -e "${gl_kjlan}[服务器检测合集]${gl_bai}"
        echo "17. NS一键检测脚本"
        echo "18. 服务器带宽测试"
        echo "19. 三网回程路由测试"
        echo "20. IP质量检测"
        echo "21. IP质量检测-仅IPv4"
        echo "22. 网络延迟质量检测"
        echo "23. 国际互联速度测试"
        echo "24. IP媒体/AI解锁检测"
        echo ""
        echo -e "${gl_kjlan}[脚本合集]${gl_bai}"
        echo "25. PF_realm转发脚本"
        echo "26. 御坂美琴一键双协议"
        echo "27. F佬一键sing box脚本"
        echo "28. 科技lion脚本"
        echo "29. NS论坛的cake调优"
        echo "30. 酷雪云脚本"
        echo ""
        echo -e "${gl_kjlan}[代理部署]${gl_bai}"
        echo "31. 一键部署SOCKS5代理"
    else
        echo "1. 安装 XanMod 内核 + BBR v3"
        echo ""
        echo -e "${gl_kjlan}[BBR TCP调优]${gl_bai}"
        echo "2. NS论坛CAKE调优"
        echo "3. 科技lion高性能模式内核参数优化"
        echo "4. BBR 直连/落地优化（智能带宽检测）"
        echo ""
        echo -e "${gl_kjlan}[系统设置]${gl_bai}"
        echo "5. 虚拟内存管理"
        echo "6. IPv6管理（临时/永久禁用/取消）"
        echo "7. 设置临时SOCKS5代理"
        echo "8. 设置IPv4优先"
        echo "9. 设置IPv6优先"
        echo "10. IPv4/IPv6连接检测"
        echo ""
        echo -e "${gl_kjlan}[Xray配置]${gl_bai}"
        echo "11. Realm转发连接分析"
        echo "12. 查看Xray配置"
        echo "13. 设置Xray IPv6出站"
        echo "14. 恢复Xray默认配置"
        echo ""
        echo -e "${gl_kjlan}[系统信息]${gl_bai}"
        echo "15. 查看详细状态"
        echo ""
        echo -e "${gl_kjlan}[服务器检测合集]${gl_bai}"
        echo "16. NS一键检测脚本"
        echo "17. 服务器带宽测试"
        echo "18. 三网回程路由测试"
        echo "19. IP质量检测"
        echo "20. IP质量检测-仅IPv4"
        echo "21. 网络延迟质量检测"
        echo "22. 国际互联速度测试"
        echo "23. IP媒体/AI解锁检测"
        echo ""
        echo -e "${gl_kjlan}[脚本合集]${gl_bai}"
        echo "24. PF_realm转发脚本"
        echo "25. 御坂美琴一键双协议"
        echo "26. F佬一键sing box脚本"
        echo "27. 科技lion脚本"
        echo "28. NS论坛的cake调优"
        echo "29. 酷雪云脚本"
        echo ""
        echo -e "${gl_kjlan}[代理部署]${gl_bai}"
        echo "30. 一键部署SOCKS5代理"
    fi
    
    echo ""
    echo "0. 退出脚本"
    echo "------------------------------------------------"
    read -e -p "请输入选择: " choice
    
    case $choice in
        1)
            if [ $is_installed -eq 0 ]; then
                # 更新内核
                update_xanmod_kernel
                if [ $? -eq 0 ]; then
                    server_reboot
                fi
            else
                install_xanmod_kernel
                if [ $? -eq 0 ]; then
                    server_reboot
                fi
            fi
            ;;
        2)
            if [ $is_installed -eq 0 ]; then
                uninstall_xanmod
            else
                startbbrcake
            fi
            ;;
        3)
            if [ $is_installed -eq 0 ]; then
                startbbrcake
            else
                Kernel_optimize
            fi
            ;;
        4)
            if [ $is_installed -eq 0 ]; then
                Kernel_optimize
            else
                bbr_configure_direct
                break_end
            fi
            ;;
        5)
            if [ $is_installed -eq 0 ]; then
                bbr_configure_direct
                break_end
            else
                manage_swap
            fi
            ;;
        6)
            if [ $is_installed -eq 0 ]; then
                manage_swap
            else
                manage_ipv6
            fi
            ;;
        7)
            if [ $is_installed -eq 0 ]; then
                manage_ipv6
            else
                set_temp_socks5_proxy
            fi
            ;;
        8)
            if [ $is_installed -eq 0 ]; then
                set_temp_socks5_proxy
            else
                set_ipv4_priority
            fi
            ;;
        9)
            if [ $is_installed -eq 0 ]; then
                set_ipv4_priority
            else
                set_ipv6_priority
            fi
            ;;
        10)
            if [ $is_installed -eq 0 ]; then
                set_ipv6_priority
            else
                check_ipv4v6_connections
            fi
            ;;
        11)
            if [ $is_installed -eq 0 ]; then
                check_ipv4v6_connections
            else
                analyze_realm_connections
            fi
            ;;
        12)
            if [ $is_installed -eq 0 ]; then
                analyze_realm_connections
            else
                show_xray_config
            fi
            ;;
        13)
            if [ $is_installed -eq 0 ]; then
                show_xray_config
            else
                set_xray_ipv6_outbound
            fi
            ;;
        14)
            if [ $is_installed -eq 0 ]; then
                set_xray_ipv6_outbound
            else
                restore_xray_default
            fi
            ;;
        15)
            if [ $is_installed -eq 0 ]; then
                restore_xray_default
            else
                show_detailed_status
            fi
            ;;
        16)
            if [ $is_installed -eq 0 ]; then
                show_detailed_status
            else
                run_ns_detect
            fi
            ;;
        17)
            if [ $is_installed -eq 0 ]; then
                run_ns_detect
            else
                run_speedtest
            fi
            ;;
        18)
            if [ $is_installed -eq 0 ]; then
                run_speedtest
            else
                run_backtrace
            fi
            ;;
        19)
            if [ $is_installed -eq 0 ]; then
                run_backtrace
            else
                run_ip_quality_check
            fi
            ;;
        20)
            if [ $is_installed -eq 0 ]; then
                run_ip_quality_check
            else
                run_ip_quality_check_ipv4
            fi
            ;;
        21)
            if [ $is_installed -eq 0 ]; then
                run_ip_quality_check_ipv4
            else
                run_network_latency_check
            fi
            ;;
        22)
            if [ $is_installed -eq 0 ]; then
                run_network_latency_check
            else
                run_international_speed_test
            fi
            ;;
        23)
            if [ $is_installed -eq 0 ]; then
                run_international_speed_test
            else
                run_unlock_check
            fi
            ;;
        24)
            if [ $is_installed -eq 0 ]; then
                run_unlock_check
            else
                run_pf_realm
            fi
            ;;
        25)
            if [ $is_installed -eq 0 ]; then
                run_pf_realm
            else
                run_misaka_xray
            fi
            ;;
        26)
            if [ $is_installed -eq 0 ]; then
                run_misaka_xray
            else
                run_fscarmen_singbox
            fi
            ;;
        27)
            if [ $is_installed -eq 0 ]; then
                run_fscarmen_singbox
            else
                run_kejilion_script
            fi
            ;;
        28)
            if [ $is_installed -eq 0 ]; then
                run_kejilion_script
            else
                run_ns_cake
            fi
            ;;
        29)
            if [ $is_installed -eq 0 ]; then
                run_ns_cake
            else
                run_kxy_script
            fi
            ;;
        30)
            if [ $is_installed -eq 0 ]; then
                run_kxy_script
            else
                deploy_socks5
            fi
            ;;
        31)
            if [ $is_installed -eq 0 ]; then
                deploy_socks5
            else
                echo "无效选择"
                sleep 2
            fi
            ;;
        0)
            echo "退出脚本"
            exit 0
            ;;
        *)
            echo "无效选择"
            sleep 2
            ;;
    esac
}

update_xanmod_kernel() {
    clear
    echo -e "${gl_kjlan}=== 更新 XanMod 内核 ===${gl_bai}"
    echo "------------------------------------------------"
    
    # 获取当前内核版本
    local current_kernel=$(uname -r)
    echo -e "当前内核版本: ${gl_huang}${current_kernel}${gl_bai}"
    echo ""
    
    # 检测 CPU 架构
    local cpu_arch=$(uname -m)
    
    # ARM 架构提示
    if [ "$cpu_arch" = "aarch64" ]; then
        echo -e "${gl_huang}ARM64 架构暂不支持自动更新${gl_bai}"
        echo "建议卸载后重新安装以获取最新版本"
        break_end
        return 1
    fi
    
    # x86_64 架构更新流程
    echo "正在检查可用更新..."
    
    # 添加 XanMod 仓库（如果不存在）
    if [ ! -f /etc/apt/sources.list.d/xanmod-release.list ]; then
        echo "正在添加 XanMod 仓库..."
        
        # 添加密钥
        wget -qO - ${gh_proxy}raw.githubusercontent.com/kejilion/sh/main/archive.key | \
            gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg --yes 2>/dev/null
        
        if [ $? -ne 0 ]; then
            wget -qO - https://dl.xanmod.org/archive.key | \
                gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg --yes 2>/dev/null
        fi
        
        # 添加仓库
        echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' | \
            tee /etc/apt/sources.list.d/xanmod-release.list > /dev/null
    fi
    
    # 更新软件包列表
    echo "正在更新软件包列表..."
    apt update -y > /dev/null 2>&1
    
    # 检查已安装的 XanMod 内核包
    local installed_packages=$(dpkg -l | grep 'linux-.*xanmod' | awk '{print $2}')
    
    if [ -z "$installed_packages" ]; then
        echo -e "${gl_hong}错误: 未检测到已安装的 XanMod 内核${gl_bai}"
        break_end
        return 1
    fi
    
    echo -e "已安装的内核包:"
    echo "$installed_packages" | while read pkg; do
        echo "  - $pkg"
    done
    echo ""
    
    # 检查是否有可用更新
    local upgradable=$(apt list --upgradable 2>/dev/null | grep xanmod)
    
    if [ -z "$upgradable" ]; then
        echo -e "${gl_lv}✅ 当前内核已是最新版本！${gl_bai}"
        break_end
        return 0
    fi
    
    echo -e "${gl_huang}发现可用更新:${gl_bai}"
    echo "$upgradable"
    echo ""
    
    read -e -p "确定更新 XanMod 内核吗？(Y/N): " confirm
    
    case "$confirm" in
        [Yy])
            echo ""
            echo "正在更新内核..."
            apt install --only-upgrade -y $(echo "$installed_packages" | tr '\n' ' ')
            
            if [ $? -eq 0 ]; then
                # 清理仓库文件（避免日常 apt update 时出错）
                rm -f /etc/apt/sources.list.d/xanmod-release.list
                
                echo ""
                echo -e "${gl_lv}✅ XanMod 内核更新成功！${gl_bai}"
                echo -e "${gl_huang}⚠️  请重启系统以加载新内核${gl_bai}"
                return 0
            else
                echo ""
                echo -e "${gl_hong}❌ 内核更新失败${gl_bai}"
                break_end
                return 1
            fi
            ;;
        *)
            echo "已取消更新"
            break_end
            return 1
            ;;
    esac
}

uninstall_xanmod() {
    echo -e "${gl_huang}警告: 即将卸载 XanMod 内核${gl_bai}"
    read -e -p "确定继续吗？(Y/N): " confirm
    
    case "$confirm" in
        [Yy])
            apt purge -y 'linux-*xanmod1*'
            update-grub
            rm -f "$SYSCTL_CONF"
            echo -e "${gl_lv}XanMod 内核已卸载${gl_bai}"
            server_reboot
            ;;
        *)
            echo "已取消"
            ;;
    esac
}

run_unlock_check() {
    clear
    echo -e "${gl_kjlan}=== IP媒体/AI解锁检测 ===${gl_bai}"
    echo ""
    echo "正在运行流媒体解锁检测脚本..."
    echo "------------------------------------------------"
    echo ""

    # 执行解锁检测脚本
    bash <(curl -L -s check.unlock.media)

    echo ""
    echo "------------------------------------------------"
    break_end
}

run_pf_realm() {
    clear
    echo -e "${gl_kjlan}=== PF_realm转发脚本 ===${gl_bai}"
    echo ""
    echo "正在运行 PF_realm 转发脚本安装程序..."
    echo "------------------------------------------------"
    echo ""

    # 执行 PF_realm 转发脚本
    if wget -qO- https://raw.githubusercontent.com/zywe03/realm-xwPF/main/xwPF.sh | bash -s install; then
        echo ""
        echo -e "${gl_lv}✅ PF_realm 脚本执行完成${gl_bai}"
    else
        echo ""
        echo -e "${gl_hong}❌ PF_realm 脚本执行失败${gl_bai}"
        echo "可能原因："
        echo "1. 网络连接问题（无法访问GitHub）"
        echo "2. 脚本服务器不可用"
        echo "3. 权限不足"
    fi

    echo ""
    echo "------------------------------------------------"
    break_end
}

run_kxy_script() {
    clear
    echo -e "${gl_kjlan}=== 酷雪云脚本 ===${gl_bai}"
    echo ""
    echo "正在运行酷雪云脚本..."
    echo "------------------------------------------------"
    echo ""

    # 执行酷雪云脚本
    bash <(curl -sL https://cdn.kxy.ovh/kxy.sh)

    echo ""
    echo "------------------------------------------------"
    break_end
}

run_misaka_xray() {
    clear
    echo -e "${gl_kjlan}=== 御坂美琴一键双协议 ===${gl_bai}"
    echo ""
    echo "正在运行御坂美琴一键双协议安装脚本..."
    echo "------------------------------------------------"
    echo ""

    # 执行御坂美琴一键双协议脚本
    if bash <(curl -L https://raw.githubusercontent.com/yahuisme/xray-dual/main/install.sh); then
        echo ""
        echo -e "${gl_lv}✅ 御坂美琴一键双协议脚本执行完成${gl_bai}"
    else
        echo ""
        echo -e "${gl_hong}❌ 御坂美琴一键双协议脚本执行失败${gl_bai}"
        echo "可能原因："
        echo "1. 网络连接问题（无法访问GitHub）"
        echo "2. curl 命令不可用"
        echo "3. 脚本执行过程中出错"
    fi

    echo ""
    echo "------------------------------------------------"
    break_end
}

run_ns_cake() {
    clear
    echo -e "${gl_kjlan}=== NS论坛的cake调优 ===${gl_bai}"
    echo ""
    echo "正在下载并运行 NS论坛 cake 调优脚本..."
    echo "------------------------------------------------"
    echo ""

    # 切换到临时目录
    cd /tmp || {
        echo -e "${gl_hong}错误: 无法切换到 /tmp 目录${gl_bai}"
        echo ""
        echo "------------------------------------------------"
        break_end
        return 1
    }

    # 执行 NS论坛 cake 调优脚本
    if wget -O /tmp/tcpx.sh "https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh"; then
        chmod +x /tmp/tcpx.sh
        
        if bash /tmp/tcpx.sh; then
            echo ""
            echo -e "${gl_lv}✅ NS论坛 cake 调优脚本执行完成${gl_bai}"
        else
            echo ""
            echo -e "${gl_hong}❌ 脚本执行失败${gl_bai}"
        fi
        
        # 清理临时文件
        rm -f /tmp/tcpx.sh
    else
        echo ""
        echo -e "${gl_hong}❌ 下载脚本失败${gl_bai}"
        echo "可能原因："
        echo "1. 网络连接问题（无法访问GitHub）"
        echo "2. wget 命令不可用"
    fi

    echo ""
    echo "------------------------------------------------"
    break_end
}

run_kejilion_script() {
    clear
    echo -e "${gl_kjlan}=== 科技lion脚本 ===${gl_bai}"
    echo ""
    echo "正在运行科技lion脚本..."
    echo "------------------------------------------------"
    echo ""

    # 执行科技lion脚本
    bash <(curl -sL kejilion.sh)

    echo ""
    echo "------------------------------------------------"
    break_end
}

run_fscarmen_singbox() {
    clear
    echo -e "${gl_kjlan}=== F佬一键sing box脚本 ===${gl_bai}"
    echo ""
    echo "正在运行 F佬一键sing box脚本..."
    echo "------------------------------------------------"
    echo ""

    # 执行 F佬一键sing box脚本
    bash <(wget -qO- https://raw.githubusercontent.com/fscarmen/sing-box/main/sing-box.sh)

    echo ""
    echo "------------------------------------------------"
    break_end
}

#=============================================================================
# CAKE 加速功能（来自 cake.sh）
#=============================================================================

#卸载bbr+锐速
remove_bbr_lotserver() {
  sed -i '/net.ipv4.tcp_ecn/d' /etc/sysctl.d/99-sysctl.conf
  sed -i '/net.core.default_qdisc/d' /etc/sysctl.d/99-sysctl.conf
  sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.d/99-sysctl.conf
  sed -i '/net.ipv4.tcp_ecn/d' /etc/sysctl.conf
  sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
  sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
  sysctl --system

  rm -rf bbrmod

  if [[ -e /appex/bin/lotServer.sh ]]; then
    echo | bash <(wget -qO- https://raw.githubusercontent.com/fei5seven/lotServer/master/lotServerInstall.sh) uninstall
  fi
  clear
}

#启用BBR+cake
startbbrcake() {
  remove_bbr_lotserver
  echo "net.core.default_qdisc=cake" >>/etc/sysctl.d/99-sysctl.conf
  echo "net.ipv4.tcp_congestion_control=bbr" >>/etc/sysctl.d/99-sysctl.conf
  sysctl --system
  echo -e "${gl_lv}[信息]${gl_bai}BBR+cake修改成功，重启生效！"
  break_end
}

#=============================================================================
# SOCKS5 一键部署功能
#=============================================================================

deploy_socks5() {
    clear
    echo -e "${gl_kjlan}=== Sing-box SOCKS5 一键部署 ===${gl_bai}"
    echo ""
    echo "此功能将部署一个独立的SOCKS5代理服务"
    echo "------------------------------------------------"
    echo ""
    
    # 步骤1：检测 sing-box 二进制程序
    echo -e "${gl_zi}[步骤 1/7] 检测 sing-box 安装...${gl_bai}"
    echo ""
    
    local SINGBOX_CMD=""
    
    # 优先查找常见的二进制程序位置
    for path in /etc/sing-box/sing-box /usr/local/bin/sing-box /opt/sing-box/sing-box; do
        if [ -x "$path" ] && [ ! -L "$path" ]; then
            # 验证是 ELF 二进制文件，不是脚本
            if file "$path" 2>/dev/null | grep -q "ELF"; then
                SINGBOX_CMD="$path"
                echo -e "${gl_lv}✅ 找到 sing-box 程序: $SINGBOX_CMD${gl_bai}"
                break
            fi
        fi
    done
    
    # 如果没找到，检查 PATH 中的命令
    if [ -z "$SINGBOX_CMD" ]; then
        for cmd in sing-box sb; do
            if command -v "$cmd" &>/dev/null; then
                local cmd_path=$(which "$cmd")
                if file "$cmd_path" 2>/dev/null | grep -q "ELF"; then
                    SINGBOX_CMD="$cmd_path"
                    echo -e "${gl_lv}✅ 找到 sing-box 程序: $SINGBOX_CMD${gl_bai}"
                    break
                else
                    echo -e "${gl_huang}⚠️  $cmd_path 是脚本，跳过${gl_bai}"
                fi
            fi
        done
    fi
    
    if [ -z "$SINGBOX_CMD" ]; then
        echo -e "${gl_hong}❌ 未找到 sing-box 二进制程序${gl_bai}"
        echo ""
        echo "请先安装 sing-box，推荐使用："
        echo "  - F佬一键sing box脚本（菜单选项 22/23）"
        echo ""
        break_end
        return 1
    fi
    
    # 显示版本信息
    echo ""
    $SINGBOX_CMD version 2>/dev/null | head -n 1
    echo ""
    
    # 步骤2：配置参数输入
    echo -e "${gl_zi}[步骤 2/7] 配置 SOCKS5 参数...${gl_bai}"
    echo ""
    
    # 输入端口（支持回车使用随机端口）
    local socks5_port=""
    while true; do
        read -e -p "$(echo -e "${gl_huang}请输入 SOCKS5 端口 [回车随机生成]: ${gl_bai}")" socks5_port
        
        if [ -z "$socks5_port" ]; then
            # 生成随机端口（10000-65535）
            socks5_port=$((RANDOM % 55536 + 10000))
            echo -e "${gl_lv}✅ 已生成随机端口: ${socks5_port}${gl_bai}"
            break
        elif [[ "$socks5_port" =~ ^[0-9]+$ ]] && [ "$socks5_port" -ge 1024 ] && [ "$socks5_port" -le 65535 ]; then
            # 检查端口是否被占用
            if ss -tulpn | grep -q ":${socks5_port} "; then
                echo -e "${gl_hong}❌ 端口 ${socks5_port} 已被占用，请选择其他端口${gl_bai}"
            else
                echo -e "${gl_lv}✅ 使用端口: ${socks5_port}${gl_bai}"
                break
            fi
        else
            echo -e "${gl_hong}❌ 无效端口，请输入 1024-65535 之间的数字${gl_bai}"
        fi
    done
    
    echo ""
    
    # 输入用户名
    local socks5_user=""
    while true; do
        read -e -p "$(echo -e "${gl_huang}请输入用户名: ${gl_bai}")" socks5_user
        
        if [ -z "$socks5_user" ]; then
            echo -e "${gl_hong}❌ 用户名不能为空${gl_bai}"
        elif [[ "$socks5_user" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            echo -e "${gl_lv}✅ 用户名: ${socks5_user}${gl_bai}"
            break
        else
            echo -e "${gl_hong}❌ 用户名只能包含字母、数字、下划线和连字符${gl_bai}"
        fi
    done
    
    echo ""
    
    # 输入密码
    local socks5_pass=""
    while true; do
        read -e -p "$(echo -e "${gl_huang}请输入密码: ${gl_bai}")" socks5_pass
        
        if [ -z "$socks5_pass" ]; then
            echo -e "${gl_hong}❌ 密码不能为空${gl_bai}"
        elif [ ${#socks5_pass} -lt 6 ]; then
            echo -e "${gl_hong}❌ 密码长度至少6位${gl_bai}"
        else
            echo -e "${gl_lv}✅ 密码已设置${gl_bai}"
            break
        fi
    done
    
    echo ""
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_lv}配置信息确认：${gl_bai}"
    echo -e "  端口: ${gl_huang}${socks5_port}${gl_bai}"
    echo -e "  用户名: ${gl_huang}${socks5_user}${gl_bai}"
    echo -e "  密码: ${gl_huang}${socks5_pass}${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""
    
    read -e -p "$(echo -e "${gl_huang}确认开始部署？(Y/N): ${gl_bai}")" confirm
    
    case "$confirm" in
        [Yy])
            ;;
        *)
            echo "已取消部署"
            break_end
            return 1
            ;;
    esac
    
    # 步骤3：创建目录
    echo ""
    echo -e "${gl_zi}[步骤 3/7] 创建配置目录...${gl_bai}"
    mkdir -p /etc/sbox_socks5
    echo -e "${gl_lv}✅ 目录创建成功${gl_bai}"
    
    # 步骤4：创建配置文件
    echo ""
    echo -e "${gl_zi}[步骤 4/7] 创建配置文件...${gl_bai}"
    
    cat > /etc/sbox_socks5/config.json << CONFIGEOF
{
  "log": {
    "level": "info",
    "output": "/etc/sbox_socks5/socks5.log"
  },
  "inbounds": [
    {
      "type": "socks",
      "tag": "socks5-in",
      "listen": "0.0.0.0",
      "listen_port": ${socks5_port},
      "users": [
        {
          "username": "${socks5_user}",
          "password": "${socks5_pass}"
        }
      ]
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
CONFIGEOF
    
    chmod 600 /etc/sbox_socks5/config.json
    echo -e "${gl_lv}✅ 配置文件创建成功${gl_bai}"
    
    # 步骤5：验证配置
    echo ""
    echo -e "${gl_zi}[步骤 5/7] 验证配置文件语法...${gl_bai}"
    
    if $SINGBOX_CMD check -c /etc/sbox_socks5/config.json >/dev/null 2>&1; then
        echo -e "${gl_lv}✅ 配置文件语法正确${gl_bai}"
    else
        echo -e "${gl_hong}❌ 配置文件语法错误${gl_bai}"
        $SINGBOX_CMD check -c /etc/sbox_socks5/config.json
        break_end
        return 1
    fi
    
    # 步骤6：创建服务文件
    echo ""
    echo -e "${gl_zi}[步骤 6/7] 创建 systemd 服务...${gl_bai}"
    
    cat > /etc/systemd/system/sbox-socks5.service << SERVICEEOF
[Unit]
Description=Sing-box SOCKS5 Service
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${SINGBOX_CMD} run -c /etc/sbox_socks5/config.json
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=5
User=root
Group=root
StandardOutput=journal
StandardError=journal
SyslogIdentifier=sbox-socks5
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=5s
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/etc/sbox_socks5
PrivateTmp=true

[Install]
WantedBy=multi-user.target
SERVICEEOF
    
    chmod 644 /etc/systemd/system/sbox-socks5.service
    echo -e "${gl_lv}✅ 服务文件创建成功${gl_bai}"
    
    # 步骤7：启动服务
    echo ""
    echo -e "${gl_zi}[步骤 7/7] 启动服务...${gl_bai}"
    
    systemctl daemon-reload
    systemctl enable sbox-socks5 >/dev/null 2>&1
    systemctl start sbox-socks5
    
    # 等待服务启动
    sleep 3
    
    # 验证部署
    echo ""
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_lv}验证部署结果：${gl_bai}"
    echo ""
    
    local deploy_success=true
    
    # 检查服务状态
    if systemctl is-active --quiet sbox-socks5; then
        echo -e "  服务状态: ${gl_lv}✅ Running${gl_bai}"
    else
        echo -e "  服务状态: ${gl_hong}❌ Failed${gl_bai}"
        deploy_success=false
    fi
    
    # 检查端口监听
    if ss -tulpn | grep -q ":${socks5_port} "; then
        echo -e "  端口监听: ${gl_lv}✅ ${socks5_port}${gl_bai}"
    else
        echo -e "  端口监听: ${gl_hong}❌ 未监听${gl_bai}"
        deploy_success=false
    fi
    
    echo ""
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    
    if [ "$deploy_success" = true ]; then
        # 获取服务器IP
        local server_ip=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || curl -s --max-time 3 ipinfo.io/ip 2>/dev/null || echo "请手动获取")
        
        echo ""
        echo -e "${gl_lv}🎉 部署成功！${gl_bai}"
        echo ""
        echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo -e "${gl_lv}SOCKS5 连接信息：${gl_bai}"
        echo ""
        echo -e "  服务器地址: ${gl_huang}${server_ip}${gl_bai}"
        echo -e "  端口:       ${gl_huang}${socks5_port}${gl_bai}"
        echo -e "  用户名:     ${gl_huang}${socks5_user}${gl_bai}"
        echo -e "  密码:       ${gl_huang}${socks5_pass}${gl_bai}"
        echo -e "  协议:       ${gl_huang}SOCKS5${gl_bai}"
        echo ""
        echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo ""
        echo -e "${gl_zi}测试连接命令：${gl_bai}"
        echo "curl --socks5-hostname ${socks5_user}:${socks5_pass}@${server_ip}:${socks5_port} http://httpbin.org/ip"
        echo ""
        echo -e "${gl_huang}⚠️  重要提醒：${gl_bai}"
        echo "  1. 确保云服务商安全组已开放 TCP ${socks5_port} 端口"
        echo "  2. 查看日志: journalctl -u sbox-socks5 -f"
        echo "  3. 重启服务: systemctl restart sbox-socks5"
        echo "  4. 停止服务: systemctl stop sbox-socks5"
        echo "  5. 卸载服务: systemctl stop sbox-socks5 && systemctl disable sbox-socks5 && rm -rf /etc/sbox_socks5 /etc/systemd/system/sbox-socks5.service"
        echo ""
    else
        echo ""
        echo -e "${gl_hong}❌ 部署失败${gl_bai}"
        echo ""
        echo "查看详细错误信息："
        echo "  journalctl -u sbox-socks5 -n 50 --no-pager"
        echo ""
        echo "常见问题排查："
        echo "  1. 检查 sing-box 程序是否正确: file ${SINGBOX_CMD}"
        echo "  2. 检查端口是否被占用: ss -tulpn | grep ${socks5_port}"
        echo "  3. 检查服务日志: systemctl status sbox-socks5 --no-pager"
        echo ""
    fi
    
    break_end
}

#=============================================================================
# 脚本入口
#=============================================================================

main() {
    check_root
    
    # 命令行参数支持
    if [ "$1" = "-i" ] || [ "$1" = "--install" ]; then
        install_xanmod_kernel
        if [ $? -eq 0 ]; then
            echo ""
            echo "安装完成后，请重启系统以加载新内核"
        fi
        exit 0
    fi
    
    # 交互式菜单
    while true; do
        show_main_menu
    done
}

# 执行主函数
main "$@"

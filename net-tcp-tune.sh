#!/bin/bash
#=============================================================================
# BBR v3 终极优化脚本 - 融合版
# 功能：结合 XanMod 官方内核的稳定性 + 专业队列算法调优
# 特点：安全性 + 性能 双优化
# 版本：3.0 Ultimate Pro Edition
# 新增功能：UDP优化、tc fq立即生效、MSS clamp、并发优化、精准BDP、fq限速
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
# 新增功能函数
#=============================================================================

# 检查并清理冲突的配置文件
check_and_clean_conflicts() {
    echo -e "${gl_kjlan}=== 检查配置冲突 ===${gl_bai}"
    
    local conflicts_found=0
    local conflict_files=()
    
    # 检查可能冲突的配置文件（文件名排序在 99 之后的）
    for conf in /etc/sysctl.d/[0-9]*-*.conf /etc/sysctl.d/[0-9][0-9][0-9]-*.conf; do
        if [ -f "$conf" ] && [ "$conf" != "$SYSCTL_CONF" ]; then
            # 检查是否包含 TCP 缓冲区配置
            if grep -q "tcp_wmem\|tcp_rmem" "$conf" 2>/dev/null; then
                local filename=$(basename "$conf")
                local filenum=$(echo "$filename" | grep -oP '^\d+')
                
                # 如果文件编号 >= 99，可能会覆盖我们的配置
                if [ -n "$filenum" ] && [ "$filenum" -ge 99 ]; then
                    conflict_files+=("$conf")
                    conflicts_found=1
                fi
            fi
        fi
    done
    
    # 检查主配置文件
    if [ -f /etc/sysctl.conf ]; then
        if grep -q "^net.ipv4.tcp_wmem\|^net.ipv4.tcp_rmem" /etc/sysctl.conf 2>/dev/null; then
            echo -e "${gl_huang}⚠️  发现 /etc/sysctl.conf 中有活动的 TCP 缓冲区配置${gl_bai}"
            conflicts_found=1
        fi
    fi
    
    if [ $conflicts_found -eq 0 ]; then
        echo -e "${gl_lv}✓ 未发现配置冲突${gl_bai}"
        return 0
    fi
    
    # 显示冲突文件
    if [ ${#conflict_files[@]} -gt 0 ]; then
        echo -e "${gl_huang}发现以下可能冲突的配置文件：${gl_bai}"
        for file in "${conflict_files[@]}"; do
            echo "  - $file"
            grep "tcp_wmem\|tcp_rmem" "$file" | head -2 | sed 's/^/    /'
        done
        echo ""
    fi
    
    read -e -p "$(echo -e "${gl_huang}是否自动清理冲突配置？(Y/N): ${gl_bai}")" clean_choice
    
    case "$clean_choice" in
        [Yy])
            # 注释掉 /etc/sysctl.conf 中的配置
            if [ -f /etc/sysctl.conf ]; then
                sed -i.bak '/^net.ipv4.tcp_wmem/s/^/# /' /etc/sysctl.conf 2>/dev/null
                sed -i.bak '/^net.ipv4.tcp_rmem/s/^/# /' /etc/sysctl.conf 2>/dev/null
                sed -i.bak '/^net.core.rmem_max/s/^/# /' /etc/sysctl.conf 2>/dev/null
                sed -i.bak '/^net.core.wmem_max/s/^/# /' /etc/sysctl.conf 2>/dev/null
                echo -e "${gl_lv}✓ 已注释 /etc/sysctl.conf 中的冲突配置${gl_bai}"
            fi
            
            # 备份并删除冲突的配置文件
            for file in "${conflict_files[@]}"; do
                if [ -f "$file" ]; then
                    mv "$file" "${file}.disabled.$(date +%Y%m%d_%H%M%S)"
                    echo -e "${gl_lv}✓ 已禁用: $(basename $file)${gl_bai}"
                fi
            done
            
            echo -e "${gl_lv}✓ 冲突清理完成${gl_bai}"
            return 0
            ;;
        *)
            echo -e "${gl_huang}已跳过清理，配置可能不会完全生效${gl_bai}"
            return 1
            ;;
    esac
}

# 验证配置是否真正生效
verify_current_config() {
    echo -e "${gl_kjlan}=== 当前配置验证 ===${gl_bai}"
    
    local actual_wmem=$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null | awk '{print $3}')
    local actual_rmem=$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null | awk '{print $3}')
    local actual_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local actual_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    
    echo "拥塞控制: $actual_cc"
    echo "队列算法: $actual_qdisc"
    echo "TCP wmem 上限: $(echo "scale=2; $actual_wmem / 1048576" | bc 2>/dev/null || echo "$(($actual_wmem / 1048576))")MB"
    echo "TCP rmem 上限: $(echo "scale=2; $actual_rmem / 1048576" | bc 2>/dev/null || echo "$(($actual_rmem / 1048576))")MB"
    
    # 检查是否符合预期
    local expected_values="16777216 33554432 8388608"
    local config_ok=0
    
    for val in $expected_values; do
        if [ "$actual_wmem" = "$val" ] || [ "$actual_rmem" = "$val" ]; then
            config_ok=1
            break
        fi
    done
    
    echo ""
    if [ "$actual_cc" = "bbr" ] && [ "$actual_qdisc" = "fq" ] && [ $config_ok -eq 1 ]; then
        echo -e "${gl_lv}✅ 配置正常${gl_bai}"
        return 0
    else
        echo -e "${gl_huang}⚠️  配置可能未完全生效，建议运行配置检查${gl_bai}"
        return 1
    fi
}

# 获取符合条件的网卡（排除虚拟网卡）
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
    if ! command -v tc &>/dev/null; then
        echo -e "${gl_huang}警告: ${gl_bai}未检测到 tc 命令（iproute2），建议安装: apt install -y iproute2"
        return 1
    fi
    
    echo "正在对网卡应用 fq 队列算法..."
    local count=0
    for dev in $(eligible_ifaces); do
        if tc qdisc replace dev "$dev" root fq 2>/dev/null; then
            echo "  - $dev: ${gl_lv}✓${gl_bai}"
            count=$((count + 1))
        fi
    done
    
    if [ $count -gt 0 ]; then
        echo -e "${gl_lv}已对 $count 个网卡应用 fq（立即生效，无需重启）${gl_bai}"
        return 0
    else
        echo -e "${gl_huang}未找到有效网卡${gl_bai}"
        return 1
    fi
}

# fq maxrate 单连接限速（智能计算版本）
set_fq_maxrate() {
    local rate=$1  # e.g. 280mbit / 500mbit / off
    
    if ! command -v tc &>/dev/null; then
        echo -e "${gl_huang}警告: ${gl_bai}未检测到 tc 命令"
        return 1
    fi
    
    if [ "$rate" = "off" ]; then
        echo "正在移除单连接限速..."
        for dev in $(eligible_ifaces); do
            tc qdisc replace dev "$dev" root fq 2>/dev/null
        done
        echo -e "${gl_lv}已移除 maxrate，恢复默认 fq pacing${gl_bai}"
    else
        echo "正在设置单连接上限: $rate ..."
        for dev in $(eligible_ifaces); do
            tc qdisc replace dev "$dev" root fq maxrate "$rate" 2>/dev/null
        done
        echo -e "${gl_lv}已为 fq 设置单流上限: $rate${gl_bai}"
        echo -e "${gl_kjlan}提示: 此设置可防止单连接占满带宽，适合多用户场景${gl_bai}"
    fi
}

# 智能限速：根据目标有效带宽计算实际 maxrate
set_fq_maxrate_smart() {
    if ! command -v tc &>/dev/null; then
        echo -e "${gl_huang}警告: ${gl_bai}未检测到 tc 命令"
        return 1
    fi
    
    echo -e "${gl_kjlan}=== 智能限速配置 ===${gl_bai}"
    echo ""
    echo "说明："
    echo "  - 目标带宽：实际可用的 TCP 传输速度（扣除重传、协议开销）"
    echo "  - 实际设置：会自动放大 30-40%，补偿重传和开销"
    echo ""
    echo "常见场景推荐："
    echo "  • 联通 9929（300M 瓶颈）：目标 250 Mbps"
    echo "  • 电信 CN2（500M 瓶颈）：目标 450 Mbps"
    echo "  • 移动 CMI（1000M）：目标 900 Mbps"
    echo ""
    
    read -e -p "请输入目标有效带宽（数字，单位 Mbps）: " target_mbps
    
    # 验证输入
    if ! [[ "$target_mbps" =~ ^[0-9]+$ ]]; then
        echo -e "${gl_hong}错误: 请输入有效的数字${gl_bai}"
        return 1
    fi
    
    if [ "$target_mbps" -lt 10 ] || [ "$target_mbps" -gt 10000 ]; then
        echo -e "${gl_hong}错误: 带宽范围应在 10-10000 Mbps 之间${gl_bai}"
        return 1
    fi
    
    # 智能计算实际需要设置的 maxrate
    # 系数说明：
    # - 高丢包链路（9929 等）：1.40 倍（补偿 15-20% 重传 + 5% 协议开销 + 15% 余量）
    # - 中等链路（CN2 等）：1.30 倍（补偿 5-10% 重传 + 5% 协议开销 + 10% 余量）
    # - 优质链路（BGP 等）：1.20 倍（补偿 < 5% 重传 + 5% 协议开销 + 10% 余量）
    
    echo ""
    echo "请选择链路类型（影响补偿系数）："
    echo "1. 高丢包链路（联通 9929、部分 CN2 GT）- 补偿 40%"
    echo "2. 中等链路（CN2 GIA、部分直连）- 补偿 30%"
    echo "3. 优质链路（BGP、IPLC、IEPL）- 补偿 20%"
    echo "4. 自动检测（推荐）"
    read -e -p "选择（1-4）[默认 4]: " link_type
    
    # 默认值
    link_type=${link_type:-4}
    
    case "$link_type" in
        1)
            multiplier="1.40"
            link_desc="高丢包链路"
            ;;
        2)
            multiplier="1.30"
            link_desc="中等链路"
            ;;
        3)
            multiplier="1.20"
            link_desc="优质链路"
            ;;
        4)
            # 自动检测：尝试 ping 测试
            echo ""
            echo "正在自动检测链路质量..."
            read -e -p "请输入测试目标 IP（回车跳过自动检测）: " test_ip
            
            if [ -n "$test_ip" ] && command -v ping &>/dev/null; then
                loss=$(ping -c 20 -i 0.2 "$test_ip" 2>/dev/null | grep -oP '\d+(?=% packet loss)')
                if [ -n "$loss" ]; then
                    if [ "$loss" -ge 10 ]; then
                        multiplier="1.40"
                        link_desc="高丢包链路（检测到 ${loss}% 丢包）"
                    elif [ "$loss" -ge 5 ]; then
                        multiplier="1.30"
                        link_desc="中等链路（检测到 ${loss}% 丢包）"
                    else
                        multiplier="1.20"
                        link_desc="优质链路（检测到 ${loss}% 丢包）"
                    fi
                else
                    multiplier="1.35"
                    link_desc="中等链路（检测失败，使用默认值）"
                fi
            else
                multiplier="1.35"
                link_desc="中等链路（未检测，使用默认值）"
            fi
            ;;
        *)
            echo -e "${gl_hong}无效选择，使用默认值${gl_bai}"
            multiplier="1.35"
            link_desc="中等链路"
            ;;
    esac
    
    # 计算实际 maxrate
    actual_rate=$(echo "$target_mbps * $multiplier" | bc | awk '{print int($1+0.5)}')
    
    echo ""
    echo -e "${gl_kjlan}=== 计算结果 ===${gl_bai}"
    echo "链路类型: $link_desc"
    echo "补偿系数: ${multiplier}x"
    echo "目标有效带宽: ${target_mbps} Mbps"
    echo "实际设置 maxrate: ${actual_rate} Mbit"
    echo ""
    echo "预期效果："
    echo "  • TCP 理论带宽: 约 ${actual_rate} Mbps"
    echo "  • 扣除重传和开销后"
    echo "  • 实际有效带宽: 约 ${target_mbps} Mbps ✅"
    echo ""
    
    read -e -p "确认应用此配置？(Y/N): " confirm
    
    case "$confirm" in
        [Yy])
            echo "正在应用配置..."
            for dev in $(eligible_ifaces); do
                tc qdisc replace dev "$dev" root fq maxrate "${actual_rate}mbit" 2>/dev/null && \
                echo "  ✓ $dev: maxrate ${actual_rate}mbit"
            done
            echo ""
            echo -e "${gl_lv}✅ 智能限速配置完成${gl_bai}"
            echo -e "${gl_kjlan}提示: 建议运行网络测试验证实际效果${gl_bai}"
            ;;
        *)
            echo "已取消配置"
            return 1
            ;;
    esac
}

# MSS clamp 防分片
apply_mss_clamp() {
    local action=$1  # enable/disable
    
    if ! command -v iptables &>/dev/null; then
        echo -e "${gl_huang}警告: ${gl_bai}未检测到 iptables，跳过 MSS clamp"
        return 1
    fi
    
    if [ "$action" = "enable" ]; then
        # 检查规则是否已存在
        if iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu >/dev/null 2>&1; then
            echo -e "${gl_huang}MSS clamp 规则已存在${gl_bai}"
        else
            iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
            echo -e "${gl_lv}MSS clamp 已启用（FORWARD 链）${gl_bai}"
            echo -e "${gl_kjlan}提示: 此功能可防止跨运营商 TCP 分片，减少重传${gl_bai}"
        fi
    else
        if iptables -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu >/dev/null 2>&1; then
            echo -e "${gl_lv}MSS clamp 已关闭${gl_bai}"
        else
            echo -e "${gl_huang}MSS clamp 规则不存在或已删除${gl_bai}"
        fi
    fi
}

# 并发连接优化（limits + systemd）
tune_limits_and_systemd() {
    echo -e "${gl_kjlan}=== 配置并发连接优化 ===${gl_bai}"
    
    # 1. 配置 limits.conf
    if ! grep -q "soft nofile 1048576" /etc/security/limits.conf 2>/dev/null; then
        cat >> /etc/security/limits.conf <<'EOF'

# 高并发优化（BBR Ultimate Pro）
* soft nofile 1048576
* hard nofile 1048576
EOF
        echo "✓ 已写入 /etc/security/limits.conf"
    else
        echo "✓ limits.conf 已配置"
    fi
    
    # 2. 配置常见服务的 systemd 覆盖
    for service in realm xray v2ray hysteria tuic; do
        if systemctl list-unit-files | grep -q "^${service}.service"; then
            mkdir -p /etc/systemd/system/${service}.service.d
            cat > /etc/systemd/system/${service}.service.d/override.conf <<'EOF'
[Service]
LimitNOFILE=1048576
TasksMax=infinity
Restart=always
RestartSec=3
EOF
            echo "✓ 已配置 ${service}.service"
        fi
    done
    
    systemctl daemon-reload 2>/dev/null
    echo -e "${gl_lv}并发优化配置完成！${gl_bai}"
    echo -e "${gl_kjlan}提示: 需要重新登录或重启相关服务才能生效${gl_bai}"
}

#=============================================================================
# BBR 配置函数（改进版 - 确保配置生效）
#=============================================================================

bbr_configure() {
    local qdisc=$1
    local description=$2
    
    echo -e "${gl_kjlan}=== 配置 BBR v3 + ${qdisc} ===${gl_bai}"
    
    # 步骤 0：检查并清理冲突配置
    echo ""
    check_and_clean_conflicts
    echo ""
    
    # 步骤 1：清理冲突配置（保留原有逻辑作为双重保险）
    echo "正在检查配置冲突..."
    
    # 1.1 备份主配置文件（如果还没备份）
    if [ -f /etc/sysctl.conf ] && ! [ -f /etc/sysctl.conf.bak.original ]; then
        cp /etc/sysctl.conf /etc/sysctl.conf.bak.original
        echo "已备份: /etc/sysctl.conf -> /etc/sysctl.conf.bak.original"
    fi
    
    # 1.2 注释掉 /etc/sysctl.conf 中的 TCP 缓冲区配置（避免覆盖）
    if [ -f /etc/sysctl.conf ]; then
        sed -i '/^net.ipv4.tcp_wmem/s/^/# /' /etc/sysctl.conf 2>/dev/null
        sed -i '/^net.ipv4.tcp_rmem/s/^/# /' /etc/sysctl.conf 2>/dev/null
        sed -i '/^net.core.rmem_max/s/^/# /' /etc/sysctl.conf 2>/dev/null
        sed -i '/^net.core.wmem_max/s/^/# /' /etc/sysctl.conf 2>/dev/null
        echo "已清理 /etc/sysctl.conf 中的冲突配置"
    fi
    
    # 1.3 删除可能存在的软链接
    if [ -L /etc/sysctl.d/99-sysctl.conf ]; then
        rm -f /etc/sysctl.d/99-sysctl.conf
        echo "已删除配置软链接"
    fi
    
    # 步骤 2：创建独立配置文件
    echo "正在创建新配置..."
    cat > "$SYSCTL_CONF" << EOF
# BBR v3 Ultimate Configuration
# Generated on $(date)

# 队列调度算法
net.core.default_qdisc=${qdisc}

# 拥塞控制算法
net.ipv4.tcp_congestion_control=bbr

# TCP 缓冲区优化（16MB 上限，适合小内存 VPS）
net.core.rmem_default=262144
net.core.wmem_default=262144
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216

# UDP 优化（提高最低缓冲，避免突发丢包）
net.ipv4.udp_rmem_min=196608
net.ipv4.udp_wmem_min=196608
net.ipv4.udp_mem=32768 8388608 16777216

# 高级优化
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_mtu_probing=1
net.core.netdev_max_backlog=8192
net.ipv4.tcp_max_syn_backlog=4096
net.core.somaxconn=1024
EOF

    # 步骤 3：应用配置（只加载此配置文件）
    echo "正在应用配置..."
    sysctl -p "$SYSCTL_CONF" > /dev/null 2>&1
    
    # 步骤 3.5：立即应用 tc fq（无需重启）
    echo "正在应用队列算法到网卡..."
    apply_tc_fq_now > /dev/null 2>&1
    
    # 步骤 4：验证配置是否真正生效
    local actual_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    local actual_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local actual_wmem=$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null | awk '{print $3}')
    local actual_rmem=$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null | awk '{print $3}')
    
    echo ""
    echo -e "${gl_kjlan}=== 配置验证 ===${gl_bai}"
    
    # 验证队列算法
    if [ "$actual_qdisc" = "$qdisc" ]; then
        echo -e "队列算法: ${gl_lv}$actual_qdisc ✓${gl_bai}"
    else
        echo -e "队列算法: ${gl_huang}$actual_qdisc (期望: $qdisc) ⚠${gl_bai}"
    fi
    
    # 验证拥塞控制
    if [ "$actual_cc" = "bbr" ]; then
        echo -e "拥塞控制: ${gl_lv}$actual_cc ✓${gl_bai}"
    else
        echo -e "拥塞控制: ${gl_huang}$actual_cc (期望: bbr) ⚠${gl_bai}"
    fi
    
    # 验证发送缓冲区
    if [ "$actual_wmem" = "16777216" ]; then
        echo -e "发送缓冲区: ${gl_lv}16MB ✓${gl_bai}"
    else
        echo -e "发送缓冲区: ${gl_huang}$(echo "scale=2; $actual_wmem / 1048576" | bc)MB (期望: 16MB) ⚠${gl_bai}"
    fi
    
    # 验证接收缓冲区
    if [ "$actual_rmem" = "16777216" ]; then
        echo -e "接收缓冲区: ${gl_lv}16MB ✓${gl_bai}"
    else
        echo -e "接收缓冲区: ${gl_huang}$(echo "scale=2; $actual_rmem / 1048576" | bc)MB (期望: 16MB) ⚠${gl_bai}"
    fi
    
    echo ""
    
    # 最终判断
    if [ "$actual_qdisc" = "$qdisc" ] && [ "$actual_cc" = "bbr" ] && \
       [ "$actual_wmem" = "16777216" ] && [ "$actual_rmem" = "16777216" ]; then
        echo -e "${gl_lv}✅ BBR v3 + ${qdisc} 配置完成并已生效！${gl_bai}"
        echo -e "${gl_zi}优化说明: ${description}${gl_bai}"
    else
        echo -e "${gl_huang}⚠️ 配置已保存但部分参数未生效${gl_bai}"
        echo -e "${gl_huang}建议执行以下操作：${gl_bai}"
        echo "1. 检查是否有其他配置文件冲突"
        echo "2. 重启服务器使配置完全生效: reboot"
    fi
}

bbr_configure_2gb() {
    local qdisc=$1
    local description=$2
    
    echo -e "${gl_kjlan}=== 配置 BBR v3 + ${qdisc} (2GB+ 内存优化) ===${gl_bai}"
    
    # 步骤 0：检查并清理冲突配置
    echo ""
    check_and_clean_conflicts
    echo ""
    
    # 步骤 1：清理冲突配置（保留原有逻辑作为双重保险）
    echo "正在检查配置冲突..."
    
    # 1.1 备份主配置文件（如果还没备份）
    if [ -f /etc/sysctl.conf ] && ! [ -f /etc/sysctl.conf.bak.original ]; then
        cp /etc/sysctl.conf /etc/sysctl.conf.bak.original
        echo "已备份: /etc/sysctl.conf -> /etc/sysctl.conf.bak.original"
    fi
    
    # 1.2 注释掉 /etc/sysctl.conf 中的 TCP 缓冲区配置（避免覆盖）
    if [ -f /etc/sysctl.conf ]; then
        sed -i '/^net.ipv4.tcp_wmem/s/^/# /' /etc/sysctl.conf 2>/dev/null
        sed -i '/^net.ipv4.tcp_rmem/s/^/# /' /etc/sysctl.conf 2>/dev/null
        sed -i '/^net.core.rmem_max/s/^/# /' /etc/sysctl.conf 2>/dev/null
        sed -i '/^net.core.wmem_max/s/^/# /' /etc/sysctl.conf 2>/dev/null
        echo "已清理 /etc/sysctl.conf 中的冲突配置"
    fi
    
    # 1.3 删除可能存在的软链接
    if [ -L /etc/sysctl.d/99-sysctl.conf ]; then
        rm -f /etc/sysctl.d/99-sysctl.conf
        echo "已删除配置软链接"
    fi
    
    # 步骤 2：创建独立配置文件（2GB 内存版本）
    echo "正在创建新配置..."
    cat > "$SYSCTL_CONF" << EOF
# BBR v3 Ultimate Configuration (2GB+ Memory)
# Generated on $(date)

# 队列调度算法
net.core.default_qdisc=${qdisc}

# 拥塞控制算法
net.ipv4.tcp_congestion_control=bbr

# TCP 缓冲区优化（32MB 上限，256KB 默认值，适合 2GB+ 内存 VPS）
net.core.rmem_default=262144
net.core.wmem_default=262144
net.core.rmem_max=33554432
net.core.wmem_max=33554432
net.ipv4.tcp_rmem=4096 131072 33554432
net.ipv4.tcp_wmem=4096 131072 33554432

# UDP 优化（高性能场景）
net.ipv4.udp_rmem_min=262144
net.ipv4.udp_wmem_min=262144
net.ipv4.udp_mem=65536 16777216 33554432

# 高级优化（适合高带宽场景）
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_mtu_probing=1
net.core.netdev_max_backlog=16384
net.ipv4.tcp_max_syn_backlog=8192
net.core.somaxconn=1024
EOF

    # 步骤 3：应用配置（只加载此配置文件）
    echo "正在应用配置..."
    sysctl -p "$SYSCTL_CONF" > /dev/null 2>&1
    
    # 步骤 3.5：立即应用 tc fq（无需重启）
    echo "正在应用队列算法到网卡..."
    apply_tc_fq_now > /dev/null 2>&1
    
    # 步骤 4：验证配置是否真正生效
    local actual_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    local actual_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local actual_wmem=$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null | awk '{print $3}')
    local actual_rmem=$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null | awk '{print $3}')
    
    echo ""
    echo -e "${gl_kjlan}=== 配置验证 ===${gl_bai}"
    
    # 验证队列算法
    if [ "$actual_qdisc" = "$qdisc" ]; then
        echo -e "队列算法: ${gl_lv}$actual_qdisc ✓${gl_bai}"
    else
        echo -e "队列算法: ${gl_huang}$actual_qdisc (期望: $qdisc) ⚠${gl_bai}"
    fi
    
    # 验证拥塞控制
    if [ "$actual_cc" = "bbr" ]; then
        echo -e "拥塞控制: ${gl_lv}$actual_cc ✓${gl_bai}"
    else
        echo -e "拥塞控制: ${gl_huang}$actual_cc (期望: bbr) ⚠${gl_bai}"
    fi
    
    # 验证发送缓冲区
    if [ "$actual_wmem" = "33554432" ]; then
        echo -e "发送缓冲区: ${gl_lv}32MB ✓${gl_bai}"
    else
        echo -e "发送缓冲区: ${gl_huang}$(echo "scale=2; $actual_wmem / 1048576" | bc)MB (期望: 32MB) ⚠${gl_bai}"
    fi
    
    # 验证接收缓冲区
    if [ "$actual_rmem" = "33554432" ]; then
        echo -e "接收缓冲区: ${gl_lv}32MB ✓${gl_bai}"
    else
        echo -e "接收缓冲区: ${gl_huang}$(echo "scale=2; $actual_rmem / 1048576" | bc)MB (期望: 32MB) ⚠${gl_bai}"
    fi
    
    echo ""
    
    # 最终判断
    if [ "$actual_qdisc" = "$qdisc" ] && [ "$actual_cc" = "bbr" ] && \
       [ "$actual_wmem" = "33554432" ] && [ "$actual_rmem" = "33554432" ]; then
        echo -e "${gl_lv}✅ BBR v3 + ${qdisc} (2GB配置) 完成并已生效！${gl_bai}"
        echo -e "${gl_zi}优化说明: ${description}${gl_bai}"
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
# 详细状态显示
#=============================================================================

show_detailed_status() {
    clear
    echo -e "${gl_kjlan}=== 系统详细信息 ===${gl_bai}"
    echo ""
    
    echo "操作系统: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'=' -f2 | tr -d '"')"
    echo "内核版本: $(uname -r)"
    echo "CPU 架构: $(uname -m)"
    echo ""
    
    if command -v sysctl &>/dev/null; then
        echo "TCP 拥塞控制: $(sysctl -n net.ipv4.tcp_congestion_control)"
        echo "队列调度算法: $(sysctl -n net.core.default_qdisc)"
        echo ""
        
        echo "可用拥塞控制算法:"
        sysctl net.ipv4.tcp_available_congestion_control
        echo ""
        
        # BBR 模块信息
        if command -v modinfo &>/dev/null; then
            local bbr_info=$(modinfo tcp_bbr 2>/dev/null)
            if [ -n "$bbr_info" ]; then
                echo "BBR 模块详情:"
                echo "$bbr_info" | grep -E "version|description"
            fi
        fi
    fi
    
    echo ""
    if dpkg -l 2>/dev/null | grep -q 'linux-xanmod'; then
        echo -e "${gl_lv}XanMod 内核已安装${gl_bai}"
        dpkg -l | grep linux-xanmod | head -3
    else
        echo -e "${gl_huang}XanMod 内核未安装${gl_bai}"
    fi
    
    echo ""
    if [ -f "$SYSCTL_CONF" ]; then
        echo -e "${gl_lv}BBR 配置文件存在: $SYSCTL_CONF${gl_bai}"
        echo "配置内容:"
        cat "$SYSCTL_CONF"
    else
        echo -e "${gl_huang}BBR 配置文件不存在${gl_bai}"
    fi
    
    echo ""
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
    else
        echo "1. 安装 XanMod 内核 + BBR v3"
    fi
    
    echo ""
    echo -e "${gl_kjlan}[BBR 配置]${gl_bai}"
    echo "3. 快速启用 BBR + FQ（≤1GB 内存）+ UDP 优化"
    echo "4. 快速启用 BBR + FQ（2GB+ 内存）+ UDP 优化"
    echo ""
    echo -e "${gl_kjlan}[高级优化]${gl_bai}"
    echo "5. 立即应用 fq 到网卡（tc 命令，无需重启）"
    echo "6. 🔥 智能限速（输入目标带宽，自动补偿重传）"
    echo "7. 手动设置 fq 限速（需自行计算）"
    echo "8. 取消单连接限速"
    echo "9. 启用 MSS clamp（防 TCP 分片）"
    echo "10. 关闭 MSS clamp"
    echo "11. 并发连接优化（limits + systemd）"
    echo ""
    echo -e "${gl_kjlan}[系统工具]${gl_bai}"
    echo "12. 虚拟内存管理"
    echo ""
    echo -e "${gl_kjlan}[配置诊断]${gl_bai}"
    echo "13. 配置诊断和修复（检查冲突、验证配置）"
    echo ""
    echo -e "${gl_kjlan}[系统信息]${gl_bai}"
    echo "14. 查看详细状态"
    echo "15. 性能测试建议"
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
            fi
            ;;
        3)
            bbr_configure "fq" "通用场景优化（≤1GB 内存，16MB 缓冲区 + UDP 优化）"
            break_end
            ;;
        4)
            bbr_configure_2gb "fq" "通用场景优化（2GB+ 内存，32MB 缓冲区 + UDP 优化）"
            break_end
            ;;
        5)
            apply_tc_fq_now
            break_end
            ;;
        6)
            set_fq_maxrate_smart
            break_end
            ;;
        7)
            echo -e "${gl_kjlan}=== 手动设置单连接限速 ===${gl_bai}"
            echo "推荐值参考："
            echo "  - 300Mbps 专线：280mbit"
            echo "  - 500Mbps 专线：480mbit"
            echo "  - 1Gbps 专线：   900mbit"
            echo ""
            echo -e "${gl_huang}提示：此为手动模式，不会自动补偿重传${gl_bai}"
            echo -e "${gl_huang}      如需自动计算，请使用选项 6（智能限速）${gl_bai}"
            echo ""
            read -e -p "请输入限速值（如 280mbit）: " maxrate
            if [ -n "$maxrate" ]; then
                set_fq_maxrate "$maxrate"
            fi
            break_end
            ;;
        8)
            set_fq_maxrate off
            break_end
            ;;
        9)
            apply_mss_clamp enable
            break_end
            ;;
        10)
            apply_mss_clamp disable
            break_end
            ;;
        11)
            tune_limits_and_systemd
            break_end
            ;;
        12)
            manage_swap
            ;;
        13)
            clear
            echo -e "${gl_kjlan}=== BBR 配置诊断和修复 ===${gl_bai}"
            echo ""
            
            # 1. 检查冲突
            check_and_clean_conflicts
            echo ""
            
            # 2. 验证当前配置
            verify_current_config
            echo ""
            
            # 3. 检查 tc fq 状态
            echo -e "${gl_kjlan}=== 队列算法状态 ===${gl_bai}"
            if command -v tc &>/dev/null; then
                tc qdisc show | grep fq | head -3
                if [ $? -ne 0 ]; then
                    echo -e "${gl_huang}⚠️  网卡未应用 fq 队列算法${gl_bai}"
                    read -e -p "是否立即应用？(Y/N): " apply_fq
                    if [[ "$apply_fq" =~ ^[Yy]$ ]]; then
                        apply_tc_fq_now
                    fi
                else
                    echo -e "${gl_lv}✓ fq 队列算法已应用${gl_bai}"
                fi
            else
                echo -e "${gl_huang}⚠️  未安装 tc 命令${gl_bai}"
            fi
            echo ""
            
            # 4. 检查 MSS clamp 状态
            echo -e "${gl_kjlan}=== MSS Clamp 状态 ===${gl_bai}"
            if command -v iptables &>/dev/null; then
                if iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu >/dev/null 2>&1; then
                    echo -e "${gl_lv}✓ MSS clamp 已启用${gl_bai}"
                else
                    echo -e "${gl_huang}⚠️  MSS clamp 未启用${gl_bai}"
                fi
            fi
            echo ""
            
            # 5. 提供修复建议
            echo -e "${gl_kjlan}=== 修复建议 ===${gl_bai}"
            echo "如果发现配置异常，建议执行："
            echo "  • 重新运行 BBR 配置（菜单选项 3 或 4）"
            echo "  • 立即应用 fq（菜单选项 5）"
            echo "  • 启用 MSS clamp（菜单选项 8）"
            
            break_end
            ;;
        14)
            show_detailed_status
            ;;
        15)
            show_performance_test
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

show_performance_test() {
    clear
    echo -e "${gl_kjlan}=== 性能测试建议 ===${gl_bai}"
    echo ""
    echo "1. 验证 BBR v3 版本:"
    echo "   modinfo tcp_bbr | grep version"
    echo ""
    echo "2. 检查当前配置:"
    echo "   sysctl net.ipv4.tcp_congestion_control"
    echo "   sysctl net.core.default_qdisc"
    echo ""
    echo "3. 带宽测试:"
    echo "   wget -O /dev/null http://cachefly.cachefly.net/10gb.test"
    echo ""
    echo "4. 延迟测试:"
    echo "   ping -c 100 8.8.8.8"
    echo ""
    echo "5. iperf3 测试:"
    echo "   iperf3 -c speedtest.example.com"
    echo ""
    break_end
}

#=============================================================================
# 脚本入口
#=============================================================================

main() {
    check_root
    
    # 安装必要依赖（用于高级功能）
    local missing_tools=""
    command -v tc &>/dev/null || missing_tools="$missing_tools iproute2"
    command -v iptables &>/dev/null || missing_tools="$missing_tools iptables"
    command -v bc &>/dev/null || missing_tools="$missing_tools bc"
    
    if [ -n "$missing_tools" ]; then
        echo -e "${gl_huang}检测到缺少必要工具，正在安装...${gl_bai}"
        install_package $missing_tools > /dev/null 2>&1
    fi
    
    # 命令行参数支持
    if [ "$1" = "-i" ] || [ "$1" = "--install" ]; then
        install_xanmod_kernel
        if [ $? -eq 0 ]; then
            echo ""
            echo "安装完成后，请重启并运行以下命令配置 BBR:"
            echo "sudo $0 --configure"
        fi
        exit 0
    elif [ "$1" = "-c" ] || [ "$1" = "--configure" ]; then
        configure_bbr_qdisc
        exit 0
    fi
    
    # 交互式菜单
    while true; do
        show_main_menu
    done
}

# 执行主函数
main "$@"

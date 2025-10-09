#!/bin/bash
#=============================================================================
# BBR v3 终极优化脚本 - Realm 中转专用 Ultimate Edition
# 功能：
#   - 针对 realm 中转链路（入口联通 9929 300M、两端 G 口）定制 TCP/UDP 缓冲
#   - 提供两档 profile：入口 300M、中转/落地 千兆（含 UDP 水位）
#   - fq 立即生效的 tc 兜底、MSS clamp 一键配置、ulimit/systemd 优化
#   - XanMod 官方内核一键安装/更新/卸载、BBR v3 配置与校验
# 特点：安全性 + 性能 双优化（保守的中间值，充裕的上限）
# 版本：3.0 Ultimate Edition
#=============================================================================

set -o pipefail

# 颜色
gl_hong='\033[31m'
gl_lv='\033[32m'
gl_huang='\033[33m'
gl_bai='\033[0m'
gl_kjlan='\033[96m'
gl_zi='\033[35m'

# GitHub 代理（如有自建可改）
gh_proxy="https://"

# 配置文件路径
SYSCTL_CONF="/etc/sysctl.d/99-bbr-ultimate.conf"

#=============================================================================
# 工具函数
#=============================================================================
check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo -e "${gl_hong}错误:${gl_bai} 此脚本需要 root 权限！请用: sudo bash $0"
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
  # 仅支持 apt 系系
  if ! command -v apt &>/dev/null; then
    echo -e "${gl_hong}错误:${gl_bai} 当前系统非 Debian/Ubuntu，暂不支持。"
    exit 1
  fi
  export DEBIAN_FRONTEND=noninteractive
  apt update -y >/dev/null 2>&1
  apt install -y "$@" >/dev/null 2>&1
}

check_disk_space() {
  local required_gb=$1
  local required_space_mb=$((required_gb * 1024))
  local available_space_mb
  available_space_mb=$(df -m / | awk 'NR==2 {print $4}')
  if [ "$available_space_mb" -lt "$required_space_mb" ]; then
    echo -e "${gl_huang}警告:${gl_bai} 磁盘空间不足！"
    echo "当前可用: $((available_space_mb/1024))G | 最低需求: ${required_gb}G"
    read -e -p "是否继续？(Y/N): " c
    case "$c" in
      [Yy]) return 0 ;;
      *) exit 1 ;;
    esac
  fi
}

check_swap() {
  local swap_total
  swap_total=$(free -m | awk 'NR==3{print $2}')
  if [ "$swap_total" -eq 0 ]; then
    echo -e "${gl_huang}检测到无虚拟内存，创建 1G SWAP...${gl_bai}"
    (fallocate -l 1G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=1024) && \
    chmod 600 /swapfile && mkswap /swapfile >/dev/null 2>&1 && swapon /swapfile
    sed -i '/\/swapfile/d' /etc/fstab
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo -e "${gl_lv}SWAP 创建成功${gl_bai}"
  fi
}

add_swap() {
  local new_swap=$1  # MB
  echo -e "${gl_kjlan}=== 调整虚拟内存为 ${new_swap}MB ===${gl_bai}"
  # 安全做法：仅 swapoff 所有激活的 swap，不 wipefs 物理分区
  awk 'NR>1{print $1}' /proc/swaps | xargs -r -n1 swapoff 2>/dev/null
  swapoff /swapfile 2>/dev/null
  rm -f /swapfile

  echo "创建 /swapfile..."
  (fallocate -l ${new_swap}M /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=${new_swap})
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null 2>&1
  swapon /swapfile
  sed -i '/\/swapfile/d' /etc/fstab
  echo "/swapfile none swap sw 0 0" >> /etc/fstab

  # Alpine 兼容（若用）
  if [ -f /etc/alpine-release ]; then
    echo "nohup swapon /swapfile" > /etc/local.d/swap.start
    chmod +x /etc/local.d/swap.start
    rc-update add local 2>/dev/null
  fi
  echo -e "${gl_lv}SWAP 已调整为 ${new_swap}MB${gl_bai}"
}

calculate_optimal_swap() {
  local mem_total recommended_swap reason
  mem_total=$(free -m | awk 'NR==2{print $2}')
  echo -e "${gl_kjlan}=== 智能计算虚拟内存 ===${gl_bai}\n"
  echo -e "检测到物理内存: ${gl_huang}${mem_total}MB${gl_bai}\n"
  echo "计算过程："
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  if [ "$mem_total" -lt 512 ]; then
    recommended_swap=1024; reason="内存极小（<512MB）固定 1GB"
    echo "→ <512MB → 推荐 1GB"
  elif [ "$mem_total" -lt 1024 ]; then
    recommended_swap=$((mem_total*2)); reason="512MB-1GB → 2 倍内存"
    echo "→ 512MB-1GB → 2x → ${recommended_swap}MB"
  elif [ "$mem_total" -lt 2048 ]; then
    recommended_swap=$((mem_total*3/2)); reason="1-2GB → 1.5 倍"
    echo "→ 1-2GB → 1.5x → ${recommended_swap}MB"
  elif [ "$mem_total" -lt 4096 ]; then
    recommended_swap=$mem_total; reason="2-4GB → 1 倍"
    echo "→ 2-4GB → 1x → ${recommended_swap}MB"
  elif [ "$mem_total" -lt 8192 ]; then
    recommended_swap=4096; reason="4-8GB 固定 4GB"
    echo "→ 4-8GB → 固定 4GB"
  else
    recommended_swap=4096; reason="≥8GB 固定 4GB"
    echo "→ ≥8GB → 固定 4GB"
  fi
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo -e "\n${gl_lv}计算结果：${gl_bai}"
  echo -e "  物理内存:   ${gl_huang}${mem_total}MB${gl_bai}"
  echo -e "  推荐 SWAP:  ${gl_huang}${recommended_swap}MB${gl_bai}"
  echo -e "  总可用内存: ${gl_huang}$((mem_total + recommended_swap))MB${gl_bai}\n"
  echo -e "${gl_zi}推荐理由: ${reason}${gl_bai}\n"
  read -e -p "$(echo -e "${gl_huang}是否应用？(Y/N): ${gl_bai}")" confirm
  case "$confirm" in
    [Yy]) add_swap "$recommended_swap"; return 0 ;;
    *) echo "已取消"; sleep 1; return 1 ;;
  esac
}

server_reboot() {
  read -e -p "$(echo -e "${gl_huang}提示:${gl_bai} 现在重启服务器使配置生效吗？(Y/N): ")" r
  case "$r" in
    [Yy]) echo "正在重启..."; reboot ;;
    *) echo "已取消，请稍后手动执行: reboot" ;;
  esac
}

bytes_to_mb() {
  # $1: bytes
  awk -v v="$1" 'BEGIN{printf("%.2f", v/1048576)}'
}

#=============================================================================
# 即时生效/系统侧增强
#=============================================================================
eligible_ifaces() {
  # 列出应应用 qdisc 的网卡（排除 lo/docker/veth/桥/虚拟常见名）
  for d in /sys/class/net/*; do
    [ -e "$d" ] || continue
    dev=$(basename "$d")
    case "$dev" in
      lo|docker*|veth*|br-*|virbr*|zt*|tailscale*|wg*|tun*|tap* ) continue;;
    esac
    echo "$dev"
  done
}

apply_tc_fq_now() {
  if command -v tc >/dev/null 2>&1; then
    for dev in $(eligible_ifaces); do
      tc qdisc replace dev "$dev" root fq 2>/dev/null
    done
  fi
}

set_txqueuelen() {
  local qlen="$1"
  for dev in $(eligible_ifaces); do
    ip link set dev "$dev" txqueuelen "$qlen" 2>/dev/null
  done
}

apply_mss_clamp() {
  # $1: enable|disable
  if ! command -v iptables >/dev/null 2>&1; then
    echo -e "${gl_huang}未检测到 iptables，跳过 MSS clamp${gl_bai}"
    return 0
  fi
  if [ "$1" = "enable" ]; then
    iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu >/dev/null 2>&1 \
      || iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
    echo -e "${gl_lv}已启用 MSS clamp（FORWARD）${gl_bai}"
  else
    iptables -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu >/dev/null 2>&1
    echo -e "${gl_lv}已关闭 MSS clamp（FORWARD）${gl_bai}"
  fi
}

tune_limits_and_systemd() {
  # 文件句柄
  if ! grep -q "soft nofile 1048576" /etc/security/limits.conf 2>/dev/null; then
    cat >> /etc/security/limits.conf <<EOF

# realm/vless 并发优化
* soft nofile 1048576
* hard nofile 1048576
EOF
  fi
  # systemd drop-in for realm.service
  mkdir -p /etc/systemd/system/realm.service.d
  cat > /etc/systemd/system/realm.service.d/override.conf <<'EOF'
[Service]
LimitNOFILE=1048576
TasksMax=infinity
Restart=always
RestartSec=3
# I/O 调度（在部分 VPS 下略有帮助）
IOSchedulingClass=best-effort
IOSchedulingPriority=4
EOF
  systemctl daemon-reload 2>/dev/null
  # 不强制重启 realm，由你决定
  echo -e "${gl_lv}已写入 limits 与 systemd realm 覆盖（如有 realm.service）${gl_bai}"
}

#=============================================================================
# BBR 配置/校验
#=============================================================================
write_and_apply_sysctl() {
  # $1: heredoc 内容（完整 sysctl）
  cat > "$SYSCTL_CONF" <<EOF
# BBR v3 Ultimate Configuration
# Generated on $(date)
$1
EOF
  sysctl -p "$SYSCTL_CONF" >/dev/null 2>&1
}

verify_bbr_applied() {
  # $1: 期望 qdisc；$2: 期望 tcp max（第三个数，字节）；$3: 期望 rmem max（第三个数，字节）
  local qdisc_expected="$1"
  local wmax_expected="$2"
  local rmax_expected="$3"

  local actual_qdisc actual_cc actual_wmax actual_rmax
  actual_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
  actual_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
  actual_wmax=$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null | awk '{print $3}')
  actual_rmax=$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null | awk '{print $3}')

  echo -e "\n${gl_kjlan}=== 配置验证 ===${gl_bai}"
  if [ "$actual_qdisc" = "$qdisc_expected" ]; then
    echo -e "队列算法: ${gl_lv}$actual_qdisc ✓${gl_bai}"
  else
    echo -e "队列算法: ${gl_huang}${actual_qdisc} (期望: ${qdisc_expected}) ⚠${gl_bai}"
  fi

  if [ "$actual_cc" = "bbr" ]; then
    echo -e "拥塞控制: ${gl_lv}$actual_cc ✓${gl_bai}"
  else
    echo -e "拥塞控制: ${gl_huang}${actual_cc} (期望: bbr) ⚠${gl_bai}"
  fi

  if [ "$actual_wmax" = "$wmax_expected" ]; then
    echo -e "发送缓冲上限: ${gl_lv}$(bytes_to_mb "$actual_wmax")MB ✓${gl_bai}"
  else
    echo -e "发送缓冲上限: ${gl_huang}$(bytes_to_mb "$actual_wmax")MB (期望: $(bytes_to_mb "$wmax_expected")MB) ⚠${gl_bai}"
  fi

  if [ "$actual_rmax" = "$rmax_expected" ]; then
    echo -e "接收缓冲上限: ${gl_lv}$(bytes_to_mb "$actual_rmax")MB ✓${gl_bai}"
  else
    echo -e "接收缓冲上限: ${gl_huang}$(bytes_to_mb "$actual_rmax")MB (期望: $(bytes_to_mb "$rmax_expected")MB) ⚠${gl_bai}"
  fi
  echo ""
}

apply_profile_realm_entry_300m() {
  echo -e "${gl_kjlan}=== 应用 Realm 入口（9929 300M）配置 ===${gl_bai}"
  write_and_apply_sysctl "$(cat <<'CONF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# TCP：中间值保守，上限 8MB（300M×~200ms≈7.5MB）
net.core.rmem_default=262144
net.core.wmem_default=262144
net.core.rmem_max=8388608
net.core.wmem_max=8388608
net.ipv4.tcp_rmem=4096 65536 8388608
net.ipv4.tcp_wmem=4096 65536 8388608

# UDP：最低值抬高，避免突发丢包；上限适度
net.ipv4.udp_rmem_min=196608
net.ipv4.udp_wmem_min=196608
net.ipv4.udp_mem=32768 8388608 12582912

# 常规稳态
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_mtu_probing=1

# 并发承载
net.core.netdev_max_backlog=8192
net.ipv4.tcp_max_syn_backlog=4096
net.core.somaxconn=1024
CONF
)"
  apply_tc_fq_now
  verify_bbr_applied "fq" "8388608" "8388608"
  echo -e "${gl_zi}可选：如需限制单连接上限≈280M，执行： tc qdisc replace dev <网卡> root fq maxrate 280mbit${gl_bai}"
}

apply_profile_realm_gigabit() {
  echo -e "${gl_kjlan}=== 应用 Realm 中转/落地（千兆）配置 ===${gl_bai}"
  write_and_apply_sysctl "$(cat <<'CONF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# TCP：上限 32MB（1G×~250ms≈31MB），中间值 128KB 折中
net.core.rmem_default=262144
net.core.wmem_default=262144
net.core.rmem_max=33554432
net.core.wmem_max=33554432
net.ipv4.tcp_rmem=4096 131072 33554432
net.ipv4.tcp_wmem=4096 131072 33554432

# UDP：更充裕的水位，突发更稳（单位：页）
net.ipv4.udp_rmem_min=262144
net.ipv4.udp_wmem_min=262144
net.ipv4.udp_mem=65536 16777216 25165824

# 常规稳态
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_mtu_probing=1

# 并发承载
net.core.netdev_max_backlog=16384
net.ipv4.tcp_max_syn_backlog=8192
net.core.somaxconn=1024
CONF
)"
  apply_tc_fq_now
  verify_bbr_applied "fq" "33554432" "33554432"
}

apply_profile_lowmem() {
  echo -e "${gl_kjlan}=== 应用 ≤1GB 内存（节省内存）配置 ===${gl_bai}"
  write_and_apply_sysctl "$(cat <<'CONF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# 更保守：上限 8MB、中间值小，避免内存抖动
net.core.rmem_default=262144
net.core.wmem_default=262144
net.core.rmem_max=8388608
net.core.wmem_max=8388608
net.ipv4.tcp_rmem=4096 65536 8388608
net.ipv4.tcp_wmem=4096 65536 8388608

# UDP：适度
net.ipv4.udp_rmem_min=196608
net.ipv4.udp_wmem_min=196608
net.ipv4.udp_mem=32768 8388608 12582912

net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_mtu_probing=1
net.core.netdev_max_backlog=8192
net.ipv4.tcp_max_syn_backlog=4096
net.core.somaxconn=1024
CONF
)"
  apply_tc_fq_now
  verify_bbr_applied "fq" "8388608" "8388608"
}

apply_profile_2gbplus() {
  echo -e "${gl_kjlan}=== 应用 2GB+ 内存（通用）配置 ===${gl_bai}"
  write_and_apply_sysctl "$(cat <<'CONF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# 上限 32MB，中间值 128KB
net.core.rmem_default=262144
net.core.wmem_default=262144
net.core.rmem_max=33554432
net.core.wmem_max=33554432
net.ipv4.tcp_rmem=4096 131072 33554432
net.ipv4.tcp_wmem=4096 131072 33554432

net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_mtu_probing=1
net.core.netdev_max_backlog=16384
net.ipv4.tcp_max_syn_backlog=8192
net.core.somaxconn=1024
CONF
)"
  apply_tc_fq_now
  verify_bbr_applied "fq" "33554432" "33554432"
}

# 状态/信息
check_bbr_status() {
  echo -e "${gl_kjlan}=== 当前系统状态 ===${gl_bai}"
  echo "内核版本: $(uname -r)"
  if command -v sysctl &>/dev/null; then
    local cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")
    local qd=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "未知")
    echo "拥塞控制算法: $cc"
    echo "队列调度算法: $qd"
    echo "可用拥塞算法: $(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null)"
    if command -v modinfo &>/dev/null; then
      local descr=$(modinfo tcp_bbr 2>/dev/null | sed -n 's/^description:\s*//p' | head -n1)
      [ -n "$descr" ] && echo "BBR 模块描述: $descr"
    fi
  fi
  if dpkg -l 2>/dev/null | grep -q 'linux-.*xanmod'; then
    echo -e "XanMod 内核: ${gl_lv}已安装 ✓${gl_bai}"
  else
    echo -e "XanMod 内核: ${gl_huang}未安装${gl_bai}"
  fi
}

show_detailed_status() {
  clear
  echo -e "${gl_kjlan}=== 系统详细信息 ===${gl_bai}\n"
  grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' | sed 's/^/操作系统: /'
  echo "内核版本: $(uname -r)"
  echo "CPU 架构: $(uname -m)"
  echo ""
  if command -v sysctl &>/dev/null; then
    echo "TCP 拥塞控制: $(sysctl -n net.ipv4.tcp_congestion_control)"
    echo "队列调度算法: $(sysctl -n net.core.default_qdisc)"
    echo "可用拥塞算法: $(sysctl -n net.ipv4.tcp_available_congestion_control)"
    echo ""
    if command -v modinfo &>/dev/null; then
      local binfo=$(modinfo tcp_bbr 2>/dev/null | grep -E "version|description")
      [ -n "$binfo" ] && { echo "BBR 模块信息:"; echo "$binfo"; }
    fi
  fi
  echo ""
  if dpkg -l 2>/dev/null | grep -q 'linux-.*xanmod'; then
    echo -e "${gl_lv}XanMod 内核包:${gl_bai}"
    dpkg -l | grep 'linux-.*xanmod' | head -5
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

show_performance_test() {
  clear
  echo -e "${gl_kjlan}=== 性能测试建议 ===${gl_bai}\n"
  echo "1) 验证 BBR："
  echo "   sysctl -n net.ipv4.tcp_congestion_control"
  echo "   sysctl -n net.core.default_qdisc"
  echo ""
  echo "2) 带宽大文件拉流："
  echo "   wget -O /dev/null http://cachefly.cachefly.net/10gb.test"
  echo ""
  echo "3) 延迟基准："
  echo "   ping -c 100 8.8.8.8"
  echo ""
  echo "4) iperf3（示例）："
  echo "   iperf3 -c speedtest.example.com"
  echo ""
  break_end
}

#=============================================================================
# XanMod 内核安装/更新/卸载
#=============================================================================
install_xanmod_kernel() {
  clear
  echo -e "${gl_kjlan}=== 安装 XanMod 内核与 BBR v3 ===${gl_bai}"
  echo -e "${gl_huang}警告:${gl_bai} 将升级 Linux 内核，请先备份。"
  read -e -p "继续？(Y/N): " c
  case "$c" in
    [Yy]) ;;
    *) echo "已取消"; return 1 ;;
  esac

  local arch=$(uname -m)
  # ARM64 走专用脚本
  if [ "$arch" = "aarch64" ]; then
    echo -e "${gl_kjlan}ARM64 架构，使用专用安装脚本${gl_bai}"
    bash <(curl -sL jhb.ovh/jb/bbrv3arm.sh)
    return $?
  fi

  # OS 检测
  if [ -r /etc/os-release ]; then
    . /etc/os-release
    if [ "$ID" != "debian" ] && [ "$ID" != "ubuntu" ]; then
      echo -e "${gl_hong}错误:${gl_bai} 仅支持 Debian/Ubuntu"
      return 1
    fi
  else
    echo -e "${gl_hong}错误:${gl_bai} 无法识别系统"
    return 1
  fi

  check_disk_space 3
  check_swap
  install_package wget gnupg curl ca-certificates

  echo "添加 XanMod GPG 密钥..."
  wget -qO - ${gh_proxy}raw.githubusercontent.com/kejilion/sh/main/archive.key | \
    gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg --yes 2>/dev/null \
    || wget -qO - https://dl.xanmod.org/archive.key | \
       gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg --yes 2>/dev/null

  echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' \
    > /etc/apt/sources.list.d/xanmod-release.list

  echo "检测 CPU 最优内核变体..."
  local version
  wget -q ${gh_proxy}raw.githubusercontent.com/kejilion/sh/main/check_x86-64_psabi.sh -O /tmp/check_x86-64_psabi.sh
  chmod +x /tmp/check_x86-64_psabi.sh
  version=$(/tmp/check_x86-64_psabi.sh | grep -oP 'x86-64-v\K\d+|x86-64-v\d+')
  [ -z "$version" ] && version="3"

  echo -e "${gl_lv}将安装: linux-xanmod-x64v${version}${gl_bai}"
  apt update -y
  if ! apt install -y linux-xanmod-x64v$version; then
    echo -e "${gl_hong}内核安装失败${gl_bai}"
    rm -f /etc/apt/sources.list.d/xanmod-release.list /tmp/check_x86-64_psabi.sh
    return 1
  fi
  rm -f /tmp/check_x86-64_psabi.sh
  echo -e "${gl_lv}XanMod 内核安装成功！请重启后再配置 BBR${gl_bai}"
  return 0
}

update_xanmod_kernel() {
  clear
  echo -e "${gl_kjlan}=== 更新 XanMod 内核 ===${gl_bai}\n"
  echo "当前内核: $(uname -r)"
  local arch=$(uname -m)
  if [ "$arch" = "aarch64" ]; then
    echo -e "${gl_huang}ARM64 暂不提供自动更新，建议重新安装${gl_bai}"
    break_end; return 1
  fi

  if [ ! -f /etc/apt/sources.list.d/xanmod-release.list ]; then
    echo "添加 XanMod 仓库..."
    wget -qO - ${gh_proxy}raw.githubusercontent.com/kejilion/sh/main/archive.key | \
      gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg --yes 2>/dev/null \
      || wget -qO - https://dl.xanmod.org/archive.key | \
         gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg --yes 2>/dev/null
    echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' \
      > /etc/apt/sources.list.d/xanmod-release.list
  fi

  apt update -y >/dev/null 2>&1
  local installed_packages
  installed_packages=$(dpkg -l | grep 'linux-.*xanmod' | awk '{print $2}')
  if [ -z "$installed_packages" ]; then
    echo -e "${gl_hong}未检测到已安装的 XanMod 内核${gl_bai}"
    break_end; return 1
  fi

  local upgradable
  upgradable=$(apt list --upgradable 2>/dev/null | grep xanmod)
  if [ -z "$upgradable" ]; then
    echo -e "${gl_lv}当前已是最新版本${gl_bai}"
    break_end; return 0
  fi

  echo -e "${gl_huang}发现可更新:${gl_bai}\n${upgradable}\n"
  read -e -p "确定更新？(Y/N): " c
  if [[ "$c" =~ ^[Yy]$ ]]; then
    apt install --only-upgrade -y $(echo "$installed_packages" | tr '\n' ' ')
    echo -e "${gl_lv}更新成功，请重启以加载新内核${gl_bai}"
    return 0
  else
    echo "已取消"
    break_end; return 1
  fi
}

uninstall_xanmod() {
  echo -e "${gl_huang}警告:${gl_bai} 即将卸载 XanMod 内核"
  read -e -p "确定继续？(Y/N): " c
  if [[ "$c" =~ ^[Yy]$ ]]; then
    apt purge -y 'linux-*xanmod*'
    update-grub
    rm -f "$SYSCTL_CONF"
    echo -e "${gl_lv}XanMod 内核已卸载${gl_bai}"
    server_reboot
  else
    echo "已取消"
  fi
}

#=============================================================================
# 主菜单 & 入口参数
#=============================================================================
show_main_menu() {
  clear
  check_bbr_status
  echo ""
  echo -e "${gl_zi}╔════════════════════════════════════════════╗${gl_bai}"
  echo -e "${gl_zi}║   BBR v3 终极优化 - Realm 中转专用         ║${gl_bai}"
  echo -e "${gl_zi}╚════════════════════════════════════════════╝${gl_bai}\n"

  echo -e "${gl_kjlan}[内核管理]${gl_bai}"
  echo "1. 安装 XanMod 内核 + BBR v3"
  echo "2. 更新 XanMod 内核"
  echo "3. 卸载 XanMod 内核"
  echo ""
  echo -e "${gl_kjlan}[BBR/网络配置]${gl_bai}"
  echo "4. 应用 Realm 入口（9929 300M）配置"
  echo "5. 应用 Realm 中转/落地（千兆）配置"
  echo "6. 应用 ≤1GB 内存（节省内存）配置"
  echo "7. 应用 2GB+ 内存（通用）配置"
  echo "8. 立即应用 fq（tc 兜底）"
  echo ""
  echo -e "${gl_kjlan}[系统工具]${gl_bai}"
  echo "9.  虚拟内存管理"
  echo "10. 写入文件句柄 & systemd realm 覆盖"
  echo "11. 启用 MSS clamp（FORWARD）"
  echo "12. 关闭 MSS clamp（FORWARD）"
  echo "13. 设置网卡 txqueuelen=2000（若支持）"
  echo ""
  echo -e "${gl_kjlan}[系统信息]${gl_bai}"
  echo "14. 查看详细状态"
  echo "15. 性能测试建议"
  echo ""
  echo "0. 退出脚本"
  echo "------------------------------------------------"
  read -e -p "请输入选择: " choice
  case "$choice" in
    1) install_xanmod_kernel; [ $? -eq 0 ] && server_reboot ;;
    2) update_xanmod_kernel; [ $? -eq 0 ] && server_reboot ;;
    3) uninstall_xanmod ;;
    4) apply_profile_realm_entry_300m; break_end ;;
    5) apply_profile_realm_gigabit; break_end ;;
    6) apply_profile_lowmem; break_end ;;
    7) apply_profile_2gbplus; break_end ;;
    8) apply_tc_fq_now; echo -e "${gl_lv}已对网卡应用 fq${gl_bai}"; break_end ;;
    9) manage_swap ;;
    10) tune_limits_and_systemd; break_end ;;
    11) apply_mss_clamp enable; break_end ;;
    12) apply_mss_clamp disable; break_end ;;
    13) set_txqueuelen 2000; echo -e "${gl_lv}已尝试设置 txqueuelen=2000${gl_bai}"; break_end ;;
    14) show_detailed_status ;;
    15) show_performance_test ;;
    0) echo "退出脚本"; exit 0 ;;
    *) echo "无效选择"; sleep 1 ;;
  esac
}

manage_swap() {
  while true; do
    clear
    echo -e "${gl_kjlan}=== 虚拟内存管理 ===${gl_bai}"
    local mem_total swap_used swap_total swap_info
    mem_total=$(free -m | awk 'NR==2{print $2}')
    swap_used=$(free -m | awk 'NR==3{print $3}')
    swap_total=$(free -m | awk 'NR==3{print $2}')
    swap_info=$(free -m | awk 'NR==3{u=$3;t=$2;p=(t==0?0:int(u*100/t)); printf "%dM/%dM (%d%%)", u,t,p}')
    echo -e "物理内存:     ${gl_huang}${mem_total}MB${gl_bai}"
    echo -e "当前虚拟内存: ${gl_huang}$swap_info${gl_bai}"
    echo "------------------------------------------------"
    echo "1. 分配 1024M (1GB)"
    echo "2. 分配 2048M (2GB)"
    echo "3. 分配 4096M (4GB)"
    echo "4. 智能计算推荐值"
    echo "0. 返回主菜单"
    echo "------------------------------------------------"
    read -e -p "请输入选择: " c
    case "$c" in
      1) add_swap 1024; break_end ;;
      2) add_swap 2048; break_end ;;
      3) add_swap 4096; break_end ;;
      4) calculate_optimal_swap; [ $? -eq 0 ] && break_end ;;
      0) return ;;
      *) echo "无效选择"; sleep 1 ;;
    esac
  done
}

# 命令行参数支持：
#   --install / -i                 安装 XanMod
#   --configure / -c [profile]     应用指定配置（entry300m|relay1g|lowmem|2gbplus）
#   --mss [on|off]                 开/关 MSS clamp
#   --fq-now                       立即对网卡应用 fq
main() {
  check_root
  # 基础依赖（tc/iptables 等）
  install_package iproute2 iptables

  case "$1" in
    -i|--install)
      install_xanmod_kernel
      [ $? -eq 0 ] && echo -e "\n重启后可执行：sudo bash $0 --configure relay1g（或 entry300m）"
      exit 0
      ;;
    -c|--configure)
      prof="$2"
      case "$prof" in
        entry300m) apply_profile_realm_entry_300m ;;
        relay1g|relay|gigabit) apply_profile_realm_gigabit ;;
        lowmem) apply_profile_lowmem ;;
        2gbplus|2g|plus) apply_profile_2gbplus ;;
        "" )
          # 未指定则按内存自动
          mem_total=$(free -m | awk 'NR==2{print $2}')
          if [ "$mem_total" -lt 2048 ]; then
            apply_profile_lowmem
          else
            apply_profile_2gbplus
          fi
          ;;
        * ) echo "未知 profile: $prof"; exit 1 ;;
      esac
      exit 0
      ;;
    --mss)
      case "$2" in
        on) apply_mss_clamp enable ;;
        off) apply_mss_clamp disable ;;
        * ) echo "用法: --mss on|off"; exit 1 ;;
      esac
      exit 0
      ;;
    --fq-now)
      apply_tc_fq_now
      echo "已应用 fq"
      exit 0
      ;;
  esac

  # 交互式菜单
  while true; do
    show_main_menu
  done
}

main "$@"
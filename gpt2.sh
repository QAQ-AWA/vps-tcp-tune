#!/bin/bash
#=============================================================================
# Realm 中转机 300M 瓶颈专用优化脚本（精简版）
# 适用：只在中转/落地机执行；入口上游为 9929 且总瓶颈约 300Mbps
# 功能：
#   - BBR v3 + fq；TCP/UDP 缓冲为“300M 跨洋友好型”（上限够用，中间值保守）
#   - tc 兜底：让 fq 立刻生效（无需重启）
#   - 一键 MSS clamp（可开可关）
#   - 并发保护：文件句柄上限 + systemd 覆盖（realm.service）
#   - 可选：单连接 maxrate≈280M（避免单流顶满；默认不启用）
# 版本：relay-300m-ultimate-1.0
#=============================================================================

set -o pipefail

# 颜色
cR='\033[31m'; cG='\033[32m'; cY='\033[33m'; c0='\033[0m'; cC='\033[96m'; cM='\033[35m'

SYSCTL_CONF="/etc/sysctl.d/99-bbr-realm-300m.conf"

need_root() {
  if [ "$EUID" -ne 0 ]; then
    echo -e "${cR}需要 root 权限${c0}，请使用：sudo bash $0"; exit 1
  fi
}

press_any() {
  echo -e "${cG}操作完成${c0}"
  echo "按任意键继续..."
  read -n 1 -s -r -p ""; echo ""
}

#------------------------------------------
# 基础：立即对所有有效网卡应用 fq
#------------------------------------------
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

apply_tc_fq_now() {
  if ! command -v tc >/dev/null 2>&1; then
    echo -e "${cY}未检测到 tc（iproute2），建议安装：apt install -y iproute2${c0}"
    return 0
  fi
  for dev in $(eligible_ifaces); do
    tc qdisc replace dev "$dev" root fq 2>/dev/null
  done
  echo -e "${cG}已对网卡应用 fq（即时生效）${c0}"
}

#------------------------------------------
# 可选：单连接 maxrate（温和限流）
#------------------------------------------
set_fq_maxrate() {
  # $1: e.g. 280mbit / off
  if ! command -v tc >/dev/null 2>&1; then
    echo -e "${cY}未检测到 tc，跳过${c0}"; return 0
  fi
  if [ "$1" = "off" ]; then
    for dev in $(eligible_ifaces); do
      tc qdisc replace dev "$dev" root fq 2>/dev/null
    done
    echo -e "${cG}已移除 maxrate，保持 fq 默认 pacing${c0}"
  else
    for dev in $(eligible_ifaces); do
      tc qdisc replace dev "$dev" root fq maxrate "$1" 2>/dev/null
    done
    echo -e "${cG}已为 fq 设置单流上限：${1}${c0}"
  fi
}

#------------------------------------------
# MSS clamp：防分片
#------------------------------------------
mss_clamp() {
  # $1: on/off
  if ! command -v iptables >/dev/null 2>&1; then
    echo -e "${cY}未检测到 iptables，跳过 MSS clamp${c0}"
    return 0
  fi
  if [ "$1" = "on" ]; then
    iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu >/dev/null 2>&1 \
      || iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
    echo -e "${cG}MSS clamp 已启用（FORWARD）${c0}"
  else
    iptables -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu >/dev/null 2>&1 \
      && echo -e "${cG}MSS clamp 已关闭（FORWARD）${c0}" || echo -e "${cY}MSS clamp 规则不存在或已删除${c0}"
  fi
}

#------------------------------------------
# limits + systemd 覆盖（realm.service）
#------------------------------------------
tune_limits_systemd() {
  if ! grep -q "soft nofile 1048576" /etc/security/limits.conf 2>/dev/null; then
    cat >> /etc/security/limits.conf <<'EOF'

# realm 并发优化
* soft nofile 1048576
* hard nofile 1048576
EOF
  fi
  mkdir -p /etc/systemd/system/realm.service.d
  cat > /etc/systemd/system/realm.service.d/override.conf <<'EOF'
[Service]
LimitNOFILE=1048576
TasksMax=infinity
Restart=always
RestartSec=3
IOSchedulingClass=best-effort
IOSchedulingPriority=4
EOF
  systemctl daemon-reload 2>/dev/null
  echo -e "${cG}已写入 limits 与 realm.service 覆盖（如存在该服务）${c0}"
}

#------------------------------------------
# 300M 瓶颈友好型 sysctl（BBR v3 + fq）
# 设计思路：
# - 上限≈8~12MB 足够覆盖 300M×(150~200ms) 的 BDP，取 12MB 稍留余量
# - 中间值（第二个值）保守，避免并发时内存抖动
# - UDP 提高最低值，避免突发丢包；总上限适中
#------------------------------------------
apply_sysctl_300m() {
  cat > "$SYSCTL_CONF" <<'CONF'
# BBR v3 + fq for Realm relay with 300M upstream bottleneck

# 基本
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# TCP 缓冲：中间值保守，上限 12MB
# （若你更保守，可改回 8MB；更激进可 16MB）
net.core.rmem_default=262144
net.core.wmem_default=262144
net.core.rmem_max=12582912
net.core.wmem_max=12582912
net.ipv4.tcp_rmem=4096 65536 12582912
net.ipv4.tcp_wmem=4096 65536 12582912

# UDP：抬高最低值，适中总上限（单位：页）
net.ipv4.udp_rmem_min=196608
net.ipv4.udp_wmem_min=196608
net.ipv4.udp_mem=32768 9437184 15728640

# 常规稳态
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_mtu_probing=1

# 并发承载（中转机通常还行，不必特别夸张）
net.core.netdev_max_backlog=8192
net.ipv4.tcp_max_syn_backlog=4096
net.core.somaxconn=1024
CONF

  sysctl -p "$SYSCTL_CONF" >/dev/null 2>&1
  echo -e "${cG}sysctl 已写入并加载：$SYSCTL_CONF${c0}"
}

#------------------------------------------
# 状态查看
#------------------------------------------
show_status() {
  echo -e "${cC}=== 当前网络关键参数 ===${c0}"
  echo "内核: $(uname -r)"
  echo "拥塞控制: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
  echo "默认 qdisc: $(sysctl -n net.core.default_qdisc 2>/dev/null)"
  echo "tcp_wmem:   $(sysctl -n net.ipv4.tcp_wmem 2>/dev/null)"
  echo "tcp_rmem:   $(sysctl -n net.ipv4.tcp_rmem 2>/dev/null)"
  echo "udp_mem:    $(sysctl -n net.ipv4.udp_mem 2>/dev/null)"
}

#------------------------------------------
# 菜单
#------------------------------------------
menu() {
  clear
  echo -e "${cM}╔══════════════════════════════════════╗${c0}"
  echo -e "${cM}║   Realm 中转机 300M 专用优化（简版） ║${c0}"
  echo -e "${cM}╚══════════════════════════════════════╝${c0}"
  echo ""
  echo "1) 应用 300M 瓶颈友好型 sysctl（BBRv3+fq+UDP）"
  echo "2) 立即对网卡应用 fq（tc 兜底）"
  echo "3) 启用 MSS clamp（FORWARD）"
  echo "4) 关闭 MSS clamp（FORWARD）"
  echo "5) 并发优化：limits + realm.service 覆盖"
  echo "6) 为 fq 设置单连接 maxrate=280M（可按需）"
  echo "7) 取消单连接限速（移除 maxrate）"
  echo "8) 查看当前关键参数"
  echo "0) 退出"
  echo ""
  read -e -p "选择: " n
  case "$n" in
    1) apply_sysctl_300m; apply_tc_fq_now; show_status; press_any ;;
    2) apply_tc_fq_now; press_any ;;
    3) mss_clamp on; press_any ;;
    4) mss_clamp off; press_any ;;
    5) tune_limits_systemd; press_any ;;
    6) set_fq_maxrate 280mbit; press_any ;;
    7) set_fq_maxrate off; press_any ;;
    8) show_status; press_any ;;
    0) exit 0;;
    *) echo "无效选择"; sleep 1;;
  esac
}

#------------------------------------------
# 主入口
# 支持参数：
#   --apply      直接应用 sysctl + fq
#   --mss on/off 打开/关闭 MSS clamp
#   --maxrate N  设置 fq 单流上限（如 280mbit）；--maxrate off 取消
#   --status     查看参数
#------------------------------------------
main() {
  need_root
  case "$1" in
    --apply)
      apply_sysctl_300m
      apply_tc_fq_now
      show_status
      ;;
    --mss)
      [ "$2" = "on" ] && mss_clamp on || mss_clamp off
      ;;
    --maxrate)
      [ -z "$2" ] && { echo "用法: --maxrate 280mbit|off"; exit 1; }
      set_fq_maxrate "$2"
      ;;
    --status)
      show_status
      ;;
    *)
      menu
      ;;
  esac
}

main "$@"
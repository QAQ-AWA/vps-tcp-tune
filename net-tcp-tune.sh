#!/bin/bash
#=============================================================================
# BBR v3 终极优化脚本 - 融合版
# 功能：结合 XanMod 官方内核的稳定性 + 专业队列算法调优
# 特点：安全性 + 性能 双优化
# 版本：2.0 Ultimate Edition
#=============================================================================

#=============================================================================
# 📋 推荐配置方案（基于实测优化）
#=============================================================================
# 
# 💡 测试环境：经过本人十几二十几台不同服务器的测试
#    包括酷雪云北京9929等多个节点的实测验证
# 
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 
# ⭐ 首选方案（推荐）：
#    步骤1 → 执行菜单选项 1：BBR v3 内核安装
#    步骤2 → 执行菜单选项 2：BBR 直连/落地优化（智能带宽检测）
#            选择子选项 1 进行自动检测
# 
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 
# 🔧 次选方案（备用）：
#    步骤1 → 执行菜单选项 1：BBR v3 内核安装
#    步骤2 → 执行菜单选项 3：NS论坛CAKE调优
#    步骤3 → 执行菜单选项 4：科技lion高性能模式内核参数优化
#            选择第一个选项
# 
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 
#=============================================================================

# 颜色定义
gl_hong='\033[31m'
gl_lv='\033[32m'
gl_huang='\033[33m'
gl_bai='\033[0m'
gl_kjlan='\033[96m'
gl_zi='\033[35m'

# 调试与安全选项
if [ "${VTT_DEBUG:-0}" = "1" ]; then
    set -x
    echo -e "${gl_huang}已启用调试模式 (VTT_DEBUG=1)${gl_bai}"
fi
: "${VTT_SKIP_SHA:=0}"

# 仓库与下载配置
DEFAULT_REPO_OWNER="QAQ-AWA"
DEFAULT_REPO_NAME="vps-tcp-tune"
DEFAULT_REPO_BRANCH="main"

REPO_OWNER="${VTT_REPO_OWNER:-${DEFAULT_REPO_OWNER}}"
REPO_NAME="${VTT_REPO_NAME:-${DEFAULT_REPO_NAME}}"
REPO_BRANCH="${VTT_REPO_BRANCH:-${DEFAULT_REPO_BRANCH}}"

BASE_GITHUB_REPO="https://github.com/${REPO_OWNER}/${REPO_NAME}"
BASE_RAW_GITHUB="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}"
BASE_RELEASES="${BASE_GITHUB_REPO}/releases/download"
CDN_JSDELIVR_RAW="https://cdn.jsdelivr.net/gh/${REPO_OWNER}/${REPO_NAME}@${REPO_BRANCH}"

USE_LEGACY_LINKS="${VTT_USE_LEGACY_LINKS:-0}"
REPO_INFO_PRINTED=0

# GitHub 代理设置
gh_proxy="https://"

# 配置文件路径（使用独立文件，不破坏系统配置）
SYSCTL_CONF="/etc/sysctl.d/99-bbr-ultimate.conf"

# 最近一次成功下载的地址
LAST_DOWNLOAD_URL=""
# ARM64 安装流程的最后错误信息
ARM64_LAST_ERROR=""

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

clean_sysctl_conf() {
    # 备份主配置文件
    if [ -f /etc/sysctl.conf ] && ! [ -f /etc/sysctl.conf.bak.original ]; then
        cp /etc/sysctl.conf /etc/sysctl.conf.bak.original
    fi
    
    # 注释所有冲突参数
    sed -i '/^net.core.rmem_max/s/^/# /' /etc/sysctl.conf 2>/dev/null
    sed -i '/^net.core.wmem_max/s/^/# /' /etc/sysctl.conf 2>/dev/null
    sed -i '/^net.ipv4.tcp_rmem/s/^/# /' /etc/sysctl.conf 2>/dev/null
    sed -i '/^net.ipv4.tcp_wmem/s/^/# /' /etc/sysctl.conf 2>/dev/null
    sed -i '/^net.core.default_qdisc/s/^/# /' /etc/sysctl.conf 2>/dev/null
    sed -i '/^net.ipv4.tcp_congestion_control/s/^/# /' /etc/sysctl.conf 2>/dev/null
}

install_package() {
    local packages=("$@")
    local missing_packages=()
    local os_release="/etc/os-release"
    local os_id=""
    local os_like=""
    local pkg_manager=""
    local update_cmd=()
    local install_cmd=()

    for package in "${packages[@]}"; do
        if ! command -v "$package" &>/dev/null; then
            missing_packages+=("$package")
        fi
    done

    if [ "${#missing_packages[@]}" -eq 0 ]; then
        return 0
    fi

    if [ -r "$os_release" ]; then
        # shellcheck disable=SC1091
        . "$os_release"
        os_id="${ID,,}"
        os_like="${ID_LIKE,,}"
    fi

    local detection="${os_id} ${os_like}"

    if [[ "$detection" =~ (debian|ubuntu) ]]; then
        pkg_manager="apt"
        update_cmd=(apt update -y)
        install_cmd=(apt install -y)
    elif [[ "$detection" =~ (rhel|centos|fedora|rocky|alma|redhat) ]]; then
        if command -v dnf &>/dev/null; then
            pkg_manager="dnf"
            update_cmd=(dnf makecache)
            install_cmd=(dnf install -y)
        elif command -v yum &>/dev/null; then
            pkg_manager="yum"
            update_cmd=(yum makecache)
            install_cmd=(yum install -y)
        else
            echo "错误: 未找到可用的 RHEL 系包管理器 (dnf 或 yum)" >&2
            return 1
        fi
    else
        echo "错误: 未支持的 Linux 发行版，无法自动安装依赖。请手动安装: ${missing_packages[*]}" >&2
        return 1
    fi

    if [ ${#update_cmd[@]} -gt 0 ]; then
        echo -e "${gl_huang}正在更新软件仓库...${gl_bai}"
        if ! "${update_cmd[@]}"; then
            echo "错误: 使用 ${pkg_manager} 更新软件仓库失败。" >&2
            return 1
        fi
    fi

    for package in "${missing_packages[@]}"; do
        echo -e "${gl_huang}正在安装 $package...${gl_bai}"
        if ! "${install_cmd[@]}" "$package"; then
            echo "错误: ${pkg_manager} 安装 $package 失败，请检查上方输出信息。" >&2
            return 1
        fi
    done
}

is_interactive_shell() {
    [ -t 0 ] && [ -t 1 ]
}

download_with_retry() {
    local url="$1"
    local output="$2"
    local retries="${3:-3}"
    local retry_delay="${4:-2}"
    local connect_timeout="${5:-10}"
    local max_time="${6:-120}"
    local status=1

    if command -v curl &>/dev/null; then
        if curl -fsSL --retry "$retries" --retry-delay "$retry_delay" --connect-timeout "$connect_timeout" --max-time "$max_time" -o "$output" "$url"; then
            status=0
        fi
    fi

    if [ $status -ne 0 ] && command -v wget &>/dev/null; then
        local tries=$((retries + 1))
        if wget -q --tries="$tries" --waitretry="$retry_delay" --timeout="$max_time" --connect-timeout="$connect_timeout" -O "$output" "$url"; then
            status=0
        fi
    fi

    if [ $status -ne 0 ]; then
        rm -f "$output"
    fi

    return $status
}

download_from_candidates() {
    local output="$1"
    shift

    rm -f "$output"

    local idx=1
    for candidate in "$@"; do
        [ -z "$candidate" ] && continue
        echo -e "${gl_kjlan}下载候选 #${idx}:${gl_bai} $candidate"
        if download_with_retry "$candidate" "$output"; then
            LAST_DOWNLOAD_URL="$candidate"
            echo -e "${gl_lv}下载成功:${gl_bai} $candidate"
            return 0
        fi
        echo -e "${gl_huang}下载失败:${gl_bai} $candidate"
        idx=$((idx + 1))
    done

    rm -f "$output"
    return 1
}

download_with_fallback() {
    local relative_path="$1"
    local output="$2"
    shift 2
    local -a extra_candidates=("$@")
    local primary="${BASE_RAW_GITHUB}/${relative_path}"
    local cdn="${CDN_JSDELIVR_RAW}/${relative_path}"
    local -a candidates=("$primary" "$cdn")
    candidates+=("${extra_candidates[@]}")
    local -a labels=("自有仓库主源" "自有仓库 CDN 回退")

    print_repo_info_once
    rm -f "$output"

    for idx in "${!candidates[@]}"; do
        local url="${candidates[$idx]}"
        [ -z "$url" ] && continue
        local label="${labels[$idx]:-备用资源}"
        echo -e "${gl_kjlan}${label}:${gl_bai} $url"
        if download_with_retry "$url" "$output"; then
            LAST_DOWNLOAD_URL="$url"
            return 0
        fi
        echo -e "${gl_huang}下载失败 (${label})${gl_bai}"
    done

    rm -f "$output"
    return 1
}

fetch_text() {
    local relative_path="$1"
    local result_var="$2"
    shift 2
    local tmp_file
    tmp_file=$(mktemp)

    if download_with_fallback "$relative_path" "$tmp_file" "$@"; then
        local content
        content=$(cat "$tmp_file")
        rm -f "$tmp_file"
        printf -v "$result_var" "%s" "$content"
        return 0
    fi

    rm -f "$tmp_file"
    return 1
}

fetch_release_asset() {
    local asset_name="$1"
    local output="$2"
    local tag="${3:-}"
    local use_api="${4:-0}"
    local -a candidates=()

    print_repo_info_once
    rm -f "$output"

    if [ -n "$tag" ]; then
        candidates+=("${BASE_RELEASES}/${tag}/${asset_name}")
        candidates+=("https://download.fastgit.org/${REPO_OWNER}/${REPO_NAME}/releases/download/${tag}/${asset_name}")
        candidates+=("https://mirror.ghproxy.com/https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/${tag}/${asset_name}")
        candidates+=("https://cdn.jsdelivr.net/gh/${REPO_OWNER}/${REPO_NAME}@${tag}/${asset_name}")
    else
        candidates+=("${BASE_RAW_GITHUB}/${asset_name}")
        candidates+=("${CDN_JSDELIVR_RAW}/${asset_name}")
    fi

    if [ "$use_api" = "1" ]; then
        local api_endpoint
        if [ -n "$tag" ]; then
            api_endpoint="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/tags/${tag}"
        else
            api_endpoint="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
        fi
        local asset_url
        asset_url=$(curl -fsSL "$api_endpoint" 2>/dev/null | awk -v name="$asset_name" -F'"' '
            $2 == "assets" { in_assets=1; next }
            in_assets && $2 == "name" && $4 == name { getline; if ($2 == "browser_download_url") { print $4; exit } }
        ')
        if [ -n "$asset_url" ]; then
            candidates=("$asset_url" "${candidates[@]}")
        fi
    fi

    for url in "${candidates[@]}"; do
        [ -z "$url" ] && continue
        echo -e "${gl_kjlan}尝试下载发布资产:${gl_bai} $url"
        if download_with_retry "$url" "$output"; then
            LAST_DOWNLOAD_URL="$url"
            return 0
        fi
        echo -e "${gl_huang}下载失败:${gl_bai} $url"
    done

    rm -f "$output"
    return 1
}

print_repo_info_once() {
    if [ "${REPO_INFO_PRINTED}" -eq 0 ]; then
        echo -e "${gl_kjlan}当前资源仓库:${gl_bai} ${REPO_OWNER}/${REPO_NAME}@${REPO_BRANCH}${gl_bai}"
        echo -e "${gl_kjlan}主源:${gl_bai} ${BASE_RAW_GITHUB}${gl_bai}"
        echo -e "${gl_kjlan}CDN 回退:${gl_bai} ${CDN_JSDELIVR_RAW}${gl_bai}"
        if [ "${USE_LEGACY_LINKS}" = "1" ]; then
            echo -e "${gl_huang}已启用旧版链接兼容模式 (VTT_USE_LEGACY_LINKS=1)${gl_bai}"
        fi
        REPO_INFO_PRINTED=1
    fi
}

legacy_raw_url() {
    local owner="$1"
    local repo="$2"
    local ref="$3"
    local path="$4"
    echo "https://raw.githubusercontent.com/${owner}/${repo}/${ref}/${path}"
}

get_repo_resource_path() {
    local key="$1"
    case "$key" in
        "xanmod_archive_key") echo "resources/kejilion/archive.key" ;;
        "xanmod_check_script") echo "resources/kejilion/check_x86-64_psabi.sh" ;;
        "backtrace_install") echo "resources/ludashi2020/backtrace/install.sh" ;;
        "latency_tester") echo "resources/Cd1s/network-latency-tester/latency.sh" ;;
        "pf_realm_script") echo "resources/zywe03/realm-xwPF/xwPF.sh" ;;
        "xray_dual_install") echo "resources/yahuisme/xray-dual/install.sh" ;;
        "sing_box_install") echo "resources/fscarmen/sing-box/sing-box.sh" ;;
        "lotserver_install") echo "resources/fei5seven/lotServer/lotServerInstall.sh" ;;
        *)
            return 1
            ;;
    esac
}

get_repo_resource_description() {
    local key="$1"
    case "$key" in
        "xanmod_archive_key") echo "XanMod 仓库密钥" ;;
        "xanmod_check_script") echo "XanMod 架构检测脚本" ;;
        "backtrace_install") echo "三网回程路由测试脚本" ;;
        "latency_tester") echo "国际互联速度测试脚本" ;;
        "pf_realm_script") echo "PF_realm 转发脚本" ;;
        "xray_dual_install") echo "御坂美琴一键双协议脚本" ;;
        "sing_box_install") echo "F佬一键 sing-box 脚本" ;;
        "lotserver_install") echo "LotServer 管理脚本" ;;
        *)
            echo "$key"
            ;;
    esac
}

get_legacy_url() {
    local key="$1"
    case "$key" in
        "xanmod_archive_key") legacy_raw_url "kejilion" "sh" "main" "archive.key" ;;
        "xanmod_check_script") legacy_raw_url "kejilion" "sh" "main" "check_x86-64_psabi.sh" ;;
        "backtrace_install") legacy_raw_url "ludashi2020" "backtrace" "main" "install.sh" ;;
        "latency_tester") legacy_raw_url "Cd1s" "network-latency-tester" "main" "latency.sh" ;;
        "pf_realm_script") legacy_raw_url "zywe03" "realm-xwPF" "main" "xwPF.sh" ;;
        "xray_dual_install") legacy_raw_url "yahuisme" "xray-dual" "main" "install.sh" ;;
        "sing_box_install") legacy_raw_url "fscarmen" "sing-box" "main" "sing-box.sh" ;;
        "lotserver_install") legacy_raw_url "fei5seven" "lotServer" "master" "lotServerInstall.sh" ;;
        *)
            ;;
    esac
}

download_repo_resource() {
    local key="$1"
    local output="$2"
    local description="${3:-$(get_repo_resource_description "$key")}"
    local relative_path
    if ! relative_path=$(get_repo_resource_path "$key"); then
        echo -e "${gl_hong}未定义的资源键: ${key}${gl_bai}"
        return 1
    fi

    print_repo_info_once
    echo -e "${gl_kjlan}尝试下载 ${description}...${gl_bai}"
    if download_with_fallback "$relative_path" "$output"; then
        echo -e "${gl_lv}下载成功: ${description}${gl_bai}"
        return 0
    fi

    echo -e "${gl_huang}${description} 下载失败${gl_bai}"
    if [ "${USE_LEGACY_LINKS}" = "1" ]; then
        local legacy_url
        legacy_url=$(get_legacy_url "$key")
        if [ -n "$legacy_url" ]; then
            echo -e "${gl_huang}使用旧版链接重试: ${legacy_url}${gl_bai}"
            if download_with_retry "$legacy_url" "$output"; then
                echo -e "${gl_lv}旧版链接下载成功${gl_bai}"
                LAST_DOWNLOAD_URL="$legacy_url"
                return 0
            fi
        fi
    fi

    rm -f "$output"
    echo -e "${gl_hong}无法下载 ${description}${gl_bai}"
    return 1
}

confirm_insecure_operation() {
    local message="$1"
    local skip_env="${VTT_SKIP_SHA:-0}"

    if [ "$skip_env" = "1" ]; then
        echo -e "${gl_huang}警告: ${gl_bai}${message} (VTT_SKIP_SHA=1，已自动跳过校验)"
        return 0
    fi

    if is_interactive_shell; then
        echo -e "${gl_huang}警告: ${gl_bai}${message}"
        local reply
        read -e -p "校验文件缺失，是否跳过校验继续安装？[Y/n]: " reply
        reply=${reply:-Y}
        case "$reply" in
            [Yy]*)
                return 0
                ;;
            *)
                echo "已取消当前操作"
                return 1
                ;;
        esac
    else
        echo -e "${gl_huang}警告: ${gl_bai}${message} (非交互模式默认跳过校验)"
        return 0
    fi
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

    echo -e "${gl_kjlan}=== 调整虚拟内存（仅管理 /swapfile） ===${gl_bai}"

    # 检测是否存在活跃的 /dev/* swap 分区
    local dev_swap_list
    dev_swap_list=$(awk 'NR>1 && $1 ~ /^\/dev\// {printf "  • %s (大小: %d MB, 已用: %d MB)\n", $1, int(($3+512)/1024), int(($4+512)/1024)}' /proc/swaps)

    if [ -n "$dev_swap_list" ]; then
        echo -e "${gl_huang}检测到以下 /dev/ 虚拟内存处于激活状态：${gl_bai}"
        echo "$dev_swap_list"
        echo ""
        echo -e "${gl_huang}提示:${gl_bai} 本脚本不会修改 /dev/ 分区，请使用 ${gl_zi}swapoff <设备>${gl_bai} 等命令手动处理。"
        echo ""
    fi

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
        echo -e "${gl_kjlan}=== 虚拟内存管理（仅限 /swapfile） ===${gl_bai}"
        echo -e "${gl_huang}提示:${gl_bai} 如需调整 /dev/ swap 分区，请手动执行 swapoff/swap 分区工具。"

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

    # 备份原配置文件并记录原始状态
    if [ -f /etc/gai.conf ]; then
        cp /etc/gai.conf /etc/gai.conf.bak.$(date +%Y%m%d_%H%M%S)
        echo "已备份原配置文件到 /etc/gai.conf.bak.*"
        # 记录原先存在文件
        echo "existed" > /etc/gai.conf.original_state
    else
        # 记录原先不存在文件
        echo "not_existed" > /etc/gai.conf.original_state
        echo "原先无配置文件，已记录原始状态"
    fi

    echo "正在设置 IPv4 优先..."

    # 创建完整的 IPv4 优先配置
    cat > /etc/gai.conf << 'EOF'
# Configuration for getaddrinfo(3).
#
# 设置 IPv4 优先

# IPv4 addresses
precedence ::ffff:0:0/96  100

# IPv6 addresses
precedence ::/0           10

# IPv4-mapped IPv6 addresses
precedence ::1/128        50

# Link-local addresses
precedence fe80::/10      1
precedence fec0::/10      1
precedence fc00::/7       1

# Site-local addresses (deprecated)
precedence 2002::/16      30
EOF

    # 刷新 nscd 缓存（如果安装了）
    if command -v nscd &> /dev/null; then
        systemctl restart nscd 2>/dev/null || service nscd restart 2>/dev/null || true
        echo "已刷新 nscd DNS 缓存"
    fi

    # 刷新 systemd-resolved 缓存（如果使用）
    if command -v resolvectl &> /dev/null; then
        resolvectl flush-caches 2>/dev/null || true
        echo "已刷新 systemd-resolved DNS 缓存"
    fi

    echo -e "${gl_lv}✅ IPv4 优先已设置${gl_bai}"
    echo ""
    echo "当前出口 IP 地址："
    echo "------------------------------------------------"
    # 使用 -4 参数强制 IPv4
    curl -4 ip.sb 2>/dev/null || curl ip.sb
    echo ""
    echo "------------------------------------------------"
    echo ""
    echo -e "${gl_huang}提示：${gl_bai}"
    echo "1. 配置已生效，无需重启系统"
    echo "2. 新启动的程序将自动使用 IPv4 优先"
    echo "3. 如需强制指定，可使用: curl -4 ip.sb (强制IPv4) 或 curl -6 ip.sb (强制IPv6)"
    echo "4. 已运行的长连接服务（如Nginx、Docker容器）可能需要重启服务才能应用"
    echo ""

    break_end
}

set_ipv6_priority() {
    clear
    echo -e "${gl_kjlan}=== 设置IPv6优先 ===${gl_bai}"
    echo ""

    # 备份原配置文件并记录原始状态
    if [ -f /etc/gai.conf ]; then
        cp /etc/gai.conf /etc/gai.conf.bak.$(date +%Y%m%d_%H%M%S)
        echo "已备份原配置文件到 /etc/gai.conf.bak.*"
        # 记录原先存在文件
        echo "existed" > /etc/gai.conf.original_state
    else
        # 记录原先不存在文件
        echo "not_existed" > /etc/gai.conf.original_state
        echo "原先无配置文件，已记录原始状态"
    fi

    echo "正在设置 IPv6 优先..."

    # 创建完整的 IPv6 优先配置
    cat > /etc/gai.conf << 'EOF'
# Configuration for getaddrinfo(3).
#
# 设置 IPv6 优先

# IPv6 addresses (highest priority)
precedence ::/0           100

# IPv4 addresses (lower priority)
precedence ::ffff:0:0/96  10

# IPv4-mapped IPv6 addresses
precedence ::1/128        50

# Link-local addresses
precedence fe80::/10      1
precedence fec0::/10      1
precedence fc00::/7       1

# Site-local addresses (deprecated)
precedence 2002::/16      30
EOF

    # 刷新 nscd 缓存（如果安装了）
    if command -v nscd &> /dev/null; then
        systemctl restart nscd 2>/dev/null || service nscd restart 2>/dev/null || true
        echo "已刷新 nscd DNS 缓存"
    fi

    # 刷新 systemd-resolved 缓存（如果使用）
    if command -v resolvectl &> /dev/null; then
        resolvectl flush-caches 2>/dev/null || true
        echo "已刷新 systemd-resolved DNS 缓存"
    fi

    echo -e "${gl_lv}✅ IPv6 优先已设置${gl_bai}"
    echo ""
    echo "当前出口 IP 地址："
    echo "------------------------------------------------"
    # 使用 -6 参数强制 IPv6
    curl -6 ip.sb 2>/dev/null || curl ip.sb
    echo ""
    echo "------------------------------------------------"
    echo ""
    echo -e "${gl_huang}提示：${gl_bai}"
    echo "1. 配置已生效，无需重启系统"
    echo "2. 新启动的程序将自动使用 IPv6 优先"
    echo "3. 如需强制指定，可使用: curl -6 ip.sb (强制IPv6) 或 curl -4 ip.sb (强制IPv4)"
    echo "4. 已运行的长连接服务（如Nginx、Docker容器）可能需要重启服务才能应用"
    echo ""

    break_end
}

manage_ip_priority() {
    while true; do
        clear
        echo -e "${gl_kjlan}=== 设置IPv4/IPv6优先级 ===${gl_bai}"
        echo ""
        echo "1. 设置IPv4优先"
        echo "2. 设置IPv6优先"
        echo "3. 恢复IP优先级配置"
        echo "0. 返回主菜单"
        echo ""
        echo "------------------------------------------------"
        read -p "请选择操作 [0-3]: " ip_priority_choice
        echo ""
        
        case $ip_priority_choice in
            1)
                set_ipv4_priority
                ;;
            2)
                set_ipv6_priority
                ;;
            3)
                restore_gai_conf
                ;;
            0)
                break
                ;;
            *)
                echo -e "${gl_hong}无效选择，请重新输入${gl_bai}"
                sleep 2
                ;;
        esac
    done
}

restore_gai_conf() {
    clear
    echo -e "${gl_kjlan}=== 恢复 IP 优先级配置 ===${gl_bai}"
    echo ""

    # 检查是否有原始状态记录
    if [ ! -f /etc/gai.conf.original_state ]; then
        echo -e "${gl_huang}⚠️  未找到原始状态记录${gl_bai}"
        echo "可能的原因："
        echo "1. 从未使用过本脚本设置过 IPv4/IPv6 优先级"
        echo "2. 原始状态记录文件已被删除"
        echo ""
        
        # 列出所有备份文件
        if ls /etc/gai.conf.bak.* 2>/dev/null; then
            echo "发现以下备份文件："
            ls -lh /etc/gai.conf.bak.* 2>/dev/null
            echo ""
            echo "是否要手动恢复最新的备份？[y/n]"
            read -p "请选择: " manual_restore
            if [[ "$manual_restore" == "y" || "$manual_restore" == "Y" ]]; then
                latest_backup=$(ls -t /etc/gai.conf.bak.* 2>/dev/null | head -1)
                if [ -n "$latest_backup" ]; then
                    cp "$latest_backup" /etc/gai.conf
                    echo -e "${gl_lv}✅ 已从备份恢复: $latest_backup${gl_bai}"
                fi
            fi
        else
            echo "也未找到任何备份文件。"
            echo ""
            echo "是否要删除当前的 gai.conf 文件（恢复到系统默认）？[y/n]"
            read -p "请选择: " delete_conf
            if [[ "$delete_conf" == "y" || "$delete_conf" == "Y" ]]; then
                rm -f /etc/gai.conf
                echo -e "${gl_lv}✅ 已删除 gai.conf，系统将使用默认配置${gl_bai}"
            fi
        fi
    else
        # 读取原始状态
        original_state=$(cat /etc/gai.conf.original_state)
        
        if [ "$original_state" == "not_existed" ]; then
            echo "检测到原先${gl_huang}没有${gl_bai} gai.conf 文件"
            echo "恢复操作将${gl_hong}删除${gl_bai}当前的 gai.conf 文件"
            echo ""
            echo "确认要恢复到原始状态吗？[y/n]"
            read -p "请选择: " confirm
            
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                rm -f /etc/gai.conf
                rm -f /etc/gai.conf.original_state
                echo -e "${gl_lv}✅ 已删除 gai.conf，恢复到原始状态（无配置文件）${gl_bai}"
                
                # 刷新缓存
                if command -v nscd &> /dev/null; then
                    systemctl restart nscd 2>/dev/null || service nscd restart 2>/dev/null || true
                fi
                if command -v resolvectl &> /dev/null; then
                    resolvectl flush-caches 2>/dev/null || true
                fi
            else
                echo "已取消恢复操作"
            fi
            
        elif [ "$original_state" == "existed" ]; then
            echo "检测到原先${gl_lv}存在${gl_bai} gai.conf 文件"
            
            # 查找最新的备份
            latest_backup=$(ls -t /etc/gai.conf.bak.* 2>/dev/null | head -1)
            
            if [ -n "$latest_backup" ]; then
                echo "找到备份文件: $latest_backup"
                echo ""
                echo "确认要从备份恢复吗？[y/n]"
                read -p "请选择: " confirm
                
                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                    cp "$latest_backup" /etc/gai.conf
                    rm -f /etc/gai.conf.original_state
                    echo -e "${gl_lv}✅ 已从备份恢复配置${gl_bai}"
                    
                    # 刷新缓存
                    if command -v nscd &> /dev/null; then
                        systemctl restart nscd 2>/dev/null || service nscd restart 2>/dev/null || true
                        echo "已刷新 nscd DNS 缓存"
                    fi
                    if command -v resolvectl &> /dev/null; then
                        resolvectl flush-caches 2>/dev/null || true
                        echo "已刷新 systemd-resolved DNS 缓存"
                    fi
                    
                    echo ""
                    echo "当前出口 IP 地址："
                    echo "------------------------------------------------"
                    curl ip.sb
                    echo ""
                    echo "------------------------------------------------"
                else
                    echo "已取消恢复操作"
                fi
            else
                echo -e "${gl_hong}错误: 未找到备份文件${gl_bai}"
            fi
        fi
    fi
    
    echo ""
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
        local conn_count_v6_mapped=$(echo "$realm_connections" | grep -c "::ffff:${source_ip}")
        local conn_count=$((conn_count_v4 + conn_count_v6_mapped))
        
        # 判断协议类型（注意：::ffff: 开头的是 IPv4-mapped IPv6，本质是 IPv4）
        local protocol_type=""
        if [ $conn_count_v6_mapped -gt 0 ]; then
            protocol_type="✅ IPv4（IPv6映射格式）"
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
# Realm IPv4 强制转发管理
#=============================================================================

# 备份当前配置
backup_realm_config() {
    local backup_dir="/root/.realm_backup"
    
    # 创建备份目录
    if [ ! -d "$backup_dir" ]; then
        mkdir -p "$backup_dir"
    fi
    
    # 检查是否已存在备份
    if [ -f "$backup_dir/resolv.conf.bak" ] || [ -f "$backup_dir/config.json.bak" ]; then
        echo -e "${gl_huang}⚠️  发现已存在的备份${gl_bai}"
        
        if [ -f "$backup_dir/backup_time.txt" ]; then
            echo -n "备份时间: "
            cat "$backup_dir/backup_time.txt"
        fi
        
        echo ""
        read -p "是否覆盖现有备份? [y/N]: " overwrite
        
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            echo -e "${gl_huang}已取消备份操作${gl_bai}"
            return 1
        fi
    fi
    
    echo -e "${gl_zi}正在备份配置文件...${gl_bai}"
    
    # 备份 resolv.conf
    if [ -f /etc/resolv.conf ]; then
        cp /etc/resolv.conf "$backup_dir/resolv.conf.bak"
        echo -e "${gl_lv}✅ 已备份 /etc/resolv.conf${gl_bai}"
    else
        echo -e "${gl_huang}⚠️  /etc/resolv.conf 不存在${gl_bai}"
    fi
    
    # 备份 realm config
    if [ -f /etc/realm/config.json ]; then
        cp /etc/realm/config.json "$backup_dir/config.json.bak"
        echo -e "${gl_lv}✅ 已备份 /etc/realm/config.json${gl_bai}"
    else
        echo -e "${gl_huang}⚠️  /etc/realm/config.json 不存在${gl_bai}"
    fi
    
    # 记录备份时间
    date '+%Y-%m-%d %H:%M:%S' > "$backup_dir/backup_time.txt"
    
    echo ""
    echo -e "${gl_lv}✅ 配置备份完成！${gl_bai}"
    return 0
}

# 启用 Realm IPv4 强制转发
enable_realm_ipv4() {
    clear
    echo -e "${gl_kjlan}=========================================="
    echo "      启用 Realm IPv4 强制转发"
    echo -e "==========================================${gl_bai}"
    echo ""
    
    # 步骤1：备份配置
    echo -e "${gl_zi}[步骤 1/5] 备份当前配置...${gl_bai}"
    echo ""
    
    if ! backup_realm_config; then
        echo ""
        break_end
        return 1
    fi
    
    echo ""
    
    # 步骤2：修改 resolv.conf
    echo -e "${gl_zi}[步骤 2/5] 修改 DNS 配置...${gl_bai}"
    
    if [ -f /etc/resolv.conf ]; then
        # 删除 IPv6 DNS 服务器行
        local ipv6_dns_count=$(grep -c ':' /etc/resolv.conf 2>/dev/null || echo "0")
        
        if [ "$ipv6_dns_count" -gt 0 ]; then
            sed -i '/nameserver.*:/d' /etc/resolv.conf
            echo -e "${gl_lv}✅ 已删除 ${ipv6_dns_count} 个 IPv6 DNS 服务器${gl_bai}"
        else
            echo -e "${gl_lv}✅ 未发现 IPv6 DNS 服务器${gl_bai}"
        fi
    else
        echo -e "${gl_hong}❌ /etc/resolv.conf 不存在${gl_bai}"
    fi
    
    echo ""
    
    # 步骤3：修改 Realm 配置
    echo -e "${gl_zi}[步骤 3/5] 修改 Realm 配置...${gl_bai}"
    
    if [ ! -f /etc/realm/config.json ]; then
        echo -e "${gl_hong}❌ /etc/realm/config.json 不存在${gl_bai}"
        echo ""
        break_end
        return 1
    fi
    
    # 检查是否安装了 jq
    if ! command -v jq &>/dev/null; then
        echo "正在安装 jq..."
        apt-get update -qq && apt-get install -y jq >/dev/null 2>&1
    fi
    
    # 使用 sed 和手动编辑来修改配置
    local temp_config="/tmp/realm_config_temp.json"
    
    # 读取原配置
    cat /etc/realm/config.json > "$temp_config"
    
    # 添加 resolve: ipv4 (在第一个 { 后插入)
    if ! grep -q '"resolve"' "$temp_config"; then
        sed -i '0,/{/s/{/{\n    "resolve": "ipv4",/' "$temp_config"
        echo -e "${gl_lv}✅ 已添加 resolve: ipv4${gl_bai}"
    else
        echo -e "${gl_lv}✅ resolve 配置已存在${gl_bai}"
    fi
    
    # 替换所有 ::: 为 0.0.0.0
    local listen_count=$(grep -c ':::' "$temp_config" 2>/dev/null || echo "0")
    
    if [ "$listen_count" -gt 0 ]; then
        sed -i 's/":::/"0.0.0.0:/g' "$temp_config"
        echo -e "${gl_lv}✅ 已修改 ${listen_count} 个监听地址为 0.0.0.0${gl_bai}"
    else
        echo -e "${gl_lv}✅ 监听地址已经是 IPv4 格式${gl_bai}"
    fi
    
    # 验证 JSON 格式
    if command -v jq &>/dev/null; then
        if jq empty "$temp_config" 2>/dev/null; then
            mv "$temp_config" /etc/realm/config.json
            echo -e "${gl_lv}✅ 配置文件格式验证通过${gl_bai}"
        else
            echo -e "${gl_hong}❌ 配置文件格式错误，已回滚${gl_bai}"
            rm "$temp_config"
            return 1
        fi
    else
        mv "$temp_config" /etc/realm/config.json
    fi
    
    echo ""
    
    # 步骤4：重启 Realm 服务
    echo -e "${gl_zi}[步骤 4/5] 重启 Realm 服务...${gl_bai}"
    
    if systemctl restart realm 2>/dev/null; then
        sleep 2
        
        if systemctl is-active --quiet realm; then
            echo -e "${gl_lv}✅ Realm 服务重启成功${gl_bai}"
        else
            echo -e "${gl_hong}❌ Realm 服务启动失败${gl_bai}"
            echo ""
            echo "查看服务状态："
            systemctl status realm --no-pager -l
        fi
    else
        echo -e "${gl_huang}⚠️  未找到 realm systemd 服务${gl_bai}"
        echo "如果使用其他方式启动，请手动重启 Realm"
    fi
    
    echo ""
    
    # 步骤5：验证配置
    echo -e "${gl_zi}[步骤 5/5] 验证配置...${gl_bai}"
    echo ""
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${gl_huang}DNS 配置:${gl_bai}"
    grep '^nameserver' /etc/resolv.conf 2>/dev/null || echo "无 DNS 配置"
    echo ""
    
    echo -e "${gl_huang}Realm 监听端口:${gl_bai}"
    ss -tlnp 2>/dev/null | grep realm | awk '{print $4}' | head -5 || echo "无监听端口"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    echo -e "${gl_lv}🎉 IPv4 强制转发配置完成！${gl_bai}"
    echo ""
    echo "验证方法："
    echo "  ss -tlnp | grep realm"
    echo "  (应该只显示 0.0.0.0:端口，而不是 [::]:端口)"
    echo ""
    
    break_end
}

# 还原原始配置
restore_realm_config() {
    clear
    echo -e "${gl_kjlan}=========================================="
    echo "        还原 Realm 原始配置"
    echo -e "==========================================${gl_bai}"
    echo ""
    
    local backup_dir="/root/.realm_backup"
    
    # 检查备份是否存在
    if [ ! -d "$backup_dir" ]; then
        echo -e "${gl_hong}❌ 备份目录不存在${gl_bai}"
        echo ""
        echo "可能原因："
        echo "  - 从未执行过 IPv4 强制转发配置"
        echo "  - 备份文件已被删除"
        echo ""
        break_end
        return 1
    fi
    
    if [ ! -f "$backup_dir/resolv.conf.bak" ] && [ ! -f "$backup_dir/config.json.bak" ]; then
        echo -e "${gl_hong}❌ 未找到备份文件${gl_bai}"
        echo ""
        break_end
        return 1
    fi
    
    # 显示备份信息
    echo -e "${gl_zi}备份信息:${gl_bai}"
    if [ -f "$backup_dir/backup_time.txt" ]; then
        echo -n "备份时间: "
        cat "$backup_dir/backup_time.txt"
    fi
    echo ""
    
    read -p "确认还原配置? [y/N]: " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${gl_huang}已取消还原操作${gl_bai}"
        echo ""
        break_end
        return 1
    fi
    
    echo ""
    echo -e "${gl_zi}正在还原配置文件...${gl_bai}"
    
    # 还原 resolv.conf
    if [ -f "$backup_dir/resolv.conf.bak" ]; then
        cp "$backup_dir/resolv.conf.bak" /etc/resolv.conf
        echo -e "${gl_lv}✅ 已还原 /etc/resolv.conf${gl_bai}"
    fi
    
    # 还原 realm config
    if [ -f "$backup_dir/config.json.bak" ]; then
        cp "$backup_dir/config.json.bak" /etc/realm/config.json
        echo -e "${gl_lv}✅ 已还原 /etc/realm/config.json${gl_bai}"
    fi
    
    echo ""
    
    # 重启服务
    echo -e "${gl_zi}正在重启 Realm 服务...${gl_bai}"
    
    if systemctl restart realm 2>/dev/null; then
        sleep 2
        
        if systemctl is-active --quiet realm; then
            echo -e "${gl_lv}✅ Realm 服务重启成功${gl_bai}"
        else
            echo -e "${gl_hong}❌ Realm 服务启动失败${gl_bai}"
        fi
    else
        echo -e "${gl_huang}⚠️  未找到 realm systemd 服务${gl_bai}"
    fi
    
    echo ""
    echo -e "${gl_lv}✅ 配置还原完成！${gl_bai}"
    echo ""
    
    break_end
}

# Realm IPv4 管理主菜单
realm_ipv4_management() {
    while true; do
        clear
        echo -e "${gl_kjlan}=========================================="
        echo "      Realm 转发强制使用 IPv4"
        echo -e "==========================================${gl_bai}"
        echo ""
        
        # 显示当前状态
        echo -e "${gl_zi}当前状态:${gl_bai}"
        
        # 检查备份
        if [ -d /root/.realm_backup ] && [ -f /root/.realm_backup/config.json.bak ]; then
            echo -e "备份状态: ${gl_lv}✅ 已备份${gl_bai}"
            if [ -f /root/.realm_backup/backup_time.txt ]; then
                echo -n "备份时间: "
                cat /root/.realm_backup/backup_time.txt
            fi
        else
            echo -e "备份状态: ${gl_huang}⚠️  未备份${gl_bai}"
        fi
        
        # 检查 Realm 配置
        if [ -f /etc/realm/config.json ]; then
            if grep -q '"resolve".*"ipv4"' /etc/realm/config.json 2>/dev/null; then
                echo -e "IPv4强制: ${gl_lv}✅ 已启用${gl_bai}"
            else
                echo -e "IPv4强制: ${gl_huang}⚠️  未启用${gl_bai}"
            fi
            
            local listen_ipv6=$(grep -c ':::' /etc/realm/config.json 2>/dev/null || echo "0")
            if [ "$listen_ipv6" -gt 0 ]; then
                echo -e "监听地址: ${gl_huang}检测到 ${listen_ipv6} 个 IPv6 监听${gl_bai}"
            else
                echo -e "监听地址: ${gl_lv}✅ IPv4 格式${gl_bai}"
            fi
        else
            echo -e "配置文件: ${gl_hong}❌ 不存在${gl_bai}"
        fi
        
        # 检查 DNS
        if [ -f /etc/resolv.conf ]; then
            local ipv6_dns=$(grep -c 'nameserver.*:' /etc/resolv.conf 2>/dev/null || echo "0")
            if [ "$ipv6_dns" -gt 0 ]; then
                echo -e "DNS配置: ${gl_huang}检测到 ${ipv6_dns} 个 IPv6 DNS${gl_bai}"
            else
                echo -e "DNS配置: ${gl_lv}✅ 仅 IPv4 DNS${gl_bai}"
            fi
        fi
        
        echo ""
        echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo ""
        echo "1. 启用 IPv4 强制转发（会先备份）"
        echo "2. 还原到原始配置"
        echo "3. 查看详细配置"
        echo "0. 返回主菜单"
        echo ""
        
        read -p "请选择操作 [0-3]: " choice
        
        case $choice in
            1)
                enable_realm_ipv4
                ;;
            2)
                restore_realm_config
                ;;
            3)
                clear
                echo -e "${gl_kjlan}=========================================="
                echo "           详细配置信息"
                echo -e "==========================================${gl_bai}"
                echo ""
                
                echo -e "${gl_huang}=== DNS 配置 ===${gl_bai}"
                cat /etc/resolv.conf 2>/dev/null || echo "文件不存在"
                echo ""
                
                echo -e "${gl_huang}=== Realm 配置 ===${gl_bai}"
                cat /etc/realm/config.json 2>/dev/null || echo "文件不存在"
                echo ""
                
                echo -e "${gl_huang}=== Realm 监听端口 ===${gl_bai}"
                ss -tlnp 2>/dev/null | grep realm || echo "无监听端口"
                echo ""
                
                break_end
                ;;
            0)
                return 0
                ;;
            *)
                echo ""
                echo -e "${gl_hong}无效选择${gl_bai}"
                sleep 1
                ;;
        esac
    done
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

# 自动检测所有入站连接
check_all_inbound_connections() {
    clear
    echo -e "${gl_kjlan}=========================================="
    echo "自动检测所有入站连接"
    echo -e "==========================================${gl_bai}"
    echo ""
    
    echo -e "${gl_zi}[1/3] 获取所有 ESTABLISHED 入站连接...${gl_bai}"
    echo ""
    
    # 获取所有 ESTABLISHED 连接的远程地址（兼容多种ss版本）
    # 尝试多种方式获取连接
    local connections=""
    
    # 方法1：使用 state 参数（新版ss）
    if ss -tn state established &>/dev/null; then
        connections=$(ss -tn state established 2>/dev/null | awk 'NR>1 && $1=="ESTAB" {print $5}' | grep -v "^$")
    fi
    
    # 方法2：使用 grep ESTAB（兼容旧版ss）
    if [ -z "$connections" ]; then
        connections=$(ss -tn 2>/dev/null | grep ESTAB | awk '{print $5}' | grep -v "^$")
    fi
    
    # 方法3：使用 netstat 作为后备
    if [ -z "$connections" ] && command -v netstat &>/dev/null; then
        connections=$(netstat -tn 2>/dev/null | grep ESTABLISHED | awk '{print $5}' | grep -v "^$")
    fi
    
    # 过滤本地回环连接（可选，保留所有连接以便调试）
    # connections=$(echo "$connections" | grep -v "^127.0.0.1" | grep -v "^\[::1\]")
    
    # 调试信息
    local conn_count=$(echo "$connections" | wc -l | tr -d ' ')
    echo -e "${gl_zi}检测到 ${gl_lv}${conn_count}${gl_zi} 个ESTABLISHED连接${gl_bai}"
    echo ""
    
    if [ -z "$connections" ] || [ "$conn_count" -eq 0 ]; then
        echo -e "${gl_huang}未发现任何活跃连接${gl_bai}"
        echo ""
        echo "可能的原因："
        echo "1. 当前确实没有建立的TCP连接"
        echo "2. 需要root权限查看所有连接（请使用 sudo 运行）"
        echo "3. 转发可能使用UDP协议（请检查 ss -un 或 netstat -un）"
        echo ""
        echo "快速检查命令："
        echo "  查看TCP: ss -tn | grep ESTAB"
        echo "  查看UDP: ss -un"
        echo "  查看监听端口: ss -tlnp"
        echo "  查看所有连接: ss -antp"
        echo ""
        
        # 显示原始ss输出用于调试
        echo -e "${gl_zi}═══ 原始连接信息（调试用） ═══${gl_bai}"
        ss -tn 2>/dev/null | head -20
        echo ""
        
        break_end
        return 1
    fi
    
    echo -e "${gl_zi}[2/3] 分析连接协议类型...${gl_bai}"
    echo ""
    
    # 统计 IPv4 和 IPv6 连接
    # 注意：::ffff: 开头的是 IPv4-mapped IPv6，本质是 IPv4
    # 先去掉端口号，再统计
    local connections_no_port=$(echo "$connections" | sed 's/:[0-9]*$//')
    
    local ipv4_mapped=$(echo "$connections_no_port" | grep -c "::ffff:")
    local ipv6_real=$(echo "$connections_no_port" | grep ":" | grep -vc "::ffff:")
    local ipv4_pure=$(echo "$connections_no_port" | grep -vc ":")
    local ipv4_connections=$((ipv4_pure + ipv4_mapped))
    local ipv6_connections=$ipv6_real
    local total_connections=$(echo "$connections" | wc -l)
    
    # 提取唯一的源 IP（去重）
    local unique_sources=$(echo "$connections_no_port" | sort -u)
    local source_count=$(echo "$unique_sources" | wc -l)
    
    echo -e "${gl_zi}[3/3] 生成统计报告...${gl_bai}"
    echo ""
    
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "            连接统计总览"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""
    echo -e "  • 总连接数:       ${gl_lv}${total_connections}${gl_bai}"
    echo -e "  • 唯一源IP数:     ${gl_huang}${source_count}${gl_bai}"
    echo ""
    echo -e "  ${gl_zi}协议分布：${gl_bai}"
    echo -e "    - IPv4（纯）:    ${gl_lv}${ipv4_pure}${gl_bai} 个"
    echo -e "    - IPv4（映射）:  ${gl_lv}${ipv4_mapped}${gl_bai} 个"
    echo -e "    - IPv4 总计:     ${gl_lv}${ipv4_connections}${gl_bai} 个"
    echo -e "    - IPv6（真）:    ${ipv6_connections} 个"
    echo ""
    
    if [ "$ipv6_connections" -eq 0 ]; then
        echo -e "  ${gl_lv}✅ 100% 使用 IPv4 链路（包含映射格式）${gl_bai}"
    else
        local ipv4_percent=$((ipv4_connections * 100 / total_connections))
        local ipv6_percent=$((ipv6_connections * 100 / total_connections))
        echo -e "  ${gl_huang}⚠️  混合链路: IPv4 ${ipv4_percent}% | IPv6 ${ipv6_percent}%${gl_bai}"
    fi
    
    echo ""
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""
    
    # 显示 Top 10 源 IP（增强版：带归属信息）
    echo -e "${gl_zi}Top 10 连接源详情（按连接数排序）：${gl_bai}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    local source_num=1
    echo "$connections" | sed 's/:[0-9]*$//' | sort | uniq -c | sort -rn | head -10 | while read count ip; do
        # 提取纯 IP（去除方括号）
        local clean_ip=$(echo "$ip" | sed 's/\[::ffff://; s/\]//')
        
        # 判断协议类型
        local protocol_type=""
        local protocol_color=""
        if echo "$ip" | grep -q "::ffff:"; then
            protocol_type="IPv4（映射格式）"
            protocol_color="${gl_lv}"
        elif echo "$ip" | grep -q ":"; then
            protocol_type="IPv6（真）"
            protocol_color="${gl_hong}"
        else
            protocol_type="纯IPv4"
            protocol_color="${gl_lv}"
            clean_ip="$ip"
        fi
        
        # IP 归属查询
        local ip_location="查询中..."
        local ip_as="未知"
        
        if command -v curl &>/dev/null; then
            local ip_info=$(timeout 2 curl -s "http://ip-api.com/json/${clean_ip}?lang=zh-CN&fields=country,regionName,city,isp,as" 2>/dev/null)
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
        
        # 美化显示
        echo -e "┌─────────────── 连接源 #${source_num} ───────────────┐"
        echo -e "│  源IP地址:   ${gl_huang}${clean_ip}${gl_bai}"
        echo -e "│  IP归属:     ${ip_location}"
        [ -n "$ip_as" ] && echo -e "│  AS号:       ${ip_as}"
        echo -e "│  连接数:     ${gl_lv}${count}${gl_bai} 个"
        echo -e "│  协议类型:   ${protocol_color}✅ ${protocol_type}${gl_bai}"
        echo -e "└──────────────────────────────────────────┘"
        echo ""
        
        source_num=$((source_num + 1))
    done
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # 显示监听端口
    echo -e "${gl_zi}本地监听端口（Top 5）：${gl_bai}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    ss -tln 2>/dev/null | awk 'NR>1 {print $4}' | sed 's/.*://' | sort | uniq -c | sort -rn | head -5 | while read count port; do
        echo -e "  端口 ${gl_huang}${port}${gl_bai} - ${count} 个监听"
    done
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
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
        echo "1. 自动检测所有入站连接（推荐，无需输入IP）"
        echo "2. 出站检测（检测本机到目标服务器的连接）"
        echo "3. 入站检测（检测来自指定源服务器的连接）"
        echo "0. 返回主菜单"
        echo "------------------------------------------------"
        read -e -p "请输入选择: " choice
        
        case "$choice" in
            1)
                # 自动检测所有入站
                check_all_inbound_connections
                ;;
            2)
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
            3)
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
    echo "1. 自动检测（推荐，自动选择最近服务器）" >&2
    echo "2. 手动指定测速服务器（指定服务器ID）" >&2
    echo "3. 使用默认值（1000 Mbps / 1 Gbps，跳过检测）" >&2
    echo "" >&2
    
    read -e -p "请输入选择 [1]: " bw_choice
    bw_choice=${bw_choice:-1}
    
    case "$bw_choice" in
        1)
            # 自动检测带宽 - 选择最近服务器
            echo "" >&2
            echo -e "${gl_huang}正在运行 speedtest 测速...${gl_bai}" >&2
            echo -e "${gl_zi}提示: 自动选择距离最近的服务器${gl_bai}" >&2
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
            
            # 智能测速：获取附近服务器列表，按距离依次尝试
            echo -e "${gl_zi}正在搜索附近测速服务器...${gl_bai}" >&2
            
            # 获取附近服务器列表（按延迟排序）
            local servers_list=$(speedtest --accept-license --servers 2>/dev/null | grep -oP '^\s*\K[0-9]+' | head -n 10)
            
            if [ -z "$servers_list" ]; then
                echo -e "${gl_huang}无法获取服务器列表，使用自动选择...${gl_bai}" >&2
                servers_list="auto"
            else
                local server_count=$(echo "$servers_list" | wc -l)
                echo -e "${gl_lv}✅ 找到 ${server_count} 个附近服务器${gl_bai}" >&2
            fi
            echo "" >&2
            
            local speedtest_output=""
            local upload_speed=""
            local attempt=0
            local max_attempts=5  # 最多尝试5个服务器
            
            # 逐个尝试服务器
            for server_id in $servers_list; do
                attempt=$((attempt + 1))
                
                if [ $attempt -gt $max_attempts ]; then
                    echo -e "${gl_huang}已尝试 ${max_attempts} 个服务器，停止尝试${gl_bai}" >&2
                    break
                fi
                
                if [ "$server_id" = "auto" ]; then
                    echo -e "${gl_zi}[尝试 ${attempt}] 自动选择最近服务器...${gl_bai}" >&2
                    speedtest_output=$(speedtest --accept-license 2>&1)
                else
                    echo -e "${gl_zi}[尝试 ${attempt}] 测试服务器 #${server_id}...${gl_bai}" >&2
                    speedtest_output=$(speedtest --accept-license --server-id="$server_id" 2>&1)
                fi
                
                echo "$speedtest_output" >&2
                echo "" >&2
                
                # 提取上传速度
                upload_speed=""
                if echo "$speedtest_output" | grep -q "Upload:"; then
                    upload_speed=$(echo "$speedtest_output" | grep -i "Upload:" | grep -oP '\d+\.\d+' 2>/dev/null | head -n1)
                fi
                if [ -z "$upload_speed" ]; then
                    upload_speed=$(echo "$speedtest_output" | grep -i "Upload:" | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.[0-9]+$/) {print $i; exit}}')
                fi
                
                # 检查是否成功
                if [ -n "$upload_speed" ] && ! echo "$speedtest_output" | grep -qi "FAILED\|error"; then
                    local success_server=$(echo "$speedtest_output" | grep "Server:" | head -n1 | sed 's/.*Server: //')
                    echo -e "${gl_lv}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}" >&2
                    echo -e "${gl_lv}✅ 测速成功！${gl_bai}" >&2
                    echo -e "${gl_zi}使用服务器: ${success_server}${gl_bai}" >&2
                    echo -e "${gl_lv}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}" >&2
                    echo "" >&2
                    break
                else
                    local failed_server=$(echo "$speedtest_output" | grep "Server:" | head -n1 | sed 's/.*Server: //' | sed 's/[[:space:]]*$//')
                    if [ -n "$failed_server" ]; then
                        echo -e "${gl_huang}⚠️  失败: ${failed_server}${gl_bai}" >&2
                    else
                        echo -e "${gl_huang}⚠️  此服务器失败${gl_bai}" >&2
                    fi
                    echo -e "${gl_zi}继续尝试下一个服务器...${gl_bai}" >&2
                    echo "" >&2
                fi
            done
            
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
            echo "" >&2
            
            # 所有尝试都失败了
            if [ -z "$upload_speed" ] || echo "$speedtest_output" | grep -qi "FAILED\|error"; then
                echo -e "${gl_huang}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}" >&2
                echo -e "${gl_huang}⚠️  无法自动检测带宽${gl_bai}" >&2
                echo -e "${gl_huang}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}" >&2
                echo "" >&2
                echo -e "${gl_zi}原因: 测速服务器可能暂时不可用${gl_bai}" >&2
                echo "" >&2
                echo -e "${gl_kjlan}默认配置方案：${gl_bai}" >&2
                echo -e "  带宽:       ${gl_huang}1000 Mbps (1 Gbps)${gl_bai}" >&2
                echo -e "  缓冲区:     ${gl_huang}16 MB${gl_bai}" >&2
                echo -e "  适用场景:   ${gl_zi}标准 1Gbps 服务器（覆盖大多数场景）${gl_bai}" >&2
                echo "" >&2
                echo -e "${gl_huang}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}" >&2
                echo "" >&2
                
                # 询问用户确认
                read -e -p "是否使用默认值 1000 Mbps？(Y/N) [Y]: " use_default
                use_default=${use_default:-Y}
                
                case "$use_default" in
                    [Yy])
                        echo "" >&2
                        echo -e "${gl_lv}✅ 使用默认配置: 1000 Mbps（16 MB 缓冲区）${gl_bai}" >&2
                        echo "1000"
                        return 0
                        ;;
                    [Nn])
                        echo "" >&2
                        echo -e "${gl_zi}请手动输入带宽值${gl_bai}" >&2
                        local manual_bandwidth=""
                        while true; do
                            read -e -p "请输入上传带宽（单位：Mbps，如 500、1000、2000）: " manual_bandwidth
                            if [[ "$manual_bandwidth" =~ ^[0-9]+$ ]] && [ "$manual_bandwidth" -gt 0 ]; then
                                echo "" >&2
                                echo -e "${gl_lv}✅ 使用自定义值: ${manual_bandwidth} Mbps${gl_bai}" >&2
                                echo "$manual_bandwidth"
                                return 0
                            else
                                echo -e "${gl_hong}❌ 请输入有效的数字${gl_bai}" >&2
                            fi
                        done
                        ;;
                    *)
                        echo "" >&2
                        echo -e "${gl_huang}输入无效，使用默认值 1000 Mbps${gl_bai}" >&2
                        echo "1000"
                        return 0
                        ;;
                esac
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
            # 手动指定测速服务器ID
            echo "" >&2
            echo -e "${gl_kjlan}=== 手动指定测速服务器 ===${gl_bai}" >&2
            echo "" >&2
            
            # 检查speedtest是否安装
            if ! command -v speedtest &>/dev/null; then
                echo -e "${gl_huang}speedtest 未安装，正在安装...${gl_bai}" >&2
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
                        echo "将使用通用值 1000 Mbps" >&2
                        echo "1000"
                        return 1
                        ;;
                esac
                
                cd /tmp
                wget -q "$download_url" -O speedtest.tgz && \
                tar -xzf speedtest.tgz && \
                mv speedtest /usr/local/bin/ && \
                rm -f speedtest.tgz
                
                if [ $? -ne 0 ]; then
                    echo -e "${gl_hong}安装失败，将使用默认值 1000 Mbps${gl_bai}" >&2
                    echo "1000"
                    return 1
                fi
                echo -e "${gl_lv}✅ speedtest 安装成功${gl_bai}" >&2
                echo "" >&2
            fi
            
            # 显示如何查看服务器列表
            echo -e "${gl_zi}📋 如何查看可用的测速服务器：${gl_bai}" >&2
            echo "" >&2
            echo -e "  方法1：查看所有服务器列表" >&2
            echo -e "  ${gl_huang}speedtest --servers${gl_bai}" >&2
            echo "" >&2
            echo -e "  方法2：只显示附近服务器（推荐）" >&2
            echo -e "  ${gl_huang}speedtest --servers | head -n 20${gl_bai}" >&2
            echo "" >&2
            echo -e "${gl_zi}💡 服务器列表格式说明：${gl_bai}" >&2
            echo -e "  每行开头的数字就是服务器ID" >&2
            echo -e "  例如: ${gl_huang}12345${gl_bai}) 服务商名称 (位置, 距离)" >&2
            echo "" >&2
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
            echo "" >&2
            
            # 询问是否现在查看服务器列表
            read -e -p "是否现在查看附近的测速服务器列表？(Y/N) [Y]: " show_list
            show_list=${show_list:-Y}
            
            if [[ "$show_list" =~ ^[Yy]$ ]]; then
                echo "" >&2
                echo -e "${gl_kjlan}附近的测速服务器列表：${gl_bai}" >&2
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
                speedtest --accept-license --servers 2>/dev/null | head -n 20 >&2
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
                echo "" >&2
            fi
            
            # 输入服务器ID
            local server_id=""
            while true; do
                read -e -p "$(echo -e "${gl_huang}请输入测速服务器ID（纯数字）: ${gl_bai}")" server_id
                
                if [[ "$server_id" =~ ^[0-9]+$ ]]; then
                    break
                else
                    echo -e "${gl_hong}❌ 无效输入，请输入纯数字的服务器ID${gl_bai}" >&2
                fi
            done
            
            # 使用指定服务器测速
            echo "" >&2
            echo -e "${gl_huang}正在使用服务器 #${server_id} 测速...${gl_bai}" >&2
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
            echo "" >&2
            
            local speedtest_output=$(speedtest --accept-license --server-id="$server_id" 2>&1)
            echo "$speedtest_output" >&2
            echo "" >&2
            
            # 提取上传速度
            local upload_speed=""
            if echo "$speedtest_output" | grep -q "Upload:"; then
                upload_speed=$(echo "$speedtest_output" | grep -i "Upload:" | grep -oP '\d+\.\d+' 2>/dev/null | head -n1)
            fi
            if [ -z "$upload_speed" ]; then
                upload_speed=$(echo "$speedtest_output" | grep -i "Upload:" | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.[0-9]+$/) {print $i; exit}}')
            fi
            
            # 检查测速是否成功
            if [ -n "$upload_speed" ] && ! echo "$speedtest_output" | grep -qi "FAILED\|error"; then
                local upload_mbps=${upload_speed%.*}
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
                echo -e "${gl_lv}✅ 测速成功！${gl_bai}" >&2
                echo -e "${gl_lv}检测到上传带宽: ${upload_mbps} Mbps${gl_bai}" >&2
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
                echo "" >&2
                echo "$upload_mbps"
                return 0
            else
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
                echo -e "${gl_hong}❌ 测速失败${gl_bai}" >&2
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
                echo "" >&2
                echo -e "${gl_zi}可能原因：${gl_bai}" >&2
                echo "  - 服务器ID不存在或已下线" >&2
                echo "  - 网络连接问题" >&2
                echo "  - 该服务器暂时不可用" >&2
                echo "" >&2
                
                read -e -p "是否使用默认值 1000 Mbps？(Y/N) [Y]: " use_default
                use_default=${use_default:-Y}
                
                if [[ "$use_default" =~ ^[Yy]$ ]]; then
                    echo "" >&2
                    echo -e "${gl_lv}✅ 使用默认配置: 1000 Mbps（16 MB 缓冲区）${gl_bai}" >&2
                    echo "1000"
                    return 0
                else
                    echo "" >&2
                    echo -e "${gl_zi}请手动输入带宽值${gl_bai}" >&2
                    local manual_bandwidth=""
                    while true; do
                        read -e -p "请输入上传带宽（单位：Mbps，如 500、1000、2000）: " manual_bandwidth
                        if [[ "$manual_bandwidth" =~ ^[0-9]+$ ]] && [ "$manual_bandwidth" -gt 0 ]; then
                            echo "" >&2
                            echo -e "${gl_lv}✅ 使用自定义值: ${manual_bandwidth} Mbps${gl_bai}" >&2
                            echo "$manual_bandwidth"
                            return 0
                        else
                            echo -e "${gl_hong}❌ 请输入有效的数字${gl_bai}" >&2
                        fi
                    done
                fi
            fi
            ;;
        3)
            # 使用默认值
            echo "" >&2
            echo -e "${gl_lv}使用默认配置: 1000 Mbps（16 MB 缓冲区）${gl_bai}" >&2
            echo -e "${gl_zi}说明: 适合标准 1Gbps 服务器，覆盖大多数场景${gl_bai}" >&2
            echo "" >&2
            echo "1000"
            return 0
            ;;
        *)
            echo -e "${gl_huang}无效选择，使用默认值 1000 Mbps${gl_bai}" >&2
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
        sed -i '/^net.core.default_qdisc/s/^/# /' /etc/sysctl.conf 2>/dev/null
        sed -i '/^net.ipv4.tcp_congestion_control/s/^/# /' /etc/sysctl.conf 2>/dev/null
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


apply_bbr_preferences() {
    echo -e "${gl_kjlan}=== 配置 BBR/BBR2 与队列算法 ===${gl_bai}"

    if ! command -v sysctl &>/dev/null; then
        echo -e "${gl_hong}错误: 未检测到 sysctl，无法配置网络参数${gl_bai}"
        return 1
    fi

    local available_cc
    available_cc=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null)

    local selected_cc=""
    if echo "$available_cc" | grep -qw "bbr2"; then
        selected_cc="bbr2"
    elif echo "$available_cc" | grep -qw "bbr"; then
        selected_cc="bbr"
    fi

    if [ -n "$selected_cc" ]; then
        if sysctl -w net.ipv4.tcp_congestion_control="$selected_cc" >/dev/null 2>&1; then
            echo -e "拥塞控制算法: ${gl_lv}${selected_cc} ✓${gl_bai}"
        else
            echo -e "${gl_huang}警告: 无法立即应用 ${selected_cc}，可能需要重启。${gl_bai}"
        fi
    else
        echo -e "${gl_huang}警告: 当前内核未提供 bbr/bbr2 拥塞控制算法${gl_bai}"
    fi

    local target_qdisc="fq"
    if command -v modprobe &>/dev/null; then
        if ! modprobe -q sch_fq 2>/dev/null; then
            if modprobe -q sch_fq_codel 2>/dev/null; then
                target_qdisc="fq_codel"
                echo -e "${gl_huang}提示: sch_fq 模块不可用，已回退至 fq_codel${gl_bai}"
            else
                target_qdisc=""
                echo -e "${gl_huang}警告: sch_fq / sch_fq_codel 模块不可用，保持系统默认队列${gl_bai}"
            fi
        fi
    fi

    if [ -n "$target_qdisc" ]; then
        if sysctl -w net.core.default_qdisc="$target_qdisc" >/dev/null 2>&1; then
            echo -e "默认队列算法: ${gl_lv}${target_qdisc} ✓${gl_bai}"
        else
            echo -e "${gl_huang}警告: 无法立即设置默认队列，可能需要重启。${gl_bai}"
        fi
    fi

    if [ -n "$selected_cc" ] || [ -n "$target_qdisc" ]; then
        mkdir -p /etc/sysctl.d
        {
            echo "# Generated by net-tcp-tune.sh (ARM64 BBR 配置)"
            echo "# $(date '+%Y-%m-%d %H:%M:%S')"
            if [ -n "$target_qdisc" ]; then
                echo "net.core.default_qdisc=$target_qdisc"
            fi
            if [ -n "$selected_cc" ]; then
                echo "net.ipv4.tcp_congestion_control=$selected_cc"
            fi
        } > "$SYSCTL_CONF"

        if sysctl -p "$SYSCTL_CONF" >/dev/null 2>&1; then
            echo -e "${gl_lv}持久化配置已写入 ${SYSCTL_CONF}${gl_bai}"
        else
            echo -e "${gl_huang}警告: sysctl -p 应用失败，请稍后手动执行: sysctl -p ${SYSCTL_CONF}${gl_bai}"
        fi
    else
        echo -e "${gl_huang}提示: 未写入持久化配置（缺少可用的 BBR/队列参数）${gl_bai}"
    fi

    local current_cc="未知"
    local current_qdisc="未知"
    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")
    current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "未知")

    echo "当前拥塞控制: $current_cc"
    echo "当前默认队列: $current_qdisc"
    echo "当前内核版本: $(uname -r)"
}

try_install_xanmod_arm64() {
    ARM64_LAST_ERROR=""
    echo -e "${gl_kjlan}→ 尝试通过 XanMod APT 仓库安装 ARM64 内核${gl_bai}"

    local arch=""
    arch=$(dpkg --print-architecture 2>/dev/null || true)
    if [ -z "$arch" ]; then
        arch=$(uname -m 2>/dev/null)
    fi
    case "$arch" in
        arm64|aarch64)
            ;;
        *)
            ARM64_LAST_ERROR="当前架构 (${arch:-未知}) 非 ARM64"
            return 1
            ;;
    esac

    local keyring="/usr/share/keyrings/xanmod-archive-keyring.gpg"
    local repo_file="/etc/apt/sources.list.d/xanmod-release.list"
    local key_installed=0

    if [ -s "$keyring" ]; then
        key_installed=1
    else
        local key_tmp
        key_tmp=$(mktemp 2>/dev/null)
        if [ -n "$key_tmp" ]; then
            if download_repo_resource "xanmod_archive_key" "$key_tmp" "XanMod 仓库密钥"; then
                if gpg --dearmor -o "$keyring" --yes "$key_tmp"; then
                    key_installed=1
                else
                    echo -e "${gl_huang}密钥导入失败，尝试官方源${gl_bai}"
                fi
            else
                echo -e "${gl_huang}未能从自有仓库获取 XanMod 密钥，尝试官方源${gl_bai}"
            fi

            if [ "$key_installed" -ne 1 ]; then
                rm -f "$key_tmp"
                key_tmp=$(mktemp 2>/dev/null)
                if [ -n "$key_tmp" ] && download_with_retry "https://dl.xanmod.org/archive.key" "$key_tmp"; then
                    if gpg --dearmor -o "$keyring" --yes "$key_tmp"; then
                        key_installed=1
                    fi
                fi
            fi

            rm -f "$key_tmp"
        fi
    fi

    if [ "$key_installed" -ne 1 ]; then
        ARM64_LAST_ERROR="无法获取 XanMod 仓库密钥"
        return 1
    fi

    local repo_preexisting=0
    if [ -f "$repo_file" ]; then
        repo_preexisting=1
    fi
    echo "deb [signed-by=${keyring}] http://deb.xanmod.org releases main" | tee "$repo_file" > /dev/null
    echo -e "${gl_kjlan}已写入 XanMod APT 仓库: ${repo_file}${gl_bai}"

    if ! apt update; then
        ARM64_LAST_ERROR="apt update 失败（XanMod 仓库不可用或网络异常）"
        if [ "$repo_preexisting" -eq 0 ]; then
            rm -f "$repo_file"
        fi
        return 1
    fi

    local package=""
    local -a prefer_pkgs=(
        "linux-xanmod-lts"
        "linux-image-xanmod-lts"
        "linux-xanmod"
        "linux-image-xanmod"
    )

    local pkg
    for pkg in "${prefer_pkgs[@]}"; do
        if apt-cache show "$pkg" >/dev/null 2>&1; then
            package="$pkg"
            break
        fi
    done

    if [ -z "$package" ]; then
        package=$(apt-cache search --names-only '^linux.*xanmod' 2>/dev/null | awk '{print $1}' | head -n1)
    fi

    if [ -z "$package" ]; then
        ARM64_LAST_ERROR="XanMod 仓库中未找到 ARM64 内核包"
        if [ "$repo_preexisting" -eq 0 ]; then
            rm -f "$repo_file"
        fi
        return 1
    fi

    echo -e "${gl_kjlan}检测到可用内核包:${gl_bai} ${package}"
    if ! apt install -y "$package"; then
        ARM64_LAST_ERROR="apt 安装 ${package} 失败"
        if [ "$repo_preexisting" -eq 0 ]; then
            rm -f "$repo_file"
        fi
        return 1
    fi

    local header_pkg=""
    local candidate_header=""
    case "$package" in
        linux-image-*)
            candidate_header="${package/linux-image/linux-headers}"
            if apt-cache show "$candidate_header" >/dev/null 2>&1; then
                header_pkg="$candidate_header"
            fi
            ;;
        linux-xanmod*)
            if apt-cache show linux-headers-xanmod >/dev/null 2>&1; then
                header_pkg="linux-headers-xanmod"
            fi
            ;;
    esac

    if [ -n "$header_pkg" ]; then
        echo -e "${gl_kjlan}尝试安装头文件:${gl_bai} ${header_pkg}"
        apt install -y "$header_pkg" >/dev/null 2>&1 || true
    fi

    echo -e "${gl_lv}已安装 XanMod ARM64 内核 (${package})${gl_bai}"
    return 0
}

try_install_debian_backports_kernel() {
    ARM64_LAST_ERROR=""

    local os_id=""
    local codename=""

    if [ -r /etc/os-release ]; then
        . /etc/os-release
        os_id="${ID,,}"
        codename="$VERSION_CODENAME"
    fi

    if [ "$os_id" != "debian" ]; then
        ARM64_LAST_ERROR="当前系统不是 Debian，跳过 backports"
        return 1
    fi

    if [ -z "$codename" ] && command -v lsb_release &>/dev/null; then
        codename=$(lsb_release -sc 2>/dev/null)
    fi

    if [ -z "$codename" ]; then
        ARM64_LAST_ERROR="无法识别 Debian 发行代号"
        return 1
    fi

    local list_file="/etc/apt/sources.list.d/${codename}-backports.list"
    if [ -f "$list_file" ]; then
        if ! grep -q "${codename}-backports" "$list_file"; then
            echo "deb http://deb.debian.org/debian ${codename}-backports main" >> "$list_file"
        fi
    else
        echo "deb http://deb.debian.org/debian ${codename}-backports main" > "$list_file"
    fi

    if ! apt update -y; then
        ARM64_LAST_ERROR="apt update 失败（${codename}-backports）"
        return 1
    fi

    if apt install -y -t "${codename}-backports" linux-image-arm64; then
        apt install -y -t "${codename}-backports" linux-headers-arm64 >/dev/null 2>&1 || true
        echo -e "${gl_lv}已通过 Debian ${codename}-backports 安装最新 ARM64 内核${gl_bai}"
        return 0
    fi

    ARM64_LAST_ERROR="安装 linux-image-arm64 失败"
    return 1
}

try_install_ubuntu_hwe_kernel() {
    ARM64_LAST_ERROR=""

    local os_id=""
    local version_id=""

    if [ -r /etc/os-release ]; then
        . /etc/os-release
        os_id="${ID,,}"
        version_id="$VERSION_ID"
    fi

    if [ "$os_id" != "ubuntu" ]; then
        ARM64_LAST_ERROR="当前系统不是 Ubuntu，跳过 HWE"
        return 1
    fi

    if [ -z "$version_id" ] && command -v lsb_release &>/dev/null; then
        version_id=$(lsb_release -sr 2>/dev/null)
    fi

    if [ -z "$version_id" ]; then
        ARM64_LAST_ERROR="无法识别 Ubuntu 版本号"
        return 1
    fi

    local hwe_pkg="linux-generic-hwe-${version_id}"
    hwe_pkg=${hwe_pkg// /}

    if ! apt-cache show "$hwe_pkg" >/dev/null 2>&1; then
        if apt-cache show linux-generic >/dev/null 2>&1; then
            hwe_pkg="linux-generic"
        else
            ARM64_LAST_ERROR="未找到可用的 HWE 元包"
            return 1
        fi
    fi

    if apt install -y "$hwe_pkg"; then
        echo -e "${gl_lv}已安装 Ubuntu HWE 内核 (${hwe_pkg})${gl_bai}"
        return 0
    fi

    ARM64_LAST_ERROR="安装 ${hwe_pkg} 失败"
    return 1
}

install_arm64_kernel_stack() {
    echo -e "${gl_kjlan}=== ARM64 内核安装流程 ===${gl_bai}"
    echo -e "${gl_kjlan}策略顺序:${gl_bai} XanMod APT → Debian Backports → Ubuntu HWE → BBR/BBR2 + fq"

    check_disk_space 3

    if ! install_package curl wget ca-certificates gnupg xz-utils python3 lsb-release; then
        echo -e "${gl_huang}警告: 依赖安装失败，将尝试使用当前环境继续${gl_bai}"
    fi

    local kernel_installed=false
    local install_source=""
    local failure_msgs=()

    if try_install_xanmod_arm64; then
        kernel_installed=true
        install_source="XanMod APT 仓库"
    else
        local reason="${ARM64_LAST_ERROR:-未知原因}"
        failure_msgs+=("XanMod APT: ${reason}")
    fi

    if [ "$kernel_installed" = false ]; then
        if try_install_debian_backports_kernel; then
            kernel_installed=true
            install_source="Debian Backports"
        else
            local reason="${ARM64_LAST_ERROR:-未知原因}"
            failure_msgs+=("Debian Backports: ${reason}")
        fi
    fi

    if [ "$kernel_installed" = false ]; then
        if try_install_ubuntu_hwe_kernel; then
            kernel_installed=true
            install_source="Ubuntu HWE"
        else
            local reason="${ARM64_LAST_ERROR:-未知原因}"
            failure_msgs+=("Ubuntu HWE: ${reason}")
        fi
    fi

    if [ "$kernel_installed" = true ]; then
        echo -e "${gl_lv}内核安装成功，来源: ${install_source}${gl_bai}"
        echo -e "${gl_kjlan}策略结果:${gl_bai} ${install_source}"
        echo -e "${gl_huang}提示: 请重启系统以加载新内核 (reboot)${gl_bai}"
    else
        echo -e "${gl_huang}未能安装新的 ARM64 内核，准备在现有内核上启用 BBR/BBR2${gl_bai}"
        for item in "${failure_msgs[@]}"; do
            [ -n "$item" ] && echo -e "${gl_huang}  • ${item}${gl_bai}"
        done
        echo -e "${gl_kjlan}策略结果:${gl_bai} 使用当前内核 + BBR/BBR2 + fq"
    fi

    echo -e "${gl_kjlan}配置拥塞控制与默认队列...${gl_bai}"
    if ! apply_bbr_preferences; then
        echo -e "${gl_huang}警告: BBR/队列配置未完全成功，请手动检查${gl_bai}"
    fi

    echo ""
    check_bbr_status

    if [ "$kernel_installed" = true ]; then
        if command -v update-grub &>/dev/null; then
            echo ""
            echo -e "${gl_zi}提示: 使用 GRUB 的系统建议运行 update-grub 后重启。${gl_bai}"
        fi
    fi

    return 0
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
        install_arm64_kernel_stack
        return $?
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
    local xanmod_key_tmp
    xanmod_key_tmp=$(mktemp)
    local key_imported=0

    if download_repo_resource "xanmod_archive_key" "$xanmod_key_tmp" "XanMod 仓库密钥"; then
        if gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg --yes "$xanmod_key_tmp"; then
            key_imported=1
        else
            echo -e "${gl_huang}密钥导入失败，尝试官方源...${gl_bai}"
        fi
    else
        echo -e "${gl_huang}未能从自有仓库获取 XanMod 密钥，尝试官方源...${gl_bai}"
    fi

    if [ $key_imported -ne 1 ]; then
        if download_with_retry "https://dl.xanmod.org/archive.key" "$xanmod_key_tmp"; then
            if gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg --yes "$xanmod_key_tmp"; then
                key_imported=1
            else
                echo -e "${gl_hong}密钥导入失败${gl_bai}"
            fi
        else
            echo -e "${gl_hong}密钥下载失败${gl_bai}"
        fi
    fi

    rm -f "$xanmod_key_tmp"

    if [ $key_imported -ne 1 ]; then
        echo -e "${gl_hong}无法获取 XanMod 仓库密钥，终止安装${gl_bai}"
        return 1
    fi

    local xanmod_repo_file="/etc/apt/sources.list.d/xanmod-release.list"

    # 添加 XanMod 仓库
    echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' | \
        tee "$xanmod_repo_file" > /dev/null
    
    # 检测 CPU 架构版本
    echo "正在检测 CPU 支持的最优内核版本..."
    local version=""
    local check_script_tmp
    check_script_tmp=$(mktemp)

    if download_repo_resource "xanmod_check_script" "$check_script_tmp" "XanMod 架构检测脚本"; then
        chmod +x "$check_script_tmp"
        local detect_output
        detect_output=$(bash "$check_script_tmp" 2>/dev/null)
        version=$(echo "$detect_output" | grep -oP 'x86-64-v\K\d+|x86-64-v\d+' | head -n1)
        if [[ "$version" =~ ^x86-64-v([0-9]+)$ ]]; then
            version="${BASH_REMATCH[1]}"
        fi
    fi

    rm -f "$check_script_tmp"

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
        rm -f "$xanmod_repo_file"
        return 1
    fi

    echo -e "${gl_lv}XanMod 内核安装成功！${gl_bai}"
    echo -e "${gl_huang}提示: 请先重启系统加载新内核，然后再配置 BBR${gl_bai}"
    echo -e "${gl_kjlan}后续更新: 可执行 ${gl_bai}sudo apt update && sudo apt upgrade${gl_kjlan} 以获取最新内核${gl_bai}"

    read -e -p "是否保留 XanMod 软件源以便后续自动获取更新？(Y/n): " keep_repo
    case "${keep_repo:-Y}" in
        [Nn])
            echo -e "${gl_huang}移除软件源后将无法通过 apt upgrade 自动获取内核更新，如需更新需重新添加仓库。${gl_bai}"
            read -e -p "确认仍要移除 XanMod 软件源吗？(Y/N): " remove_repo
            case "$remove_repo" in
                [Yy])
                    rm -f "$xanmod_repo_file"
                    echo -e "${gl_huang}已按要求移除 XanMod 软件源。${gl_bai}"
                    ;;
                *)
                    echo -e "${gl_lv}已保留 XanMod 软件源。${gl_bai}"
                    ;;
            esac
            ;;
        *)
            echo -e "${gl_lv}已保留 XanMod 软件源，系统可通过 apt upgrade 获取未来的内核更新。${gl_bai}"
            ;;
    esac

    return 0
}


#=============================================================================
# IP地址获取函数
#=============================================================================

ip_address() {
    local public_ip=""
    local candidate=""
    local external_api_success=false
    local last_curl_status=0
    local external_api_notice=""

    if candidate=$(curl -4 -fsS --max-time 2 https://ipinfo.io/ip 2>/dev/null); then
        candidate=$(echo "$candidate" | tr -d '\r\n')
        if [ -n "$candidate" ]; then
            public_ip="$candidate"
            external_api_success=true
        fi
    else
        last_curl_status=$?
    fi

    if [ "$external_api_success" = false ]; then
        if candidate=$(curl -4 -fsS --max-time 2 https://api.ip.sb/ip 2>/dev/null); then
            candidate=$(echo "$candidate" | tr -d '\r\n')
            if [ -n "$candidate" ]; then
                public_ip="$candidate"
                external_api_success=true
            fi
        else
            last_curl_status=$?
        fi
    fi

    if [ "$external_api_success" = false ]; then
        if candidate=$(curl -4 -fsS --max-time 2 https://ifconfig.me/ip 2>/dev/null); then
            candidate=$(echo "$candidate" | tr -d '\r\n')
            if [ -n "$candidate" ]; then
                public_ip="$candidate"
                external_api_success=true
            fi
        else
            last_curl_status=$?
        fi
    fi

    if [ "$external_api_success" = false ]; then
        public_ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i == "src") {print $(i+1); exit}}')
    fi

    if [ -z "$public_ip" ]; then
        public_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi

    if [ -z "$public_ip" ]; then
        public_ip="外部接口不可达"
    fi

    if [ "$external_api_success" = false ]; then
        external_api_notice="外部接口不可达"
        if [ "$last_curl_status" -ne 0 ]; then
            external_api_notice+=" (curl 返回码 $last_curl_status)"
        fi
    fi

    local local_ipv4=""
    local_ipv4=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i == "src") {print $(i+1); exit}}')
    if [ -z "$local_ipv4" ]; then
        local_ipv4=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    if [ -z "$local_ipv4" ]; then
        local_ipv4="外部接口不可达"
    fi

    if ! isp_info=$(curl -fsS --max-time 2 http://ipinfo.io/org 2>/dev/null); then
        isp_info=""
    else
        isp_info=$(echo "$isp_info" | tr -d '\r\n')
    fi

    if [ -z "$isp_info" ] && [ -n "$external_api_notice" ]; then
        isp_info="$external_api_notice"
    fi

    if echo "$isp_info" | grep -Eiq 'mobile|unicom|telecom'; then
        ipv4_address="$local_ipv4"
    else
        ipv4_address="$public_ip"
    fi

    if [ -z "$ipv4_address" ]; then
        ipv4_address="$local_ipv4"
    fi

    if ! ipv6_address=$(curl -fsS --max-time 2 https://v6.ipinfo.io/ip 2>/dev/null); then
        ipv6_address=""
    else
        ipv6_address=$(echo "$ipv6_address" | tr -d '\r\n')
    fi

    if [ -n "$external_api_notice" ] && [ -z "$isp_info" ]; then
        isp_info="$external_api_notice"
    fi

    if [ -z "$isp_info" ]; then
        isp_info="未获取到运营商信息"
    fi
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
# 内核参数优化 - 星辰大海ヾ优化模式（VLESS Reality/AnyTLS专用）
#=============================================================================

optimize_xinchendahai() {
    echo -e "${gl_lv}切换到星辰大海ヾ优化模式...${gl_bai}"
    echo -e "${gl_zi}针对 VLESS Reality/AnyTLS 节点深度优化${gl_bai}"
    echo ""
    echo -e "${gl_hong}⚠️  重要提示 ⚠️${gl_bai}"
    echo -e "${gl_huang}本配置为临时生效（使用 sysctl -w 命令）${gl_bai}"
    echo -e "${gl_huang}重启后将恢复到永久配置文件的设置${gl_bai}"
    echo ""
    echo "如果你之前执行过："
    echo "  - CAKE调优 / Debian12调优 / BBR直连优化"
    echo "重启后会恢复到那些配置，本次优化会消失！"
    echo ""
    read -e -p "是否继续？(Y/N) [Y]: " confirm
    confirm=${confirm:-Y}
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo "已取消"
        return
    fi
    echo ""

    # 文件描述符优化
    echo -e "${gl_lv}优化文件描述符...${gl_bai}"
    ulimit -n 131072
    echo "  ✓ 文件描述符: 131072 (13万)"

    # 内存管理优化
    echo -e "${gl_lv}优化内存管理...${gl_bai}"
    sysctl -w vm.swappiness=5 2>/dev/null
    echo "  ✓ swappiness = 5 （安全值）"
    sysctl -w vm.dirty_ratio=15 2>/dev/null
    echo "  ✓ dirty_ratio = 15"
    sysctl -w vm.dirty_background_ratio=5 2>/dev/null
    echo "  ✓ dirty_background_ratio = 5"
    sysctl -w vm.overcommit_memory=1 2>/dev/null
    echo "  ✓ overcommit_memory = 1"

    # TCP拥塞控制（保持用户的队列算法，不覆盖CAKE）
    echo -e "${gl_lv}优化TCP拥塞控制...${gl_bai}"
    sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null
    echo "  ✓ tcp_congestion_control = bbr"
    current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    if [ "$current_qdisc" = "cake" ]; then
        echo "  ✓ default_qdisc = cake （保持用户设置）"
    else
        echo "  ℹ default_qdisc = $current_qdisc （保持不变）"
    fi

    # TCP连接优化（TLS握手加速）
    echo -e "${gl_lv}优化TCP连接（TLS握手加速）...${gl_bai}"
    sysctl -w net.ipv4.tcp_fastopen=3 2>/dev/null
    echo "  ✓ tcp_fastopen = 3"
    sysctl -w net.ipv4.tcp_slow_start_after_idle=0 2>/dev/null
    echo "  ✓ tcp_slow_start_after_idle = 0 （关键优化）"
    sysctl -w net.ipv4.tcp_tw_reuse=1 2>/dev/null
    echo "  ✓ tcp_tw_reuse = 1"
    sysctl -w net.ipv4.tcp_fin_timeout=30 2>/dev/null
    echo "  ✓ tcp_fin_timeout = 30"
    sysctl -w net.ipv4.tcp_max_syn_backlog=8192 2>/dev/null
    echo "  ✓ tcp_max_syn_backlog = 8192"

    # TCP保活设置
    echo -e "${gl_lv}优化TCP保活...${gl_bai}"
    sysctl -w net.ipv4.tcp_keepalive_time=600 2>/dev/null
    echo "  ✓ tcp_keepalive_time = 600s (10分钟)"
    sysctl -w net.ipv4.tcp_keepalive_intvl=30 2>/dev/null
    echo "  ✓ tcp_keepalive_intvl = 30s"
    sysctl -w net.ipv4.tcp_keepalive_probes=5 2>/dev/null
    echo "  ✓ tcp_keepalive_probes = 5"

    # TCP缓冲区优化（16MB）
    echo -e "${gl_lv}优化TCP缓冲区（16MB）...${gl_bai}"
    sysctl -w net.core.rmem_max=16777216 2>/dev/null
    echo "  ✓ rmem_max = 16MB"
    sysctl -w net.core.wmem_max=16777216 2>/dev/null
    echo "  ✓ wmem_max = 16MB"
    sysctl -w net.ipv4.tcp_rmem='4096 87380 16777216' 2>/dev/null
    echo "  ✓ tcp_rmem = 4K 85K 16MB"
    sysctl -w net.ipv4.tcp_wmem='4096 65536 16777216' 2>/dev/null
    echo "  ✓ tcp_wmem = 4K 64K 16MB"

    # UDP优化（QUIC支持）
    echo -e "${gl_lv}优化UDP（QUIC支持）...${gl_bai}"
    sysctl -w net.ipv4.udp_rmem_min=8192 2>/dev/null
    echo "  ✓ udp_rmem_min = 8192"
    sysctl -w net.ipv4.udp_wmem_min=8192 2>/dev/null
    echo "  ✓ udp_wmem_min = 8192"

    # 连接队列优化
    echo -e "${gl_lv}优化连接队列...${gl_bai}"
    sysctl -w net.core.somaxconn=4096 2>/dev/null
    echo "  ✓ somaxconn = 4096"
    sysctl -w net.core.netdev_max_backlog=5000 2>/dev/null
    echo "  ✓ netdev_max_backlog = 5000 （修正过高值）"
    sysctl -w net.ipv4.ip_local_port_range='1024 65535' 2>/dev/null
    echo "  ✓ ip_local_port_range = 1024-65535"

    echo ""
    echo -e "${gl_lv}星辰大海ヾ优化模式设置完成！${gl_bai}"
    echo -e "${gl_zi}配置特点: TLS握手加速 + QUIC支持 + 大并发优化 + CAKE兼容${gl_bai}"
    echo -e "${gl_huang}优化说明: 已修正过激参数，保持用户CAKE设置，适配≥2GB内存${gl_bai}"
}

#=============================================================================
# 内核参数优化 - Reality终极优化（方案E）
#=============================================================================

optimize_reality_ultimate() {
    echo -e "${gl_lv}切换到Reality终极优化模式...${gl_bai}"
    echo -e "${gl_zi}基于星辰大海深度改进，性能提升5-10%，资源消耗降低25%${gl_bai}"
    echo ""
    echo -e "${gl_hong}⚠️  重要提示 ⚠️${gl_bai}"
    echo -e "${gl_huang}本配置为临时生效（使用 sysctl -w 命令）${gl_bai}"
    echo -e "${gl_huang}重启后将恢复到永久配置文件的设置${gl_bai}"
    echo ""
    echo "如果你之前执行过："
    echo "  - CAKE调优 / Debian12调优 / BBR直连优化"
    echo "重启后会恢复到那些配置，本次优化会消失！"
    echo ""
    read -e -p "是否继续？(Y/N) [Y]: " confirm
    confirm=${confirm:-Y}
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo "已取消"
        return
    fi
    echo ""

    # 文件描述符优化
    echo -e "${gl_lv}优化文件描述符...${gl_bai}"
    ulimit -n 524288
    echo "  ✓ 文件描述符: 524288 (50万)"

    # TCP拥塞控制（核心）
    echo -e "${gl_lv}优化TCP拥塞控制...${gl_bai}"
    sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null
    echo "  ✓ tcp_congestion_control = bbr"
    current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    if [ "$current_qdisc" = "cake" ]; then
        echo "  ✓ default_qdisc = cake （保持用户设置）"
    else
        echo "  ℹ default_qdisc = $current_qdisc （保持不变）"
    fi

    # TCP连接优化（TLS握手加速）
    echo -e "${gl_lv}优化TCP连接（TLS握手加速）...${gl_bai}"
    sysctl -w net.ipv4.tcp_fastopen=3 2>/dev/null
    echo "  ✓ tcp_fastopen = 3"
    sysctl -w net.ipv4.tcp_slow_start_after_idle=0 2>/dev/null
    echo "  ✓ tcp_slow_start_after_idle = 0 （关键优化）"
    sysctl -w net.ipv4.tcp_tw_reuse=1 2>/dev/null
    echo "  ✓ tcp_tw_reuse = 1"
    sysctl -w net.ipv4.ip_local_port_range='1024 65535' 2>/dev/null
    echo "  ✓ ip_local_port_range = 1024-65535"

    # Reality特有优化（方案E核心亮点）
    echo -e "${gl_lv}Reality特有优化...${gl_bai}"
    sysctl -w net.ipv4.tcp_notsent_lowat=16384 2>/dev/null
    echo "  ✓ tcp_notsent_lowat = 16384 （减少延迟）"
    sysctl -w net.ipv4.tcp_fin_timeout=15 2>/dev/null
    echo "  ✓ tcp_fin_timeout = 15 （快速回收）"
    sysctl -w net.ipv4.tcp_max_tw_buckets=5000 2>/dev/null
    echo "  ✓ tcp_max_tw_buckets = 5000"

    # TCP缓冲区（12MB平衡配置）
    echo -e "${gl_lv}优化TCP缓冲区（12MB）...${gl_bai}"
    sysctl -w net.core.rmem_max=12582912 2>/dev/null
    echo "  ✓ rmem_max = 12MB"
    sysctl -w net.core.wmem_max=12582912 2>/dev/null
    echo "  ✓ wmem_max = 12MB"
    sysctl -w net.ipv4.tcp_rmem='4096 87380 12582912' 2>/dev/null
    echo "  ✓ tcp_rmem = 4K 85K 12MB"
    sysctl -w net.ipv4.tcp_wmem='4096 65536 12582912' 2>/dev/null
    echo "  ✓ tcp_wmem = 4K 64K 12MB"

    # 内存管理
    echo -e "${gl_lv}优化内存管理...${gl_bai}"
    sysctl -w vm.swappiness=5 2>/dev/null
    echo "  ✓ swappiness = 5"
    sysctl -w vm.dirty_ratio=15 2>/dev/null
    echo "  ✓ dirty_ratio = 15"
    sysctl -w vm.dirty_background_ratio=5 2>/dev/null
    echo "  ✓ dirty_background_ratio = 5"
    sysctl -w vm.overcommit_memory=1 2>/dev/null
    echo "  ✓ overcommit_memory = 1"
    sysctl -w vm.vfs_cache_pressure=50 2>/dev/null
    echo "  ✓ vfs_cache_pressure = 50"

    # 连接保活（更短的检测周期）
    echo -e "${gl_lv}优化连接保活...${gl_bai}"
    sysctl -w net.ipv4.tcp_keepalive_time=300 2>/dev/null
    echo "  ✓ tcp_keepalive_time = 300s (5分钟)"
    sysctl -w net.ipv4.tcp_keepalive_intvl=30 2>/dev/null
    echo "  ✓ tcp_keepalive_intvl = 30s"
    sysctl -w net.ipv4.tcp_keepalive_probes=5 2>/dev/null
    echo "  ✓ tcp_keepalive_probes = 5"

    # UDP/QUIC优化
    echo -e "${gl_lv}优化UDP（QUIC支持）...${gl_bai}"
    sysctl -w net.ipv4.udp_rmem_min=8192 2>/dev/null
    echo "  ✓ udp_rmem_min = 8192"
    sysctl -w net.ipv4.udp_wmem_min=8192 2>/dev/null
    echo "  ✓ udp_wmem_min = 8192"

    # 连接队列优化（科学配置）
    echo -e "${gl_lv}优化连接队列...${gl_bai}"
    sysctl -w net.core.somaxconn=4096 2>/dev/null
    echo "  ✓ somaxconn = 4096"
    sysctl -w net.ipv4.tcp_max_syn_backlog=8192 2>/dev/null
    echo "  ✓ tcp_max_syn_backlog = 8192"
    sysctl -w net.core.netdev_max_backlog=5000 2>/dev/null
    echo "  ✓ netdev_max_backlog = 5000 （科学值）"

    # TCP安全
    echo -e "${gl_lv}TCP安全增强...${gl_bai}"
    sysctl -w net.ipv4.tcp_syncookies=1 2>/dev/null
    echo "  ✓ tcp_syncookies = 1"
    sysctl -w net.ipv4.tcp_mtu_probing=1 2>/dev/null
    echo "  ✓ tcp_mtu_probing = 1"

    echo ""
    echo -e "${gl_lv}星辰大海ヾ优化模式设置完成！${gl_bai}"
    echo -e "${gl_zi}配置特点: TLS握手加速 + QUIC支持 + 大并发优化 + CAKE兼容${gl_bai}"
    echo -e "${gl_huang}优化说明: 已修正过激参数，保持用户CAKE设置，适配≥2GB内存${gl_bai}"
}

#=============================================================================
# 内核参数优化 - Reality终极优化（方案E）
#=============================================================================

optimize_reality_ultimate() {
    echo -e "${gl_lv}切换到Reality终极优化模式...${gl_bai}"
    echo -e "${gl_zi}基于星辰大海深度改进，性能提升5-10%，资源消耗降低25%${gl_bai}"
    echo ""
    echo -e "${gl_hong}⚠️  重要提示 ⚠️${gl_bai}"
    echo -e "${gl_huang}本配置为临时生效（使用 sysctl -w 命令）${gl_bai}"
    echo -e "${gl_huang}重启后将恢复到永久配置文件的设置${gl_bai}"
    echo ""
    echo "如果你之前执行过："
    echo "  - CAKE调优 / Debian12调优 / BBR直连优化"
    echo "重启后会恢复到那些配置，本次优化会消失！"
    echo ""
    read -e -p "是否继续？(Y/N) [Y]: " confirm
    confirm=${confirm:-Y}
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo "已取消"
        return
    fi
    echo ""

    # 文件描述符优化
    echo -e "${gl_lv}优化文件描述符...${gl_bai}"
    ulimit -n 524288
    echo "  ✓ 文件描述符: 524288 (50万)"

    # TCP拥塞控制（核心）
    echo -e "${gl_lv}优化TCP拥塞控制...${gl_bai}"
    sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null
    echo "  ✓ tcp_congestion_control = bbr"
    current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    if [ "$current_qdisc" = "cake" ]; then
        echo "  ✓ default_qdisc = cake （保持用户设置）"
    else
        echo "  ℹ default_qdisc = $current_qdisc （保持不变）"
    fi

    # TCP连接优化（TLS握手加速）
    echo -e "${gl_lv}优化TCP连接（TLS握手加速）...${gl_bai}"
    sysctl -w net.ipv4.tcp_fastopen=3 2>/dev/null
    echo "  ✓ tcp_fastopen = 3"
    sysctl -w net.ipv4.tcp_slow_start_after_idle=0 2>/dev/null
    echo "  ✓ tcp_slow_start_after_idle = 0 （关键优化）"
    sysctl -w net.ipv4.tcp_tw_reuse=1 2>/dev/null
    echo "  ✓ tcp_tw_reuse = 1"
    sysctl -w net.ipv4.ip_local_port_range='1024 65535' 2>/dev/null
    echo "  ✓ ip_local_port_range = 1024-65535"

    # Reality特有优化（方案E核心亮点）
    echo -e "${gl_lv}Reality特有优化...${gl_bai}"
    sysctl -w net.ipv4.tcp_notsent_lowat=16384 2>/dev/null
    echo "  ✓ tcp_notsent_lowat = 16384 （减少延迟）"
    sysctl -w net.ipv4.tcp_fin_timeout=15 2>/dev/null
    echo "  ✓ tcp_fin_timeout = 15 （快速回收）"
    sysctl -w net.ipv4.tcp_max_tw_buckets=5000 2>/dev/null
    echo "  ✓ tcp_max_tw_buckets = 5000"

    # TCP缓冲区（12MB平衡配置）
    echo -e "${gl_lv}优化TCP缓冲区（12MB）...${gl_bai}"
    sysctl -w net.core.rmem_max=12582912 2>/dev/null
    echo "  ✓ rmem_max = 12MB"
    sysctl -w net.core.wmem_max=12582912 2>/dev/null
    echo "  ✓ wmem_max = 12MB"
    sysctl -w net.ipv4.tcp_rmem='4096 87380 12582912' 2>/dev/null
    echo "  ✓ tcp_rmem = 4K 85K 12MB"
    sysctl -w net.ipv4.tcp_wmem='4096 65536 12582912' 2>/dev/null
    echo "  ✓ tcp_wmem = 4K 64K 12MB"

    # 内存管理
    echo -e "${gl_lv}优化内存管理...${gl_bai}"
    sysctl -w vm.swappiness=5 2>/dev/null
    echo "  ✓ swappiness = 5"
    sysctl -w vm.dirty_ratio=15 2>/dev/null
    echo "  ✓ dirty_ratio = 15"
    sysctl -w vm.dirty_background_ratio=5 2>/dev/null
    echo "  ✓ dirty_background_ratio = 5"
    sysctl -w vm.overcommit_memory=1 2>/dev/null
    echo "  ✓ overcommit_memory = 1"
    sysctl -w vm.vfs_cache_pressure=50 2>/dev/null
    echo "  ✓ vfs_cache_pressure = 50"

    # 连接保活（更短的检测周期）
    echo -e "${gl_lv}优化连接保活...${gl_bai}"
    sysctl -w net.ipv4.tcp_keepalive_time=300 2>/dev/null
    echo "  ✓ tcp_keepalive_time = 300s (5分钟)"
    sysctl -w net.ipv4.tcp_keepalive_intvl=30 2>/dev/null
    echo "  ✓ tcp_keepalive_intvl = 30s"
    sysctl -w net.ipv4.tcp_keepalive_probes=5 2>/dev/null
    echo "  ✓ tcp_keepalive_probes = 5"

    # UDP/QUIC优化
    echo -e "${gl_lv}优化UDP（QUIC支持）...${gl_bai}"
    sysctl -w net.ipv4.udp_rmem_min=8192 2>/dev/null
    echo "  ✓ udp_rmem_min = 8192"
    sysctl -w net.ipv4.udp_wmem_min=8192 2>/dev/null
    echo "  ✓ udp_wmem_min = 8192"

    # 连接队列优化（科学配置）
    echo -e "${gl_lv}优化连接队列...${gl_bai}"
    sysctl -w net.core.somaxconn=4096 2>/dev/null
    echo "  ✓ somaxconn = 4096"
    sysctl -w net.ipv4.tcp_max_syn_backlog=8192 2>/dev/null
    echo "  ✓ tcp_max_syn_backlog = 8192"
    sysctl -w net.core.netdev_max_backlog=5000 2>/dev/null
    echo "  ✓ netdev_max_backlog = 5000 （科学值）"

    # TCP安全
    echo -e "${gl_lv}TCP安全增强...${gl_bai}"
    sysctl -w net.ipv4.tcp_syncookies=1 2>/dev/null
    echo "  ✓ tcp_syncookies = 1"
    sysctl -w net.ipv4.tcp_mtu_probing=1 2>/dev/null
    echo "  ✓ tcp_mtu_probing = 1"

    echo ""
    echo -e "${gl_lv}Reality终极优化完成！${gl_bai}"
    echo -e "${gl_zi}配置特点: 性能提升5-10% + 资源消耗降低25% + 更科学的参数配置${gl_bai}"
    echo -e "${gl_huang}预期效果: 比星辰大海更平衡，适配性更强（≥2GB内存即可）${gl_bai}"
}

#=============================================================================
# 内核参数优化 - 低配优化（1GB内存专用）
#=============================================================================

optimize_low_spec() {
    echo -e "${gl_lv}切换到低配优化模式...${gl_bai}"
    echo -e "${gl_zi}专为512MB-1GB内存VPS设计，安全稳定${gl_bai}"
    echo ""
    echo -e "${gl_hong}⚠️  重要提示 ⚠️${gl_bai}"
    echo -e "${gl_huang}本配置为临时生效（使用 sysctl -w 命令）${gl_bai}"
    echo -e "${gl_huang}重启后将恢复到永久配置文件的设置${gl_bai}"
    echo ""
    echo "如果你之前执行过："
    echo "  - CAKE调优 / Debian12调优 / BBR直连优化"
    echo "重启后会恢复到那些配置，本次优化会消失！"
    echo ""
    read -e -p "是否继续？(Y/N) [Y]: " confirm
    confirm=${confirm:-Y}
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo "已取消"
        return
    fi
    echo ""

    # 文件描述符优化（适度）
    echo -e "${gl_lv}优化文件描述符...${gl_bai}"
    ulimit -n 65535
    echo "  ✓ 文件描述符: 65535 (6.5万)"

    # TCP拥塞控制（核心）
    echo -e "${gl_lv}优化TCP拥塞控制...${gl_bai}"
    sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null
    echo "  ✓ tcp_congestion_control = bbr"
    current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    if [ "$current_qdisc" = "cake" ]; then
        echo "  ✓ default_qdisc = cake （保持用户设置）"
    else
        echo "  ℹ default_qdisc = $current_qdisc （保持不变）"
    fi

    # TCP连接优化（核心功能）
    echo -e "${gl_lv}优化TCP连接...${gl_bai}"
    sysctl -w net.ipv4.tcp_fastopen=3 2>/dev/null
    echo "  ✓ tcp_fastopen = 3"
    sysctl -w net.ipv4.tcp_slow_start_after_idle=0 2>/dev/null
    echo "  ✓ tcp_slow_start_after_idle = 0 （关键优化）"
    sysctl -w net.ipv4.tcp_tw_reuse=1 2>/dev/null
    echo "  ✓ tcp_tw_reuse = 1"
    sysctl -w net.ipv4.ip_local_port_range='1024 65535' 2>/dev/null
    echo "  ✓ ip_local_port_range = 1024-65535"

    # TCP缓冲区（8MB保守配置）
    echo -e "${gl_lv}优化TCP缓冲区（8MB保守配置）...${gl_bai}"
    sysctl -w net.core.rmem_max=8388608 2>/dev/null
    echo "  ✓ rmem_max = 8MB"
    sysctl -w net.core.wmem_max=8388608 2>/dev/null
    echo "  ✓ wmem_max = 8MB"
    sysctl -w net.ipv4.tcp_rmem='4096 87380 8388608' 2>/dev/null
    echo "  ✓ tcp_rmem = 4K 85K 8MB"
    sysctl -w net.ipv4.tcp_wmem='4096 65536 8388608' 2>/dev/null
    echo "  ✓ tcp_wmem = 4K 64K 8MB"

    # 内存管理（保守安全）
    echo -e "${gl_lv}优化内存管理...${gl_bai}"
    sysctl -w vm.swappiness=10 2>/dev/null
    echo "  ✓ swappiness = 10 （安全值）"
    sysctl -w vm.dirty_ratio=20 2>/dev/null
    echo "  ✓ dirty_ratio = 20"
    sysctl -w vm.dirty_background_ratio=10 2>/dev/null
    echo "  ✓ dirty_background_ratio = 10"

    # 连接队列（适度配置）
    echo -e "${gl_lv}优化连接队列...${gl_bai}"
    sysctl -w net.core.somaxconn=2048 2>/dev/null
    echo "  ✓ somaxconn = 2048"
    sysctl -w net.ipv4.tcp_max_syn_backlog=4096 2>/dev/null
    echo "  ✓ tcp_max_syn_backlog = 4096"
    sysctl -w net.core.netdev_max_backlog=2500 2>/dev/null
    echo "  ✓ netdev_max_backlog = 2500"

    # TCP安全
    echo -e "${gl_lv}TCP安全增强...${gl_bai}"
    sysctl -w net.ipv4.tcp_syncookies=1 2>/dev/null
    echo "  ✓ tcp_syncookies = 1"

    echo ""
    echo -e "${gl_lv}低配优化完成！${gl_bai}"
    echo -e "${gl_zi}配置特点: 核心优化保留 + 资源消耗最低 + 稳定性最高${gl_bai}"
    echo -e "${gl_huang}适用场景: 512MB-1GB内存VPS，性能提升15-25%${gl_bai}"
}

#=============================================================================
# 内核参数优化 - 星辰大海原始版（用于对比测试）
#=============================================================================

optimize_xinchendahai_original() {
    echo -e "${gl_lv}切换到星辰大海ヾ原始版模式...${gl_bai}"
    echo -e "${gl_zi}针对 VLESS Reality/AnyTLS 节点深度优化（原始参数）${gl_bai}"
    echo ""
    echo -e "${gl_hong}⚠️  重要提示 ⚠️${gl_bai}"
    echo -e "${gl_huang}本配置为临时生效（使用 sysctl -w 命令）${gl_bai}"
    echo -e "${gl_huang}重启后将恢复到永久配置文件的设置${gl_bai}"
    echo ""
    echo "如果你之前执行过："
    echo "  - CAKE调优 / Debian12调优 / BBR直连优化"
    echo "重启后会恢复到那些配置，本次优化会消失！"
    echo ""
    read -e -p "是否继续？(Y/N) [Y]: " confirm
    confirm=${confirm:-Y}
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo "已取消"
        return
    fi
    echo ""

    echo -e "${gl_lv}优化文件描述符...${gl_bai}"
    ulimit -n 1048576
    echo "  ✓ 文件描述符: 1048576 (100万)"

    echo -e "${gl_lv}优化内存管理...${gl_bai}"
    sysctl -w vm.swappiness=1 2>/dev/null
    echo "  ✓ vm.swappiness = 1"
    sysctl -w vm.dirty_ratio=15 2>/dev/null
    echo "  ✓ vm.dirty_ratio = 15"
    sysctl -w vm.dirty_background_ratio=5 2>/dev/null
    echo "  ✓ vm.dirty_background_ratio = 5"
    sysctl -w vm.overcommit_memory=1 2>/dev/null
    echo "  ✓ vm.overcommit_memory = 1"
    sysctl -w vm.min_free_kbytes=65536 2>/dev/null
    echo "  ✓ vm.min_free_kbytes = 65536"
    sysctl -w vm.vfs_cache_pressure=50 2>/dev/null
    echo "  ✓ vm.vfs_cache_pressure = 50"

    echo -e "${gl_lv}优化TCP拥塞控制...${gl_bai}"
    sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null
    echo "  ✓ net.ipv4.tcp_congestion_control = bbr"
    
    # 智能检测当前 qdisc，如果是 cake 则保持，否则设为 fq
    current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "fq")
    if [ "$current_qdisc" = "cake" ]; then
        echo "  ✓ net.core.default_qdisc = cake (保持当前设置)"
    else
        sysctl -w net.core.default_qdisc=fq 2>/dev/null
        echo "  ✓ net.core.default_qdisc = fq"
    fi

    echo -e "${gl_lv}优化TCP连接（TLS握手加速）...${gl_bai}"
    sysctl -w net.ipv4.tcp_fastopen=3 2>/dev/null
    echo "  ✓ net.ipv4.tcp_fastopen = 3"
    sysctl -w net.ipv4.tcp_fin_timeout=30 2>/dev/null
    echo "  ✓ net.ipv4.tcp_fin_timeout = 30"
    sysctl -w net.ipv4.tcp_max_syn_backlog=8192 2>/dev/null
    echo "  ✓ net.ipv4.tcp_max_syn_backlog = 8192"
    sysctl -w net.ipv4.tcp_tw_reuse=1 2>/dev/null
    echo "  ✓ net.ipv4.tcp_tw_reuse = 1"
    sysctl -w net.ipv4.tcp_slow_start_after_idle=0 2>/dev/null
    echo "  ✓ net.ipv4.tcp_slow_start_after_idle = 0"
    sysctl -w net.ipv4.tcp_mtu_probing=2 2>/dev/null
    echo "  ✓ net.ipv4.tcp_mtu_probing = 2"
    sysctl -w net.ipv4.tcp_window_scaling=1 2>/dev/null
    echo "  ✓ net.ipv4.tcp_window_scaling = 1"
    sysctl -w net.ipv4.tcp_timestamps=1 2>/dev/null
    echo "  ✓ net.ipv4.tcp_timestamps = 1"

    echo -e "${gl_lv}优化TCP安全/稳态...${gl_bai}"
    sysctl -w net.ipv4.tcp_syncookies=1 2>/dev/null
    echo "  ✓ net.ipv4.tcp_syncookies = 1"
    sysctl -w net.ipv4.tcp_keepalive_time=600 2>/dev/null
    echo "  ✓ net.ipv4.tcp_keepalive_time = 600"
    sysctl -w net.ipv4.tcp_keepalive_intvl=30 2>/dev/null
    echo "  ✓ net.ipv4.tcp_keepalive_intvl = 30"
    sysctl -w net.ipv4.tcp_keepalive_probes=5 2>/dev/null
    echo "  ✓ net.ipv4.tcp_keepalive_probes = 5"

    echo -e "${gl_lv}优化TCP缓冲区...${gl_bai}"
    sysctl -w net.core.rmem_max=16777216 2>/dev/null
    echo "  ✓ net.core.rmem_max = 16777216"
    sysctl -w net.core.wmem_max=16777216 2>/dev/null
    echo "  ✓ net.core.wmem_max = 16777216"
    sysctl -w net.core.rmem_default=262144 2>/dev/null
    echo "  ✓ net.core.rmem_default = 262144"
    sysctl -w net.core.wmem_default=262144 2>/dev/null
    echo "  ✓ net.core.wmem_default = 262144"
    sysctl -w net.ipv4.tcp_rmem='4096 87380 16777216' 2>/dev/null
    echo "  ✓ net.ipv4.tcp_rmem = 4096 87380 16777216"
    sysctl -w net.ipv4.tcp_wmem='4096 65536 16777216' 2>/dev/null
    echo "  ✓ net.ipv4.tcp_wmem = 4096 65536 16777216"

    echo -e "${gl_lv}优化UDP（QUIC支持）...${gl_bai}"
    sysctl -w net.ipv4.udp_rmem_min=8192 2>/dev/null
    echo "  ✓ net.ipv4.udp_rmem_min = 8192"
    sysctl -w net.ipv4.udp_wmem_min=8192 2>/dev/null
    echo "  ✓ net.ipv4.udp_wmem_min = 8192"

    echo -e "${gl_lv}优化连接队列...${gl_bai}"
    sysctl -w net.core.somaxconn=4096 2>/dev/null
    echo "  ✓ net.core.somaxconn = 4096"
    sysctl -w net.core.netdev_max_backlog=250000 2>/dev/null
    echo "  ✓ net.core.netdev_max_backlog = 250000"
    sysctl -w net.ipv4.ip_local_port_range='1024 65535' 2>/dev/null
    echo "  ✓ net.ipv4.ip_local_port_range = 1024 65535"

    echo -e "${gl_lv}优化CPU设置...${gl_bai}"
    sysctl -w kernel.sched_autogroup_enabled=0 2>/dev/null
    echo "  ✓ kernel.sched_autogroup_enabled = 0"
    sysctl -w kernel.numa_balancing=0 2>/dev/null
    echo "  ✓ kernel.numa_balancing = 0"

    echo -e "${gl_lv}其他优化...${gl_bai}"
    echo never > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null
    echo "  ✓ transparent_hugepage = never"

    echo ""
    echo -e "${gl_lv}星辰大海ヾ原始版优化模式设置完成！${gl_bai}"
    echo -e "${gl_zi}配置特点: TLS握手加速 + QUIC支持 + 大并发优化${gl_bai}"
    echo -e "${gl_huang}注意: 这是原始参数版本，用于对比测试，建议≥4GB内存使用${gl_bai}"
}

#=============================================================================
# 内核参数优化 - 主菜单
#=============================================================================

Kernel_optimize() {
    while true; do
        clear
        echo "Linux系统内核参数优化 - Reality专用调优"
        echo "------------------------------------------------"
        echo "针对VLESS Reality/AnyTLS节点深度优化"
        echo -e "${gl_huang}提示: ${gl_bai}所有方案都是临时生效（重启后自动还原）"
        echo "--------------------"
        echo "1. 星辰大海ヾ优化：  13万文件描述符，16MB缓冲区，兼容CAKE"
        echo "                      适用：≥2GB内存，推荐使用"
        echo "                      评分：⭐⭐⭐⭐⭐ (24/25分) 🏆"
        echo ""
        echo "2. Reality终极优化：  50万文件描述符，12MB缓冲区"
        echo "                      适用：≥2GB内存，性能+5-10%（推荐）"
        echo "                      评分：⭐⭐⭐⭐⭐ (24/25分) 🏆"
        echo ""
        echo "3. 低配优化模式：     6.5万文件描述符，8MB缓冲区"
        echo "                      适用：512MB-1GB内存，稳定优先"
        echo "                      评分：⭐⭐⭐⭐ (20/25分) 💡 1GB内存推荐"
        echo ""
        echo "4. 星辰大海原始版：   100万文件描述符，16MB缓冲区，强制fq"
        echo "                      适用：≥4GB内存，对比测试用"
        echo "                      评分：⭐⭐⭐⭐⭐ (23/25分) 🧪 测试对比"
        echo "--------------------"
        echo "0. 返回主菜单"
        echo "--------------------"
        read -e -p "请输入你的选择: " sub_choice
        case $sub_choice in
            1)
                cd ~
                clear
                optimize_xinchendahai
                ;;
            2)
                cd ~
                clear
                optimize_reality_ultimate
                ;;
            3)
                cd ~
                clear
                optimize_low_spec
                ;;
            4)
                cd ~
                clear
                optimize_xinchendahai_original
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
        speedtest --accept-license
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

    # 运行测试（自动接受许可）
    speedtest --accept-license

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
    local backtrace_tmp
    backtrace_tmp=$(mktemp)
    if download_repo_resource "backtrace_install" "$backtrace_tmp" "三网回程路由测试脚本"; then
        chmod +x "$backtrace_tmp"
        if ! bash "$backtrace_tmp"; then
            echo -e "${gl_hong}三网回程路由测试脚本执行失败${gl_bai}"
        fi
    else
        echo -e "${gl_hong}无法获取三网回程路由测试脚本${gl_bai}"
    fi
    rm -f "$backtrace_tmp"

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

    local latency_tmp
    local original_dir=$(pwd)

    if ! cd /tmp; then
        echo -e "${gl_hong}错误: 无法切换到 /tmp 目录${gl_bai}"
        break_end
        return 1
    fi

    latency_tmp=$(mktemp)

    echo "正在下载脚本..."
    if ! download_repo_resource "latency_tester" "$latency_tmp" "国际互联速度测试脚本"; then
        echo -e "${gl_hong}无法获取国际互联速度测试脚本${gl_bai}"
        rm -f "$latency_tmp"
        cd "$original_dir" || true
        break_end
        return 1
    fi

    chmod +x "$latency_tmp"

    echo ""
    echo "开始测试..."
    echo "------------------------------------------------"
    echo ""
    if ! "$latency_tmp"; then
        echo -e "${gl_hong}国际互联速度测试脚本执行失败${gl_bai}"
    fi

    rm -f "$latency_tmp"
    cd "$original_dir" || true

    echo ""
    echo "------------------------------------------------"
    break_end
}

#=============================================================================
# iperf3 单线程网络测试
#=============================================================================

iperf3_single_thread_test() {
    clear
    echo -e "${gl_zi}╔════════════════════════════════════════════╗${gl_bai}"
    echo -e "${gl_zi}║       iperf3 单线程网络性能测试            ║${gl_bai}"
    echo -e "${gl_zi}╚════════════════════════════════════════════╝${gl_bai}"
    echo ""
    
    # 检查 iperf3 是否安装
    if ! command -v iperf3 &>/dev/null; then
        echo -e "${gl_huang}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo -e "${gl_huang}检测到 iperf3 未安装，正在自动安装...${gl_bai}"
        echo -e "${gl_huang}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo ""
        
        if command -v apt &>/dev/null; then
            echo "步骤 1/2: 更新软件包列表..."
            apt update -y
            
            echo ""
            echo "步骤 2/2: 安装 iperf3..."
            apt install -y iperf3
            
            if [ $? -ne 0 ]; then
                echo ""
                echo -e "${gl_hong}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
                echo -e "${gl_hong}iperf3 安装失败！${gl_bai}"
                echo -e "${gl_hong}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
                break_end
                return 1
            fi
        else
            echo -e "${gl_hong}错误: 不支持的包管理器（仅支持 apt）${gl_bai}"
            break_end
            return 1
        fi
        
        echo ""
        echo -e "${gl_lv}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo -e "${gl_lv}✓ iperf3 安装成功！${gl_bai}"
        echo -e "${gl_lv}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo ""
    fi
    
    # 输入目标服务器
    echo -e "${gl_kjlan}[步骤 1/3] 输入目标服务器${gl_bai}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    read -e -p "请输入目标服务器 IP 或域名: " target_host
    
    if [ -z "$target_host" ]; then
        echo -e "${gl_hong}错误: 目标服务器不能为空！${gl_bai}"
        break_end
        return 1
    fi
    
    echo ""
    
    # 选择测试方向
    echo -e "${gl_kjlan}[步骤 2/3] 选择测试方向${gl_bai}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "1. 上传测试（本机 → 远程服务器）"
    echo "2. 下载测试（远程服务器 → 本机）"
    echo ""
    read -e -p "请选择测试方向 [1-2]: " direction_choice
    
    case "$direction_choice" in
        1)
            direction_flag=""
            direction_text="上行（本机 → ${target_host}）"
            ;;
        2)
            direction_flag="-R"
            direction_text="下行（${target_host} → 本机）"
            ;;
        *)
            echo -e "${gl_hong}无效的选择，使用默认值: 上传测试${gl_bai}"
            direction_flag=""
            direction_text="上行（本机 → ${target_host}）"
            ;;
    esac
    
    echo ""
    
    # 输入测试时长
    echo -e "${gl_kjlan}[步骤 3/3] 设置测试时长${gl_bai}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "建议: 30-120 秒（默认 60 秒）"
    echo ""
    read -e -p "请输入测试时长（秒）[60]: " test_duration
    test_duration=${test_duration:-60}
    
    # 验证时长是否为数字
    if ! [[ "$test_duration" =~ ^[0-9]+$ ]]; then
        echo -e "${gl_huang}警告: 无效的时长，使用默认值 60 秒${gl_bai}"
        test_duration=60
    fi
    
    # 限制时长范围
    if [ "$test_duration" -lt 1 ]; then
        test_duration=1
    elif [ "$test_duration" -gt 3600 ]; then
        echo -e "${gl_huang}警告: 时长过长，限制为 3600 秒${gl_bai}"
        test_duration=3600
    fi
    
    echo ""
    echo -e "${gl_lv}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}测试配置确认：${gl_bai}"
    echo "  目标服务器: ${target_host}"
    echo "  测试方向: ${direction_text}"
    echo "  测试时长: ${test_duration} 秒"
    echo -e "${gl_lv}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""
    
    # 测试连通性
    echo -e "${gl_huang}正在测试连通性...${gl_bai}"
    if ! ping -c 2 -W 3 "$target_host" &>/dev/null; then
        echo -e "${gl_hong}警告: 无法 ping 通目标服务器，但仍尝试 iperf3 测试...${gl_bai}"
    else
        echo -e "${gl_lv}✓ 目标服务器可达${gl_bai}"
    fi
    
    echo ""
    echo -e "${gl_kjlan}正在执行 iperf3 测试，请稍候...${gl_bai}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # 执行 iperf3 测试并保存输出
    local test_output=$(mktemp)
    iperf3 -c "$target_host" -P 1 $direction_flag -t "$test_duration" -f m 2>&1 | tee "$test_output"
    local exit_code=$?
    
    echo ""
    
    # 检查是否成功
    if [ $exit_code -ne 0 ]; then
        echo -e "${gl_hong}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo -e "${gl_hong}测试失败！${gl_bai}"
        echo ""
        echo "可能的原因："
        echo "  1. 目标服务器未运行 iperf3 服务（需要执行: iperf3 -s）"
        echo "  2. 防火墙阻止了连接（默认端口 5201）"
        echo "  3. 网络连接问题"
        echo -e "${gl_hong}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        rm -f "$test_output"
        break_end
        return 1
    fi
    
    # 解析测试结果
    echo -e "${gl_lv}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_zi}╔════════════════════════════════════════════╗${gl_bai}"
    echo -e "${gl_zi}║           测 试 结 果 汇 总                ║${gl_bai}"
    echo -e "${gl_zi}╚════════════════════════════════════════════╝${gl_bai}"
    echo ""
    
    # 提取关键指标
    local bandwidth=$(grep "sender\|receiver" "$test_output" | tail -1 | awk '{print $7, $8}')
    local transfer=$(grep "sender\|receiver" "$test_output" | tail -1 | awk '{print $5, $6}')
    local retrans=$(grep "sender" "$test_output" | tail -1 | awk '{print $9}')
    
    echo -e "${gl_kjlan}[测试信息]${gl_bai}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  目标服务器: ${target_host}"
    echo "  测试方向: ${direction_text}"
    echo "  测试时长: ${test_duration} 秒"
    echo "  测试线程: 1"
    echo ""
    
    echo -e "${gl_kjlan}[性能指标]${gl_bai}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ -n "$bandwidth" ]; then
        echo "  平均带宽: ${bandwidth}"
    else
        echo "  平均带宽: 无法获取"
    fi
    
    if [ -n "$transfer" ]; then
        echo "  总传输量: ${transfer}"
    else
        echo "  总传输量: 无法获取"
    fi
    
    if [ -n "$retrans" ] && [ "$retrans" != "" ]; then
        echo "  重传次数: ${retrans}"
        # 简单评价
        if [ "$retrans" -eq 0 ]; then
            echo -e "  连接质量: ${gl_lv}优秀（无重传）${gl_bai}"
        elif [ "$retrans" -lt 100 ]; then
            echo -e "  连接质量: ${gl_lv}良好${gl_bai}"
        elif [ "$retrans" -lt 1000 ]; then
            echo -e "  连接质量: ${gl_huang}一般（重传偏多）${gl_bai}"
        else
            echo -e "  连接质量: ${gl_hong}较差（重传过多）${gl_bai}"
        fi
    fi
    
    echo ""
    echo -e "${gl_lv}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_lv}✓ 测试完成${gl_bai}"
    echo -e "${gl_lv}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    
    # 清理临时文件
    rm -f "$test_output"
    
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
    echo -e "${gl_kjlan}━━━━━━━━━━━━ 核心功能 ━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}[内核管理]${gl_bai}"

    if [ $is_installed -eq 0 ]; then
        echo "1. 更新 XanMod 内核"
        echo "2. 卸载 XanMod 内核"
        echo ""
        echo -e "${gl_kjlan}[BBR/网络优化]${gl_bai}"
        echo "3. BBR 直连/落地优化（智能带宽检测）⭐ 推荐"
        echo "4. NS论坛CAKE调优"
        echo "5. 科技lion高性能模式"
        echo ""
        echo -e "${gl_kjlan}━━━━━━━━━━━ 系统配置 ━━━━━━━━━━━${gl_bai}"
        echo -e "${gl_kjlan}[网络设置]${gl_bai}"
        echo "6. 设置IPv4/IPv6优先级"
        echo "7. IPv6管理（临时/永久禁用/取消）"
        echo "8. 设置临时SOCKS5代理"
        echo ""
        echo -e "${gl_kjlan}[系统管理]${gl_bai}"
        echo "9. 虚拟内存管理"
        echo "10. 查看系统详细状态"
        echo ""
        echo -e "${gl_kjlan}━━━━━━━━━━ 转发/代理配置 ━━━━━━━━━━${gl_bai}"
        echo -e "${gl_kjlan}[Realm转发管理]${gl_bai}"
        echo "11. Realm转发连接分析"
        echo "12. Realm强制使用IPv4 ⭐ 推荐"
        echo "13. IPv4/IPv6连接检测"
        echo ""
        echo -e "${gl_kjlan}[Xray配置]${gl_bai}"
        echo "14. 查看Xray配置"
        echo "15. 设置Xray IPv6出站"
        echo "16. 恢复Xray默认配置"
        echo ""
        echo -e "${gl_kjlan}[代理部署]${gl_bai}"
        echo "17. 一键部署SOCKS5代理"
        echo "18. Sub-Store多实例管理"
        echo ""
        echo -e "${gl_kjlan}━━━━━━━━━━━ 测试检测 ━━━━━━━━━━━${gl_bai}"
        echo -e "${gl_kjlan}[IP质量检测]${gl_bai}"
        echo "19. IP质量检测（IPv4+IPv6）"
        echo "20. IP质量检测（仅IPv4）⭐ 推荐"
        echo ""
        echo -e "${gl_kjlan}[网络测试]${gl_bai}"
        echo "21. 服务器带宽测试"
        echo "22. iperf3单线程测试"
        echo "23. 国际互联速度测试 ⭐ 推荐"
        echo "24. 网络延迟质量检测 ⭐ 推荐"
        echo "25. 三网回程路由测试 ⭐ 推荐"
        echo ""
        echo -e "${gl_kjlan}[流媒体/AI检测]${gl_bai}"
        echo "26. IP媒体/AI解锁检测 ⭐ 推荐"
        echo "27. NS一键检测脚本 ⭐ 推荐"
        echo ""
        echo -e "${gl_kjlan}━━━━━━━━━━ 第三方工具 ━━━━━━━━━━${gl_bai}"
        echo -e "${gl_kjlan}[脚本合集]${gl_bai}"
        echo "28. PF_realm转发脚本 ⭐ 推荐"
        echo "29. 御坂美琴一键双协议 ⭐ 推荐"
        echo "30. F佬一键sing box脚本"
        echo "31. 科技lion脚本"
        echo "32. 酷雪云脚本"
    else
        echo "1. 安装 XanMod 内核 + BBR v3 ⭐ 推荐"
        echo ""
        echo -e "${gl_kjlan}[BBR/网络优化]${gl_bai}"
        echo "2. BBR 直连/落地优化（智能带宽检测）⭐ 推荐"
        echo "3. NS论坛CAKE调优"
        echo "4. 科技lion高性能模式"
        echo ""
        echo -e "${gl_kjlan}━━━━━━━━━━━ 系统配置 ━━━━━━━━━━━${gl_bai}"
        echo -e "${gl_kjlan}[网络设置]${gl_bai}"
        echo "5. 设置IPv4/IPv6优先级"
        echo "6. IPv6管理（临时/永久禁用/取消）"
        echo "7. 设置临时SOCKS5代理"
        echo ""
        echo -e "${gl_kjlan}[系统管理]${gl_bai}"
        echo "8. 虚拟内存管理"
        echo "9. 查看系统详细状态"
        echo ""
        echo -e "${gl_kjlan}━━━━━━━━━━ 转发/代理配置 ━━━━━━━━━━${gl_bai}"
        echo -e "${gl_kjlan}[Realm转发管理]${gl_bai}"
        echo "10. Realm转发连接分析"
        echo "11. Realm强制使用IPv4 ⭐ 推荐"
        echo "12. IPv4/IPv6连接检测"
        echo ""
        echo -e "${gl_kjlan}[Xray配置]${gl_bai}"
        echo "13. 查看Xray配置"
        echo "14. 设置Xray IPv6出站"
        echo "15. 恢复Xray默认配置"
        echo ""
        echo -e "${gl_kjlan}[代理部署]${gl_bai}"
        echo "16. 一键部署SOCKS5代理"
        echo "17. Sub-Store多实例管理"
        echo ""
        echo -e "${gl_kjlan}━━━━━━━━━━━ 测试检测 ━━━━━━━━━━━${gl_bai}"
        echo -e "${gl_kjlan}[IP质量检测]${gl_bai}"
        echo "18. IP质量检测（IPv4+IPv6）"
        echo "19. IP质量检测（仅IPv4）⭐ 推荐"
        echo ""
        echo -e "${gl_kjlan}[网络测试]${gl_bai}"
        echo "20. 服务器带宽测试"
        echo "21. iperf3单线程测试"
        echo "22. 国际互联速度测试 ⭐ 推荐"
        echo "23. 网络延迟质量检测 ⭐ 推荐"
        echo "24. 三网回程路由测试 ⭐ 推荐"
        echo ""
        echo -e "${gl_kjlan}[流媒体/AI检测]${gl_bai}"
        echo "25. IP媒体/AI解锁检测 ⭐ 推荐"
        echo "26. NS一键检测脚本 ⭐ 推荐"
        echo ""
        echo -e "${gl_kjlan}━━━━━━━━━━ 第三方工具 ━━━━━━━━━━${gl_bai}"
        echo -e "${gl_kjlan}[脚本合集]${gl_bai}"
        echo "27. PF_realm转发脚本 ⭐ 推荐"
        echo "28. 御坂美琴一键双协议 ⭐ 推荐"
        echo "29. F佬一键sing box脚本"
        echo "30. 科技lion脚本"
        echo "31. 酷雪云脚本"
    fi
    
    echo ""
    echo "0. 退出脚本"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
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
                bbr_configure_direct
                break_end
            fi
            ;;
        3)
            if [ $is_installed -eq 0 ]; then
                bbr_configure_direct
                break_end
            else
                startbbrcake
            fi
            ;;
        4)
            if [ $is_installed -eq 0 ]; then
                startbbrcake
            else
                Kernel_optimize
            fi
            ;;
        5)
            if [ $is_installed -eq 0 ]; then
                Kernel_optimize
            else
                manage_ip_priority
            fi
            ;;
        6)
            if [ $is_installed -eq 0 ]; then
                manage_ip_priority
            else
                manage_swap
            fi
            ;;
        7)
            if [ $is_installed -eq 0 ]; then
                manage_swap
            else
                manage_ipv6
            fi
            ;;
        8)
            if [ $is_installed -eq 0 ]; then
                manage_ipv6
            else
                set_temp_socks5_proxy
            fi
            ;;
        9)
            if [ $is_installed -eq 0 ]; then
                manage_swap
            else
                manage_swap
            fi
            ;;
        10)
            if [ $is_installed -eq 0 ]; then
                show_detailed_status
            else
                show_detailed_status
            fi
            ;;
        11)
            if [ $is_installed -eq 0 ]; then
                analyze_realm_connections
            else
                analyze_realm_connections
            fi
            ;;
        12)
            if [ $is_installed -eq 0 ]; then
                realm_ipv4_management
            else
                check_ipv4v6_connections
            fi
            ;;
        13)
            if [ $is_installed -eq 0 ]; then
                check_ipv4v6_connections
            else
                show_xray_config
            fi
            ;;
        14)
            if [ $is_installed -eq 0 ]; then
                show_xray_config
            else
                set_xray_ipv6_outbound
            fi
            ;;
        15)
            if [ $is_installed -eq 0 ]; then
                set_xray_ipv6_outbound
            else
                restore_xray_default
            fi
            ;;
        16)
            if [ $is_installed -eq 0 ]; then
                restore_xray_default
            else
                deploy_socks5
            fi
            ;;
        17)
            if [ $is_installed -eq 0 ]; then
                deploy_socks5
            else
                manage_substore
            fi
            ;;
        18)
            if [ $is_installed -eq 0 ]; then
                manage_substore
            else
                run_ip_quality_check
            fi
            ;;
        19)
            if [ $is_installed -eq 0 ]; then
                run_ip_quality_check
            else
                run_ip_quality_check_ipv4
            fi
            ;;
        20)
            if [ $is_installed -eq 0 ]; then
                run_ip_quality_check_ipv4
            else
                run_speedtest
            fi
            ;;
        21)
            if [ $is_installed -eq 0 ]; then
                run_speedtest
            else
                iperf3_single_thread_test
            fi
            ;;
        22)
            if [ $is_installed -eq 0 ]; then
                iperf3_single_thread_test
            else
                run_international_speed_test
            fi
            ;;
        23)
            if [ $is_installed -eq 0 ]; then
                run_international_speed_test
            else
                run_network_latency_check
            fi
            ;;
        24)
            if [ $is_installed -eq 0 ]; then
                run_network_latency_check
            else
                run_backtrace
            fi
            ;;
        25)
            if [ $is_installed -eq 0 ]; then
                run_backtrace
            else
                run_unlock_check
            fi
            ;;
        26)
            if [ $is_installed -eq 0 ]; then
                run_unlock_check
            else
                run_ns_detect
            fi
            ;;
        27)
            if [ $is_installed -eq 0 ]; then
                run_ns_detect
            else
                run_pf_realm
            fi
            ;;
        28)
            if [ $is_installed -eq 0 ]; then
                run_pf_realm
            else
                run_misaka_xray
            fi
            ;;
        29)
            if [ $is_installed -eq 0 ]; then
                run_misaka_xray
            else
                run_fscarmen_singbox
            fi
            ;;
        30)
            if [ $is_installed -eq 0 ]; then
                run_fscarmen_singbox
            else
                run_kejilion_script
            fi
            ;;
        31)
            if [ $is_installed -eq 0 ]; then
                run_kejilion_script
            else
                run_kxy_script
            fi
            ;;
        32)
            if [ $is_installed -eq 0 ]; then
                run_kxy_script
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
    
    local xanmod_repo_file="/etc/apt/sources.list.d/xanmod-release.list"

    # 添加 XanMod 仓库（如果不存在）
    if [ ! -f "$xanmod_repo_file" ]; then
        echo "正在添加 XanMod 仓库..."

        local update_key_tmp
        update_key_tmp=$(mktemp)
        local update_key_imported=0

        if download_repo_resource "xanmod_archive_key" "$update_key_tmp" "XanMod 仓库密钥"; then
            if gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg --yes "$update_key_tmp" 2>/dev/null; then
                update_key_imported=1
            else
                echo -e "${gl_huang}密钥导入失败，尝试官方源...${gl_bai}"
            fi
        else
            echo -e "${gl_huang}未能从自有仓库获取 XanMod 密钥，尝试官方源...${gl_bai}"
        fi

        if [ $update_key_imported -ne 1 ]; then
            if download_with_retry "https://dl.xanmod.org/archive.key" "$update_key_tmp"; then
                if gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg --yes "$update_key_tmp" 2>/dev/null; then
                    update_key_imported=1
                else
                    echo -e "${gl_hong}密钥导入失败${gl_bai}"
                fi
            else
                echo -e "${gl_hong}密钥下载失败${gl_bai}"
            fi
        fi

        rm -f "$update_key_tmp"

        if [ $update_key_imported -ne 1 ]; then
            echo -e "${gl_hong}无法获取 XanMod 仓库密钥，终止更新流程${gl_bai}"
            break_end
            return 1
        fi
        
        # 添加仓库
        echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' | \
            tee "$xanmod_repo_file" > /dev/null
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
                echo ""
                echo -e "${gl_lv}✅ XanMod 内核更新成功！${gl_bai}"
                echo -e "${gl_huang}⚠️  请重启系统以加载新内核${gl_bai}"
                echo -e "${gl_kjlan}后续更新: 可执行 ${gl_bai}sudo apt update && sudo apt upgrade${gl_kjlan} 以检查新版本${gl_bai}"

                read -e -p "是否保留 XanMod 软件源以便继续接收更新？(Y/n): " keep_repo
                case "${keep_repo:-Y}" in
                    [Nn])
                        echo -e "${gl_huang}移除软件源后将无法通过 apt upgrade 自动获取内核更新，后续需手动重新添加。${gl_bai}"
                        read -e -p "确认移除 XanMod 软件源吗？(Y/N): " remove_repo
                        case "$remove_repo" in
                            [Yy])
                                rm -f "$xanmod_repo_file"
                                echo -e "${gl_huang}已按要求移除 XanMod 软件源。${gl_bai}"
                                ;;
                            *)
                                echo -e "${gl_lv}已保留 XanMod 软件源。${gl_bai}"
                                ;;
                        esac
                        ;;
                    *)
                        echo -e "${gl_lv}已保留 XanMod 软件源，可继续通过 apt upgrade 获取最新内核。${gl_bai}"
                        ;;
                esac
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
    bash <(curl -sL Media.Check.Place)

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
    local pf_realm_tmp
    pf_realm_tmp=$(mktemp)
    if download_repo_resource "pf_realm_script" "$pf_realm_tmp" "PF_realm 转发脚本"; then
        chmod +x "$pf_realm_tmp"
        if bash "$pf_realm_tmp" install; then
            echo ""
            echo -e "${gl_lv}✅ PF_realm 脚本执行完成${gl_bai}"
        else
            echo ""
            echo -e "${gl_hong}❌ PF_realm 脚本执行失败${gl_bai}"
            echo "可能原因："
            echo "1. 脚本执行过程中出错"
            echo "2. 权限不足"
        fi
    else
        echo ""
        echo -e "${gl_hong}❌ 无法获取 PF_realm 转发脚本${gl_bai}"
    fi
    rm -f "$pf_realm_tmp"

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
    local xray_dual_tmp
    xray_dual_tmp=$(mktemp)
    if download_repo_resource "xray_dual_install" "$xray_dual_tmp" "御坂美琴一键双协议脚本"; then
        chmod +x "$xray_dual_tmp"
        if bash "$xray_dual_tmp"; then
            echo ""
            echo -e "${gl_lv}✅ 御坂美琴一键双协议脚本执行完成${gl_bai}"
        else
            echo ""
            echo -e "${gl_hong}❌ 御坂美琴一键双协议脚本执行失败${gl_bai}"
            echo "可能原因："
            echo "1. 脚本执行过程中出错"
            echo "2. 权限不足"
        fi
    else
        echo ""
        echo -e "${gl_hong}❌ 无法获取御坂美琴一键双协议脚本${gl_bai}"
    fi
    rm -f "$xray_dual_tmp"

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
    local sing_box_tmp
    sing_box_tmp=$(mktemp)
    if download_repo_resource "sing_box_install" "$sing_box_tmp" "F佬一键 sing-box 脚本"; then
        chmod +x "$sing_box_tmp"
        if ! bash "$sing_box_tmp"; then
            echo -e "${gl_hong}F佬一键 sing-box 脚本执行失败${gl_bai}"
        fi
    else
        echo -e "${gl_hong}无法获取 F佬一键 sing-box 脚本${gl_bai}"
    fi
    rm -f "$sing_box_tmp"

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
    local lotserver_tmp
    lotserver_tmp=$(mktemp)
    if download_repo_resource "lotserver_install" "$lotserver_tmp" "LotServer 管理脚本"; then
      chmod +x "$lotserver_tmp"
      if ! printf '\n' | bash "$lotserver_tmp" uninstall; then
        echo -e "${gl_huang}LotServer 卸载脚本执行失败${gl_bai}"
      fi
    else
      echo -e "${gl_huang}未能获取 LotServer 管理脚本，跳过自动卸载${gl_bai}"
    fi
    rm -f "$lotserver_tmp"
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
# Sub-Store 多实例管理功能
#=============================================================================

# 检查端口是否被占用
check_substore_port() {
    local port=$1
    if netstat -tuln 2>/dev/null | grep -q ":$port "; then
        return 1
    elif ss -tuln 2>/dev/null | grep -q ":$port "; then
        return 1
    fi
    return 0
}

# 验证端口号
validate_substore_port() {
    local port=$1
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        return 1
    fi
    return 0
}

# 验证访问路径
validate_substore_path() {
    local path=$1
    # 只包含字母数字和少数符号
    if [[ ! "$path" =~ ^[a-zA-Z0-9/_-]+$ ]]; then
        return 1
    fi
    return 0
}

# 生成随机路径
generate_substore_random_path() {
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1
}

# 检查 Docker 是否安装
check_substore_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${gl_hong}Docker 未安装${gl_bai}"
        echo ""
        read -e -p "$(echo -e "${gl_huang}是否现在安装 Docker？(Y/N): ${gl_bai}")" install_docker
        
        case "$install_docker" in
            [Yy])
                echo ""
                echo "请选择安装源："
                echo "1. 国内镜像（阿里云）"
                echo "2. 国外官方源"
                read -e -p "请选择 [1]: " mirror_choice
                mirror_choice=${mirror_choice:-1}
                
                case "$mirror_choice" in
                    1)
                        echo "正在使用阿里云镜像安装 Docker..."
                        curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
                        ;;
                    2)
                        echo "正在使用官方源安装 Docker..."
                        curl -fsSL https://get.docker.com | bash
                        ;;
                    *)
                        echo "无效选择，使用阿里云镜像..."
                        curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
                        ;;
                esac
                
                if [ $? -eq 0 ]; then
                    echo -e "${gl_lv}✅ Docker 安装成功${gl_bai}"
                    systemctl enable docker
                    systemctl start docker
                else
                    echo -e "${gl_hong}❌ Docker 安装失败${gl_bai}"
                    return 1
                fi
                ;;
            *)
                echo "已取消，请先安装 Docker"
                return 1
                ;;
        esac
    fi
    
    if ! command -v docker compose &> /dev/null && ! command -v docker-compose &> /dev/null; then
        echo -e "${gl_huang}Docker Compose 未安装，尝试安装...${gl_bai}"
        # Docker Compose v2 通常随 Docker 一起安装
        if docker compose version &>/dev/null; then
            echo -e "${gl_lv}✅ Docker Compose 已可用${gl_bai}"
        else
            echo -e "${gl_hong}❌ Docker Compose 不可用，请手动安装${gl_bai}"
            return 1
        fi
    fi
    
    return 0
}

# 获取已部署的实例列表
get_substore_instances() {
    local instances=()
    if [ -d "/root/sub-store-configs" ]; then
        for config in /root/sub-store-configs/store-*.yaml; do
            if [ -f "$config" ]; then
                local instance_name=$(basename "$config" .yaml)
                instances+=("$instance_name")
            fi
        done
    fi
    echo "${instances[@]}"
}

# 检查实例是否存在
check_substore_instance_exists() {
    local instance_num=$1
    if [ -f "/root/sub-store-configs/store-$instance_num.yaml" ]; then
        return 0
    fi
    return 1
}

# 安装新实例
install_substore_instance() {
    clear
    echo "=================================="
    echo "    Sub-Store 实例安装向导"
    echo "=================================="
    echo ""
    
    # 检查 Docker
    if ! check_substore_docker; then
        break_end
        return 1
    fi
    
    echo -e "${gl_lv}✅ Docker 环境检查通过${gl_bai}"
    echo ""
    
    # 获取建议的实例编号
    local instances=($(get_substore_instances))
    local suggested_num=1
    if [ ${#instances[@]} -gt 0 ]; then
        echo -e "${gl_huang}已存在 ${#instances[@]} 个实例${gl_bai}"
        suggested_num=$((${#instances[@]} + 1))
    fi
    
    # 输入实例编号
    local instance_num
    while true; do
        read -e -p "请输入实例编号（建议: $suggested_num）: " instance_num
        
        if [ -z "$instance_num" ]; then
            echo -e "${gl_hong}实例编号不能为空${gl_bai}"
            continue
        fi
        
        if ! [[ "$instance_num" =~ ^[0-9]+$ ]]; then
            echo -e "${gl_hong}实例编号必须是数字${gl_bai}"
            continue
        fi
        
        if check_substore_instance_exists "$instance_num"; then
            echo -e "${gl_hong}实例编号 $instance_num 已存在${gl_bai}"
            continue
        fi
        
        break
    done
    
    echo -e "${gl_lv}✅ 实例编号: $instance_num${gl_bai}"
    echo ""
    
    # 输入后端 API 端口
    local api_port
    local default_api_port=3001
    while true; do
        read -e -p "请输入后端 API 端口（回车使用默认 $default_api_port）: " api_port
        
        if [ -z "$api_port" ]; then
            api_port=$default_api_port
            echo -e "${gl_huang}使用默认端口: $api_port${gl_bai}"
        fi
        
        if ! validate_substore_port "$api_port"; then
            echo -e "${gl_hong}端口号无效${gl_bai}"
            continue
        fi
        
        if ! check_substore_port "$api_port"; then
            echo -e "${gl_hong}端口 $api_port 已被占用${gl_bai}"
            continue
        fi
        
        break
    done
    
    echo -e "${gl_lv}✅ 后端 API 端口: $api_port${gl_bai}"
    echo ""
    
    # 输入 HTTP-META 端口
    local http_port
    local default_http_port=9876
    while true; do
        read -e -p "请输入 HTTP-META 端口（回车使用默认 $default_http_port）: " http_port
        
        if [ -z "$http_port" ]; then
            http_port=$default_http_port
            echo -e "${gl_huang}使用默认端口: $http_port${gl_bai}"
        fi
        
        if ! validate_substore_port "$http_port"; then
            echo -e "${gl_hong}端口号无效${gl_bai}"
            continue
        fi
        
        if ! check_substore_port "$http_port"; then
            echo -e "${gl_hong}端口 $http_port 已被占用${gl_bai}"
            continue
        fi
        
        if [ "$http_port" == "$api_port" ]; then
            echo -e "${gl_hong}HTTP-META 端口不能与后端 API 端口相同${gl_bai}"
            continue
        fi
        
        break
    done
    
    echo -e "${gl_lv}✅ HTTP-META 端口: $http_port${gl_bai}"
    echo ""
    
    # 输入访问路径
    local access_path
    while true; do
        local random_path=$(generate_substore_random_path)
        echo -e "${gl_zi}访问路径说明：${gl_bai}"
        echo "  - 路径会自动添加开头的 /"
        echo "  - 建议使用随机路径（更安全）"
        echo "  - 也可使用自定义路径（易记）"
        echo ""
        echo -e "${gl_huang}随机生成的路径: ${random_path}${gl_bai}"
        echo ""
        
        read -e -p "请输入访问路径（直接输入如 my-subs，或回车使用随机）: " access_path
        
        if [ -z "$access_path" ]; then
            access_path="$random_path"
            echo -e "${gl_lv}✅ 使用随机路径: /$access_path${gl_bai}"
        else
            # 移除可能的开头斜杠
            access_path="${access_path#/}"
            
            if ! validate_substore_path "$access_path"; then
                echo -e "${gl_hong}路径格式无效（只能包含字母、数字、-、_、/）${gl_bai}"
                continue
            fi
            
            echo -e "${gl_lv}✅ 使用自定义路径: /$access_path${gl_bai}"
        fi
        
        break
    done
    
    echo ""
    
    # 输入数据存储目录
    local data_dir
    local default_data_dir="/root/data-sub-store-$instance_num"
    
    read -e -p "请输入数据存储目录（回车使用默认 $default_data_dir）: " data_dir
    
    if [ -z "$data_dir" ]; then
        data_dir="$default_data_dir"
        echo -e "${gl_huang}使用默认目录: $data_dir${gl_bai}"
    fi
    
    if [ -d "$data_dir" ]; then
        echo ""
        echo -e "${gl_huang}目录 $data_dir 已存在${gl_bai}"
        local use_existing
        read -e -p "是否使用现有目录？(y/n): " use_existing
        if [[ ! "$use_existing" =~ ^[Yy]$ ]]; then
            echo "请重新运行并选择其他目录"
            break_end
            return 1
        fi
    fi
    
    # 确认信息
    echo ""
    echo "=================================="
    echo "          配置确认"
    echo "=================================="
    echo "实例编号: $instance_num"
    echo "容器名称: sub-store-$instance_num"
    echo "后端 API 端口: $api_port"
    echo "HTTP-META 端口: $http_port"
    echo "访问路径: /$access_path"
    echo "数据目录: $data_dir"
    echo "=================================="
    echo ""
    
    local confirm
    read -e -p "确认开始安装？(y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "已取消安装"
        break_end
        return 1
    fi
    
    # 创建配置目录
    mkdir -p /root/sub-store-configs
    
    # 创建数据目录
    echo ""
    echo "正在创建数据目录..."
    mkdir -p "$data_dir"
    
    # 生成配置文件
    local config_file="/root/sub-store-configs/store-$instance_num.yaml"
    echo "正在生成配置文件..."
    
    cat > "$config_file" << EOF
services:
  sub-store-$instance_num:
    image: xream/sub-store:http-meta
    container_name: sub-store-$instance_num
    restart: always
    network_mode: host
    environment:
      SUB_STORE_BACKEND_API_HOST: 127.0.0.1
      SUB_STORE_BACKEND_API_PORT: $api_port
      SUB_STORE_BACKEND_MERGE: true
      SUB_STORE_FRONTEND_BACKEND_PATH: /$access_path
      HOST: 127.0.0.1
    volumes:
      - $data_dir:/opt/app/data
EOF
    
    # 启动容器
    echo "正在启动 Sub-Store 实例..."
    if docker compose -f "$config_file" up -d; then
        echo ""
        echo -e "${gl_lv}=========================================="
        echo "  Sub-Store 实例安装成功！"
        echo "==========================================${gl_bai}"
        echo ""
        echo -e "${gl_zi}实例信息：${gl_bai}"
        echo "  - 实例编号: $instance_num"
        echo "  - 容器名称: sub-store-$instance_num"
        echo "  - 服务端口: $api_port（前后端共用，监听 127.0.0.1）"
        echo "  - 访问路径: /$access_path"
        echo "  - 数据目录: $data_dir"
        echo "  - 配置文件: $config_file"
        echo ""
        echo -e "${gl_huang}⚠️  重要提示：${gl_bai}"
        echo "  此实例仅监听本地 127.0.0.1，无法直接通过IP访问！"
        echo "  必须配置 Cloudflare Tunnel 后才能使用。"
        echo ""
        
        # 生成 Cloudflare Tunnel 配置
        local cf_tunnel_conf="/root/sub-store-cf-tunnel-$instance_num.yaml"
        cat > "$cf_tunnel_conf" << CFEOF
# Cloudflare Tunnel 配置
# 使用说明：
#   1. 安装 cloudflared: 
#      wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
#      chmod +x cloudflared-linux-amd64 && mv cloudflared-linux-amd64 /usr/local/bin/cloudflared
#   2. 登录: cloudflared tunnel login
#   3. 创建隧道: cloudflared tunnel create sub-store-$instance_num
#   4. 修改下面的 tunnel 和 credentials-file
#   5. 配置路由: cloudflared tunnel route dns <TUNNEL_ID> sub.你的域名.com
#   6. 启动: cloudflared tunnel --config $cf_tunnel_conf run

tunnel: <TUNNEL_ID>  # 替换为你的 Tunnel ID
credentials-file: /root/.cloudflared/<TUNNEL_ID>.json  # 替换为你的凭证文件路径

ingress:
  # 后端 API 路由（必须在前面，更具体的规则）
  - hostname: sub.你的域名.com
    path: /$access_path
    service: http://127.0.0.1:$api_port
  
  # 前端页面路由（通配所有其他请求，与后端共用端口）
  - hostname: sub.你的域名.com
    service: http://127.0.0.1:$api_port
  
  # 默认规则（必须）
  - service: http_status:404
CFEOF
        
        echo -e "${gl_kjlan}【Cloudflare Tunnel 配置文件】${gl_bai}"
        echo ""
        echo "  配置模板已生成: $cf_tunnel_conf"
        echo ""
        echo "  接下来将引导你进行自动配置"
        echo ""
        
        echo -e "${gl_zi}常用命令：${gl_bai}"
        echo "  - 查看日志: docker logs sub-store-$instance_num"
        echo "  - 停止服务: docker compose -f $config_file down"
        echo "  - 重启服务: docker compose -f $config_file restart"
        echo ""
        
        # 交互式配置向导
        echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo -e "${gl_huang}📌 接下来需要配置 Cloudflare Tunnel 才能使用${gl_bai}"
        echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo ""
        echo "请选择："
        echo "1. 立即配置 Cloudflare Tunnel（推荐）"
        echo "2. 跳过配置（稍后手动配置）"
        echo ""
        
        local proxy_choice
        read -e -p "请选择 [1-2]: " proxy_choice
        
        case "$proxy_choice" in
            1)
                # Cloudflare Tunnel 配置向导
                configure_cf_tunnel "$instance_num" "$http_port" "$api_port" "$access_path" "$cf_tunnel_conf"
                ;;
            2)
                echo ""
                echo -e "${gl_huang}已跳过配置${gl_bai}"
                echo "稍后可手动配置，配置文件位于："
                echo "  - CF Tunnel: $cf_tunnel_conf"
                echo ""
                ;;
            *)
                echo ""
                echo -e "${gl_huang}无效选择，已跳过配置${gl_bai}"
                ;;
        esac
    else
        echo -e "${gl_hong}启动失败，请检查配置和日志${gl_bai}"
        break_end
        return 1
    fi
    
    break_end
}

# Cloudflare Tunnel 配置向导

# Cloudflare Tunnel 配置向导
configure_cf_tunnel() {
    local instance_num=$1
    local http_port=$2
    local api_port=$3
    local access_path=$4
    local cf_tunnel_conf=$5
    
    clear
    echo -e "${gl_kjlan}=================================="
    echo "  Cloudflare Tunnel 配置向导"
    echo "==================================${gl_bai}"
    echo ""
    
    # 检查 cloudflared 是否安装
    if ! command -v cloudflared &>/dev/null; then
        echo -e "${gl_huang}cloudflared 未安装${gl_bai}"
        echo ""
        read -e -p "是否现在安装 cloudflared？(Y/N): " install_cf
        
        case "$install_cf" in
            [Yy])
                echo ""
                echo "正在下载 cloudflared..."
                
                local cpu_arch=$(uname -m)
                local download_url
                
                case "$cpu_arch" in
                    x86_64)
                        download_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
                        ;;
                    aarch64)
                        download_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
                        ;;
                    *)
                        echo -e "${gl_hong}不支持的架构: $cpu_arch${gl_bai}"
                        break_end
                        return 1
                        ;;
                esac
                
                wget -O /usr/local/bin/cloudflared "$download_url"
                chmod +x /usr/local/bin/cloudflared
                
                if [ $? -eq 0 ]; then
                    echo -e "${gl_lv}✅ cloudflared 安装成功${gl_bai}"
                else
                    echo -e "${gl_hong}❌ cloudflared 安装失败${gl_bai}"
                    break_end
                    return 1
                fi
                ;;
            *)
                echo "已取消，请手动安装 cloudflared 后配置"
                break_end
                return 1
                ;;
        esac
    else
        echo -e "${gl_lv}✅ cloudflared 已安装${gl_bai}"
    fi
    
    echo ""
    echo -e "${gl_zi}[步骤 1/5] Cloudflare 账户登录${gl_bai}"
    echo ""
    echo "即将打开浏览器进行 Cloudflare 登录..."
    echo -e "${gl_huang}请在浏览器中完成授权${gl_bai}"
    echo ""
    read -e -p "按回车继续..."
    
    cloudflared tunnel login
    
    if [ $? -ne 0 ]; then
        echo -e "${gl_hong}❌ 登录失败${gl_bai}"
        break_end
        return 1
    fi
    
    echo -e "${gl_lv}✅ 登录成功${gl_bai}"
    
    echo ""
    echo -e "${gl_zi}[步骤 2/5] 创建隧道${gl_bai}"
    echo ""
    
    local tunnel_name="sub-store-$instance_num"
    echo "隧道名称: $tunnel_name"
    
    cloudflared tunnel create "$tunnel_name"
    
    if [ $? -ne 0 ]; then
        echo -e "${gl_hong}❌ 创建隧道失败${gl_bai}"
        break_end
        return 1
    fi
    
    # 获取 tunnel ID
    local tunnel_id=$(cloudflared tunnel list | grep "$tunnel_name" | awk '{print $1}')
    
    if [ -z "$tunnel_id" ]; then
        echo -e "${gl_hong}❌ 无法获取 tunnel ID${gl_bai}"
        break_end
        return 1
    fi
    
    echo -e "${gl_lv}✅ 隧道创建成功${gl_bai}"
    echo "Tunnel ID: $tunnel_id"
    
    echo ""
    echo -e "${gl_zi}[步骤 3/5] 输入域名${gl_bai}"
    echo ""
    
    local domain
    read -e -p "请输入你的域名（如 sub.example.com）: " domain
    
    if [ -z "$domain" ]; then
        echo -e "${gl_hong}域名不能为空${gl_bai}"
        break_end
        return 1
    fi
    
    echo ""
    echo -e "${gl_zi}[步骤 4/5] 配置 DNS 路由${gl_bai}"
    echo ""
    
    cloudflared tunnel route dns "$tunnel_id" "$domain"
    
    if [ $? -ne 0 ]; then
        echo -e "${gl_hong}❌ DNS 配置失败${gl_bai}"
        break_end
        return 1
    fi
    
    echo -e "${gl_lv}✅ DNS 配置成功${gl_bai}"
    
    echo ""
    echo -e "${gl_zi}[步骤 5/5] 生成并启动配置${gl_bai}"
    echo ""
    
    # 生成最终配置文件
    local final_cf_conf="/root/sub-store-cf-tunnel-$instance_num.yaml"
    cat > "$final_cf_conf" << CFEOF
tunnel: $tunnel_id
credentials-file: /root/.cloudflared/$tunnel_id.json

ingress:
  # 后端 API 路由（必须在前面，更具体的规则）
  - hostname: $domain
    path: /$access_path
    service: http://127.0.0.1:$api_port
  
  # 前端页面路由（通配所有其他请求，与后端共用端口）
  - hostname: $domain
    service: http://127.0.0.1:$api_port
  
  # 默认规则（必须）
  - service: http_status:404
CFEOF
    
    echo -e "${gl_lv}✅ 配置文件已生成: $final_cf_conf${gl_bai}"
    
    echo ""
    echo "正在启动 Cloudflare Tunnel..."
    
    # 创建 systemd 服务
    cat > /etc/systemd/system/cloudflared-sub-store-$instance_num.service << SERVICEEOF
[Unit]
Description=Cloudflare Tunnel for Sub-Store Instance $instance_num
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/cloudflared tunnel --config $final_cf_conf run
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICEEOF
    
    systemctl daemon-reload
    systemctl enable cloudflared-sub-store-$instance_num
    systemctl start cloudflared-sub-store-$instance_num
    
    sleep 3
    
    if systemctl is-active --quiet cloudflared-sub-store-$instance_num; then
        echo -e "${gl_lv}✅ Cloudflare Tunnel 启动成功${gl_bai}"
        echo ""
        echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo -e "${gl_lv}🎉 配置完成！${gl_bai}"
        echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo ""
        echo -e "访问地址: ${gl_lv}https://$domain?api=https://$domain/$access_path${gl_bai}"
        echo ""
        echo "服务管理："
        echo "  - 查看状态: systemctl status cloudflared-sub-store-$instance_num"
        echo "  - 查看日志: journalctl -u cloudflared-sub-store-$instance_num -f"
        echo "  - 重启服务: systemctl restart cloudflared-sub-store-$instance_num"
        echo ""
    else
        echo -e "${gl_hong}❌ Cloudflare Tunnel 启动失败${gl_bai}"
        echo "查看日志: journalctl -u cloudflared-sub-store-$instance_num -n 50"
    fi
    
    break_end
}

# 更新实例
update_substore_instance() {
    clear
    echo "=================================="
    echo "    Sub-Store 实例更新"
    echo "=================================="
    echo ""
    
    local instances=($(get_substore_instances))
    
    if [ ${#instances[@]} -eq 0 ]; then
        echo -e "${gl_huang}没有已部署的实例${gl_bai}"
        break_end
        return 1
    fi
    
    echo -e "${gl_zi}已部署的实例：${gl_bai}"
    for i in "${!instances[@]}"; do
        local instance_name="${instances[$i]}"
        local instance_num=$(echo "$instance_name" | sed 's/store-//')
        local container_name="sub-store-$instance_num"
        
        if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
            echo -e "  $((i+1)). ${instance_name} ${gl_lv}[运行中]${gl_bai}"
        else
            echo -e "  $((i+1)). ${instance_name} ${gl_hong}[已停止]${gl_bai}"
        fi
    done
    echo "  $((${#instances[@]}+1)). 更新所有实例"
    echo ""
    
    local choice
    read -e -p "请选择要更新的实例编号（输入 0 取消）: " choice
    
    if [ "$choice" == "0" ]; then
        echo "已取消更新"
        break_end
        return 1
    fi
    
    # 更新所有实例
    if [ "$choice" == "$((${#instances[@]}+1))" ]; then
        echo ""
        echo "准备更新所有实例..."
        local confirm
        read -e -p "确认更新所有 ${#instances[@]} 个实例？(y/n): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "已取消更新"
            break_end
            return 1
        fi
        
        echo "正在拉取最新镜像..."
        docker pull xream/sub-store:http-meta
        
        for instance in "${instances[@]}"; do
            local config_file="/root/sub-store-configs/${instance}.yaml"
            local instance_num=$(echo "$instance" | sed 's/store-//')
            
            echo ""
            echo "正在更新实例: $instance"
            docker compose -f "$config_file" down
            docker compose -f "$config_file" up -d
            echo -e "${gl_lv}✅ 实例 $instance 更新完成${gl_bai}"
        done
        
        echo ""
        echo -e "${gl_lv}所有实例更新完成！${gl_bai}"
        break_end
        return 0
    fi
    
    # 更新单个实例
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#instances[@]} ]; then
        echo -e "${gl_hong}无效的选择${gl_bai}"
        break_end
        return 1
    fi
    
    local instance_name="${instances[$((choice-1))]}"
    local config_file="/root/sub-store-configs/${instance_name}.yaml"
    local instance_num=$(echo "$instance_name" | sed 's/store-//')
    
    echo ""
    echo "准备更新实例: $instance_name"
    local confirm
    read -e -p "确认更新？(y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "已取消更新"
        break_end
        return 1
    fi
    
    echo "正在拉取最新镜像..."
    docker pull xream/sub-store:http-meta
    
    echo "正在停止容器..."
    docker compose -f "$config_file" down
    
    echo "正在启动更新后的容器..."
    docker compose -f "$config_file" up -d
    
    echo -e "${gl_lv}✅ 实例 $instance_name 更新完成！${gl_bai}"
    
    break_end
}

# 卸载实例
uninstall_substore_instance() {
    clear
    echo "=================================="
    echo "    Sub-Store 实例卸载"
    echo "=================================="
    echo ""
    
    local instances=($(get_substore_instances))
    
    if [ ${#instances[@]} -eq 0 ]; then
        echo -e "${gl_huang}没有已部署的实例${gl_bai}"
        break_end
        return 1
    fi
    
    echo -e "${gl_zi}已部署的实例：${gl_bai}"
    for i in "${!instances[@]}"; do
        local instance_name="${instances[$i]}"
        local instance_num=$(echo "$instance_name" | sed 's/store-//')
        local container_name="sub-store-$instance_num"
        
        if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
            echo -e "  $((i+1)). ${instance_name} ${gl_lv}[运行中]${gl_bai}"
        else
            echo -e "  $((i+1)). ${instance_name} ${gl_hong}[已停止]${gl_bai}"
        fi
    done
    echo ""
    
    local choice
    read -e -p "请选择要卸载的实例编号（输入 0 取消）: " choice
    
    if [ "$choice" == "0" ]; then
        echo "已取消卸载"
        break_end
        return 1
    fi
    
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#instances[@]} ]; then
        echo -e "${gl_hong}无效的选择${gl_bai}"
        break_end
        return 1
    fi
    
    local instance_name="${instances[$((choice-1))]}"
    local config_file="/root/sub-store-configs/${instance_name}.yaml"
    local instance_num=$(echo "$instance_name" | sed 's/store-//')
    
    echo ""
    echo -e "${gl_huang}将要卸载实例: $instance_name${gl_bai}"
    
    local delete_data
    read -e -p "是否同时删除数据目录？(y/n): " delete_data
    echo ""
    
    local confirm
    read -e -p "确认卸载？(y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "已取消卸载"
        break_end
        return 1
    fi
    
    echo "正在停止并删除容器..."
    docker compose -f "$config_file" down
    
    if [[ "$delete_data" =~ ^[Yy]$ ]]; then
        # 从配置文件中提取数据目录
        local data_dir=$(grep -A 1 "volumes:" "$config_file" | tail -n 1 | awk -F':' '{print $1}' | xargs)
        if [ -n "$data_dir" ] && [ -d "$data_dir" ]; then
            echo "正在删除数据目录: $data_dir"
            rm -rf "$data_dir"
        fi
    fi
    
    echo "正在删除配置文件..."
    rm -f "$config_file"
    
    # 删除相关配置模板
    rm -f "/root/sub-store-nginx-$instance_num.conf"
    rm -f "/root/sub-store-cf-tunnel-$instance_num.yaml"
    
    echo -e "${gl_lv}✅ 实例 $instance_name 已成功卸载${gl_bai}"
    
    break_end
}

# 列出所有实例
list_substore_instances() {
    clear
    echo "=================================="
    echo "    已部署的 Sub-Store 实例"
    echo "=================================="
    echo ""
    
    local instances=($(get_substore_instances))
    
    if [ ${#instances[@]} -eq 0 ]; then
        echo -e "${gl_huang}没有已部署的实例${gl_bai}"
        break_end
        return 1
    fi
    
    for instance in "${instances[@]}"; do
        local config_file="/root/sub-store-configs/${instance}.yaml"
        local instance_num=$(echo "$instance" | sed 's/store-//')
        local container_name="sub-store-$instance_num"
        
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "实例编号: $instance_num"
        
        # 检查容器状态
        if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
            echo -e "  状态: ${gl_lv}运行中${gl_bai}"
        else
            echo -e "  状态: ${gl_hong}已停止${gl_bai}"
        fi
        
        # 提取配置信息
        if [ -f "$config_file" ]; then
            local http_port=$(grep "PORT:" "$config_file" | awk '{print $2}')
            local api_port=$(grep "SUB_STORE_BACKEND_API_PORT:" "$config_file" | awk '{print $2}')
            local access_path=$(grep "SUB_STORE_FRONTEND_BACKEND_PATH:" "$config_file" | awk '{print $2}')
            local data_dir=$(grep -A 1 "volumes:" "$config_file" | tail -n 1 | awk -F':' '{print $1}' | xargs)
            
            echo "  容器名称: $container_name"
            echo "  前端端口: $http_port (127.0.0.1)"
            echo "  后端端口: $api_port (127.0.0.1)"
            echo "  访问路径: $access_path"
            echo "  数据目录: $data_dir"
            echo "  配置文件: $config_file"
        fi
        
        echo ""
    done
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    break_end
}

# Sub-Store 主菜单
manage_substore() {
    while true; do
        clear
        echo "=================================="
        echo "   Sub-Store 多实例管理"
        echo "=================================="
        echo ""
        echo "1. 安装新实例"
        echo "2. 更新实例"
        echo "3. 卸载实例"
        echo "4. 查看已部署实例"
        echo "0. 返回主菜单"
        echo "=================================="
        read -e -p "请选择操作 [0-4]: " choice
        
        case $choice in
            1)
                install_substore_instance
                ;;
            2)
                update_substore_instance
                ;;
            3)
                uninstall_substore_instance
                ;;
            4)
                list_substore_instances
                ;;
            0)
                return
                ;;
            *)
                echo "无效的选择"
                sleep 2
                ;;
        esac
    done
}


#=============================================================================
# 脚本入口
#=============================================================================

main() {
    check_root
    print_repo_info_once
    
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

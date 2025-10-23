#!/usr/bin/env bash

#=============================================================================
# 快速启动脚本 - 在线运行最新版 net-tcp-tune.sh
# 使用方法: bash bbr.sh
#=============================================================================

DEFAULT_REPO_OWNER="QAQ-AWA"
DEFAULT_REPO_NAME="vps-tcp-tune"
DEFAULT_REPO_BRANCH="main"

REPO_OWNER="${VTT_REPO_OWNER:-${DEFAULT_REPO_OWNER}}"
REPO_NAME="${VTT_REPO_NAME:-${DEFAULT_REPO_NAME}}"
REPO_BRANCH="${VTT_REPO_BRANCH:-${DEFAULT_REPO_BRANCH}}"

PRIMARY_SOURCE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}/net-tcp-tune.sh"
CDN_FALLBACK="https://cdn.jsdelivr.net/gh/${REPO_OWNER}/${REPO_NAME}@${REPO_BRANCH}/net-tcp-tune.sh"

download_script() {
    local url="$1"
    local output="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 10 --max-time 120 "$url" -o "$output"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --connect-timeout=10 --timeout=120 -O "$output" "$url"
    else
        echo "未找到可用的 curl 或 wget 命令"
        return 1
    fi
}

main() {
    local timestamp
    timestamp=$(date +%s)
    local primary_url="${PRIMARY_SOURCE}?${timestamp}"
    local fallback_url="${CDN_FALLBACK}?${timestamp}"
    local tmp_file
    tmp_file=$(mktemp)

    echo "使用仓库: ${REPO_OWNER}/${REPO_NAME}@${REPO_BRANCH}"
    echo "下载来源: ${PRIMARY_SOURCE}"

    if ! download_script "$primary_url" "$tmp_file"; then
        echo "主源下载失败，尝试 jsDelivr CDN 回退..."
        if ! download_script "$fallback_url" "$tmp_file"; then
            echo "无法从自有仓库获取 net-tcp-tune.sh"
            rm -f "$tmp_file"
            exit 1
        fi
        echo "已启用 CDN 回退: ${CDN_FALLBACK}"
    fi

    chmod +x "$tmp_file"
    bash "$tmp_file" "$@"
    local status=$?
    rm -f "$tmp_file"
    exit $status
}

main "$@"

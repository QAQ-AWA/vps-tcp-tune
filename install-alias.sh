#!/bin/bash
#=============================================================================
# 脚本名称: install-alias.sh
# 功能描述: 为 net-tcp-tune 脚本创建快捷别名
# 使用方法: bash install-alias.sh
#=============================================================================

YELLOW='\033[1;33m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

DEFAULT_REPO_OWNER="QAQ-AWA"
DEFAULT_REPO_NAME="vps-tcp-tune"
DEFAULT_REPO_BRANCH="main"

REPO_OWNER="${VTT_REPO_OWNER:-${DEFAULT_REPO_OWNER}}"
REPO_NAME="${VTT_REPO_NAME:-${DEFAULT_REPO_NAME}}"
REPO_BRANCH="${VTT_REPO_BRANCH:-${DEFAULT_REPO_BRANCH}}"

BASE_RAW_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}"
CDN_RAW_URL="https://cdn.jsdelivr.net/gh/${REPO_OWNER}/${REPO_NAME}@${REPO_BRANCH}"

echo -e "${CYAN}=== 安装 net-tcp-tune 快捷别名 ===${NC}"
echo ""

# 检测当前使用的 shell
CURRENT_SHELL=$(basename "$SHELL")
echo -e "检测到 Shell: ${GREEN}${CURRENT_SHELL}${NC}"
echo ""
echo -e "使用仓库: ${GREEN}${REPO_OWNER}/${REPO_NAME}@${REPO_BRANCH}${NC}"
echo -e "主源: ${YELLOW}${BASE_RAW_URL}${NC}"
echo -e "CDN 回退: ${YELLOW}${CDN_RAW_URL}${NC}"
echo ""

# 根据不同的 shell 设置配置文件
if [ "$CURRENT_SHELL" = "zsh" ]; then
    RC_FILE="$HOME/.zshrc"
elif [ "$CURRENT_SHELL" = "bash" ]; then
    RC_FILE="$HOME/.bashrc"
    # 如果 .bashrc 不存在，使用 .bash_profile
    if [ ! -f "$RC_FILE" ]; then
        RC_FILE="$HOME/.bash_profile"
    fi
else
    echo -e "${YELLOW}未知的 Shell 类型，将使用 .bashrc${NC}"
    RC_FILE="$HOME/.bashrc"
fi

echo -e "配置文件: ${GREEN}${RC_FILE}${NC}"
echo ""

# 定义要添加的别名（带时间戳参数，确保每次获取最新版本）
ALIAS_CONTENT=$(cat <<EOF
# ========================================
# net-tcp-tune 快捷别名 (自动添加)
# 使用时间戳参数确保每次都获取最新版本，避免缓存
# ========================================
vtt_net_tcp_tune_runner() {
    local owner="\${VTT_REPO_OWNER:-${REPO_OWNER}}"
    local name="\${VTT_REPO_NAME:-${REPO_NAME}}"
    local branch="\${VTT_REPO_BRANCH:-${REPO_BRANCH}}"
    local base_raw="https://raw.githubusercontent.com/\${owner}/\${name}/\${branch}/net-tcp-tune.sh"
    local cdn_raw="https://cdn.jsdelivr.net/gh/\${owner}/\${name}@\${branch}/net-tcp-tune.sh"
    local timestamp=\$(date +%s)
    local tmp_file=\$(mktemp)
    local primary_url="\${base_raw}?\${timestamp}"
    local fallback_url="\${cdn_raw}?\${timestamp}"

    echo "使用仓库: \${owner}/\${name}@\${branch}"
    echo "下载来源: \${base_raw}"

    if command -v curl >/dev/null 2>&1; then
        if ! curl -fsSL --connect-timeout 10 --max-time 120 "\${primary_url}" -o "\${tmp_file}"; then
            echo "主源下载失败，尝试 jsDelivr CDN 回退..."
            if ! curl -fsSL --connect-timeout 10 --max-time 120 "\${fallback_url}" -o "\${tmp_file}"; then
                echo "无法下载 net-tcp-tune.sh"
                rm -f "\${tmp_file}"
                return 1
            fi
            echo "已启用 CDN 回退: \${cdn_raw}"
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -q --connect-timeout=10 --timeout=120 -O "\${tmp_file}" "\${primary_url}"; then
            echo "主源下载失败，尝试 jsDelivr CDN 回退..."
            if ! wget -q --connect-timeout=10 --timeout=120 -O "\${tmp_file}" "\${fallback_url}"; then
                echo "无法下载 net-tcp-tune.sh"
                rm -f "\${tmp_file}"
                return 1
            fi
            echo "已启用 CDN 回退: \${cdn_raw}"
        fi
    else
        echo "请安装 curl 或 wget 后再试"
        rm -f "\${tmp_file}"
        return 1
    fi

    chmod +x "\${tmp_file}"
    bash "\${tmp_file}" "$@"
    local status=$?
    rm -f "\${tmp_file}"
    return \${status}
}
alias bbr='vtt_net_tcp_tune_runner'
EOF
)

# 检查别名是否已存在
if grep -q "net-tcp-tune 快捷别名" "$RC_FILE" 2>/dev/null; then
    echo -e "${YELLOW}别名已存在，跳过安装${NC}"
    echo ""
else
    # 添加别名到配置文件
    echo "$ALIAS_CONTENT" >> "$RC_FILE"
    echo -e "${GREEN}✅ 别名已添加到 ${RC_FILE}${NC}"
    echo ""
fi

echo -e "${CYAN}=== 快捷命令 ===${NC}"
echo ""
echo -e "  ${GREEN}bbr${NC}   - 一键运行脚本"
echo ""
echo -e "${CYAN}=== 使用方法 ===${NC}"
echo ""
echo "1. 重新加载配置："
echo -e "   ${YELLOW}source ${RC_FILE}${NC}"
echo ""
echo "2. 或者关闭终端重新打开"
echo ""
echo "3. 然后直接输入快捷命令："
echo -e "   ${GREEN}bbr${NC}"
echo ""
echo -e "${CYAN}=== 现在就生效（执行以下命令）===${NC}"
echo ""
echo -e "${YELLOW}source ${RC_FILE}${NC}"
echo ""


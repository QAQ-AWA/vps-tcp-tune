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

echo -e "${CYAN}=== 安装 net-tcp-tune 快捷别名 ===${NC}"
echo ""

# 检测当前使用的 shell
CURRENT_SHELL=$(basename "$SHELL")
echo -e "检测到 Shell: ${GREEN}${CURRENT_SHELL}${NC}"
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

# 定义要添加的别名
ALIAS_CONTENT='
# ========================================
# net-tcp-tune 快捷别名 (自动添加)
# ========================================
alias bbr="bash <(wget -qO- https://raw.githubusercontent.com/Eric86777/vps-tcp-tune/main/net-tcp-tune.sh)"
alias tcp-tune="bash <(wget -qO- https://raw.githubusercontent.com/Eric86777/vps-tcp-tune/main/net-tcp-tune.sh)"
alias net-tune="bash <(wget -qO- https://raw.githubusercontent.com/Eric86777/vps-tcp-tune/main/net-tcp-tune.sh)"
'

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

echo -e "${CYAN}=== 可用的快捷命令 ===${NC}"
echo ""
echo -e "  ${GREEN}bbr${NC}        - 最短命令（推荐）"
echo -e "  ${GREEN}tcp-tune${NC}   - TCP 调优"
echo -e "  ${GREEN}net-tune${NC}   - 网络调优"
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


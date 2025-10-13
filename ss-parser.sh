#!/bin/bash

#########################################################
# SS订阅链接解析与生成工具
#########################################################
# 
# 功能说明：
# 1. 解析SS订阅链接，提取服务器IP、端口、加密方式、密码
# 2. 根据配置参数生成新的SS订阅链接
#
# 使用场景：
# - 查看SS节点的服务器IP和端口信息（用于配置端口转发）
# - 修改SS节点的IP/端口后重新生成订阅链接
# - 通过中转VPS转发SS流量时，生成新的订阅链接
#
#########################################################
# 常用命令示例：
#########################################################
#
# 【1】解析SS链接（提取IP和端口）：
#   ./ss-parser.sh parse 'ss://YWVzLTEyOC1nY206NGIwMmFiMWEtYjY1Yy00NDIyLWJjY2QtY2E4NTJjOTJjZjVjQDE1NC4zLjMyLjYwOjIwMDAw#🇭🇰DMIT HKG.T1.TINY 500G'
#
# 【2】生成SS订阅链接（用于端口转发后的新节点）：
#   ./ss-parser.sh generate aes-128-gcm 4b02ab1a-b65c-4422-bccd-ca852c92cf5c 8.217.243.145 20000 '🇭🇰DMIT HKG.T1.TINY 500G'
#   
#   参数说明：
#   - 第1个参数：加密方式（如：aes-128-gcm, 2022-blake3-aes-128-gcm）
#   - 第2个参数：密码
#   - 第3个参数：服务器IP（可以是原始IP，也可以是转发VPS的IP）
#   - 第4个参数：端口号
#   - 第5个参数：节点名称（可以带emoji）
#
# 【3】实际应用场景 - 端口转发：
#   原始节点: 154.3.32.60:20000
#   转发VPS: 8.217.243.145
#   
#   步骤1：在转发VPS上配置转发规则
#   socat TCP4-LISTEN:20000,fork,reuseaddr TCP4:154.3.32.60:20000
#   
#   步骤2：使用本脚本生成新的订阅链接
#   ./ss-parser.sh generate aes-128-gcm 4b02ab1a-b65c-4422-bccd-ca852c92cf5c 8.217.243.145 20000 '🇭🇰DMIT HKG.T1.TINY 500G'
#   
#   步骤3：将生成的ss://链接添加到SubStore或其他订阅工具
#
#########################################################

echo "========================================="
echo "SS订阅链接解析工具"
echo "========================================="
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 函数：解析SS链接
# 功能：将SS订阅链接解码，提取出服务器IP、端口、加密方式、密码等信息
# 参数：$1 = SS订阅链接（格式：ss://base64编码#节点名称）
# 用途：查看节点配置，用于设置端口转发
parse_ss_link() {
    local ss_link="$1"
    
    # 移除 ss:// 前缀
    local encoded_part=$(echo "$ss_link" | sed 's/ss:\/\///' | cut -d'#' -f1)
    
    # 提取备注名称（如果有）
    local name=$(echo "$ss_link" | grep -o '#.*' | sed 's/#//' | sed 's/%20/ /g')
    
    # Base64解码
    # 尝试标准base64解码
    local decoded=$(echo "$encoded_part" | base64 -d 2>/dev/null)
    
    # 如果标准解码失败，尝试URL安全的base64解码
    if [ -z "$decoded" ]; then
        decoded=$(echo "$encoded_part" | tr '_-' '/+' | base64 -d 2>/dev/null)
    fi
    
    if [ -z "$decoded" ]; then
        echo -e "${RED}错误：Base64解码失败${NC}"
        return 1
    fi
    
    # 解析格式: method:password@server:port
    local method=$(echo "$decoded" | cut -d':' -f1)
    local rest=$(echo "$decoded" | cut -d':' -f2-)
    local password=$(echo "$rest" | cut -d'@' -f1)
    local server_part=$(echo "$rest" | cut -d'@' -f2)
    local server=$(echo "$server_part" | cut -d':' -f1)
    local port=$(echo "$server_part" | cut -d':' -f2)
    
    # 显示解析结果
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}节点名称:${NC} $name"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}服务器IP:${NC} ${RED}$server${NC}"
    echo -e "${YELLOW}端口:${NC}     ${RED}$port${NC}"
    echo -e "${YELLOW}加密方式:${NC} $method"
    echo -e "${YELLOW}密码:${NC}     $password"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # 生成iptables转发命令示例
    echo -e "${BLUE}端口转发命令示例（假设转发到本地8388端口）:${NC}"
    echo -e "${YELLOW}iptables -t nat -A PREROUTING -p tcp --dport 8388 -j DNAT --to-destination $server:$port${NC}"
    echo -e "${YELLOW}iptables -t nat -A POSTROUTING -p tcp -d $server --dport $port -j MASQUERADE${NC}"
    echo ""
    
    # 生成socat转发命令示例
    echo -e "${BLUE}socat端口转发命令示例:${NC}"
    echo -e "${YELLOW}socat TCP4-LISTEN:8388,fork TCP4:$server:$port${NC}"
    echo ""
    
    # 生成新的SS链接（可用于修改后的配置）
    echo -e "${BLUE}原始配置信息:${NC}"
    echo "  cipher: $method"
    echo "  password: $password"
    echo "  port: $port"
    echo "  server: $server"
    echo ""
}

# 函数：从配置生成SS链接
# 功能：根据提供的参数生成SS订阅链接
# 参数：
#   $1 = 加密方式 (如: aes-128-gcm, 2022-blake3-aes-128-gcm)
#   $2 = 密码
#   $3 = 服务器IP（原始服务器IP或转发VPS的IP）
#   $4 = 端口号
#   $5 = 节点名称
# 用途：修改IP/端口后生成新的订阅链接，用于添加到SubStore
# 示例：./ss-parser.sh generate aes-128-gcm 4b02ab1a-b65c-4422-bccd-ca852c92cf5c 8.217.243.145 20000 '🇭🇰DMIT'
generate_ss_link() {
    local method="$1"
    local password="$2"
    local server="$3"
    local port="$4"
    local name="$5"
    
    # 组合为 method:password@server:port 格式
    local plain_text="${method}:${password}@${server}:${port}"
    
    # Base64编码
    local encoded=$(echo -n "$plain_text" | base64)
    
    # 移除换行符
    encoded=$(echo "$encoded" | tr -d '\n')
    
    # URL编码节点名称
    local encoded_name=$(echo -n "$name" | sed 's/ /%20/g')
    
    # 生成完整的SS链接
    local ss_link="ss://${encoded}#${encoded_name}"
    
    echo -e "${GREEN}生成的SS订阅链接:${NC}"
    echo "$ss_link"
    echo ""
}

# 主程序
main() {
    if [ $# -eq 0 ]; then
        echo "使用方法:"
        echo "  1. 解析SS链接:"
        echo "     $0 parse 'ss://xxxxx#节点名'"
        echo ""
        echo "  2. 生成SS链接:"
        echo "     $0 generate <加密方式> <密码> <服务器> <端口> <节点名>"
        echo ""
        echo "示例:"
        echo "  解析: $0 parse 'ss://YWVzLTEyOC1nY206NGIwMmFiMWEtYjY1Yy00NDIyLWJjY2QtY2E4NTJjOTJjZjVjQDE1NC4zLjMyLjYwOjIwMDAw#🇭🇰DMIT HKG.T1.TINY 500G'"
        echo "  生成: $0 generate aes-128-gcm 4b02ab1a-b65c-4422-bccd-ca852c92cf5c 154.3.32.60 20000 '🇭🇰DMIT HKG.T1.TINY 500G'"
        return 1
    fi
    
    local action="$1"
    shift
    
    case "$action" in
        parse|p)
            if [ -z "$1" ]; then
                echo -e "${RED}错误：请提供SS链接${NC}"
                return 1
            fi
            parse_ss_link "$1"
            ;;
        generate|g)
            if [ $# -lt 5 ]; then
                echo -e "${RED}错误：参数不足${NC}"
                echo "用法: $0 generate <加密方式> <密码> <服务器> <端口> <节点名>"
                return 1
            fi
            generate_ss_link "$1" "$2" "$3" "$4" "$5"
            ;;
        *)
            echo -e "${RED}错误：未知操作 '$action'${NC}"
            echo "支持的操作: parse (p), generate (g)"
            return 1
            ;;
    esac
}

main "$@"


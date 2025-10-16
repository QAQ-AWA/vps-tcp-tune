# BBR v3 终极优化脚本 - Ultimate Edition

🚀 **XanMod 内核 + BBR v3 + 全方位 VPS 管理工具集**  
一键安装 XanMod 内核，启用 BBR v3 拥塞控制，集成 31+ 实用工具，全面优化你的 VPS 服务器。

> **版本**: 2.8.0 (Sub-Store Multi-Instance Management)  
> **快速上手**: [📖 快速使用指南](QUICK_START.md) | **视频教程**: [🎬 B站教程](https://www.bilibili.com/video/BV14K421x7BS)

---

## 🚀 一键安装

```bash
bash <(wget -qO- https://raw.githubusercontent.com/Eric86777/vps-tcp-tune/main/net-tcp-tune.sh)
```

<details>
<summary>💡 更多安装方式（点击展开）</summary>

### 方式2：快捷别名（推荐）

安装后只需输入 `bbr` 即可运行脚本：

```bash
# 安装别名
bash <(wget -qO- https://raw.githubusercontent.com/Eric86777/vps-tcp-tune/main/install-alias.sh)

# 重新加载配置
source ~/.bashrc  # 或 source ~/.zshrc

# 以后直接使用
bbr
```

### 方式3：下载到本地

```bash
wget https://raw.githubusercontent.com/Eric86777/vps-tcp-tune/main/net-tcp-tune.sh
chmod +x net-tcp-tune.sh
./net-tcp-tune.sh
```

</details>

---

## 🎯 推荐调优流程

> **⚡ 三步完整优化 - 系统性提升网络性能**

### 📋 流程概览

```
步骤1：安装 BBR v3 内核 → 重启
步骤2：CAKE 队列调优 → 重启  
步骤3：高性能模式优化 → 完成
```

### 🔧 详细步骤

<details>
<summary><b>【步骤1】安装 XanMod 内核 + BBR v3</b></summary>

```bash
# 运行脚本
bash <(wget -qO- https://raw.githubusercontent.com/Eric86777/vps-tcp-tune/main/net-tcp-tune.sh)

# 选择菜单
选择 1 → 安装 XanMod 内核 + BBR v3

# 重启生效
reboot
```

**✅ 完成后**：XanMod 内核已安装，BBR v3 已启用

</details>

<details>
<summary><b>【步骤2】CAKE 队列调优</b></summary>

```bash
# 再次运行脚本
bash <(wget -qO- https://raw.githubusercontent.com/Eric86777/vps-tcp-tune/main/net-tcp-tune.sh)

# 选择菜单（⚠️ 注意序号变化）
选择 3 → NS论坛CAKE调优

# 重启生效
reboot
```

**✅ 完成后**：CAKE 队列算法已优化，网络延迟降低

</details>

<details>
<summary><b>【步骤3】高性能模式优化</b></summary>

```bash
# 再次运行脚本
bash <(wget -qO- https://raw.githubusercontent.com/Eric86777/vps-tcp-tune/main/net-tcp-tune.sh)

# 选择菜单
选择 4 → 科技lion高性能模式
      → 选择 1 → 高性能优化模式

# 无需重启，立即生效
```

**✅ 完成后**：系统内核参数全面优化 🎉

</details>

### ⚠️ 重要提示

| 注意事项 | 说明 |
|---------|------|
| **菜单序号变化** | 安装内核前 CAKE 是选项2，安装后变成选项3 |
| **必须重启** | 步骤1和2完成后都需要重启才能生效 |
| **按顺序执行** | 必须按照 BBR v3 → CAKE → 高性能模式 的顺序 |

### 📊 预期优化效果

| 优化项 | 优化前 | 优化后 | 说明 |
|-------|-------|-------|------|
| **拥塞控制** | Cubic | BBR v3 | 高延迟链路性能显著提升 |
| **队列管理** | pfifo_fast | CAKE | 减少缓冲区膨胀，降低延迟 |
| **并发连接** | 128 | 4096 | 大幅提升连接处理能力 |
| **TCP缓冲区** | 默认值 | 优化配置 | 适配高带宽网络环境 |

---

## 🌟 核心特性

### ✨ 十大功能模块

1. **🔧 内核管理** - XanMod 内核安装/更新/卸载（支持 x86_64 & ARM64）
2. **⚡ BBR TCP调优** - CAKE队列优化 + 6种内核参数模式 + BBR直连优化（智能带宽检测）
3. **🛠️ 系统设置** - 虚拟内存管理 + IPv6管理（临时/永久禁用/还原） + SOCKS5代理配置 + IPv4/IPv6 优先级 + IPv4/IPv6连接检测
4. **🔐 Xray 配置** - Realm转发分析 + 查看/IPv6出站/恢复默认配置
5. **📊 网络测试** - Speedtest + 三网回程 + IP质量 + 延迟检测
6. **🎯 流媒体检测** - Netflix/Disney+/OpenAI/Claude 解锁检测
7. **🔌 第三方工具** - PF_realm + 御坂美琴 + sing-box + 科技lion + NS论坛 + 酷雪云
8. **🚀 代理部署** - 一键部署 SOCKS5 代理（基于 Sing-box） + **Sub-Store 多实例管理（NEW）**
9. **📋 系统信息** - CPU/内存/网络流量/地理位置统计

---

## 📋 功能菜单

<details>
<summary>📊 完整菜单对照表（点击展开）</summary>

| 功能 | 未安装内核 | 已安装内核 |
|------|-----------|-----------|
| 安装/更新内核 | 1 | 1（更新） |
| 卸载内核 | - | 2 |
| NS论坛CAKE调优 | 2 | 3 |
| 科技lion高性能模式 | 3 | 4 |
| BBR直连/落地 | 4 | 5 |
| 虚拟内存管理 | 5 | 6 |
| **IPv6管理** | **6** | **7** |
| **临时SOCKS5代理** | **7** | **8** |
| IPv4优先 | 8 | 9 |
| IPv6优先 | 9 | 10 |
| 查看Xray配置 | 10 | 11 |
| Xray IPv6出站 | 11 | 12 |
| 恢复Xray默认 | 12 | 13 |
| 查看详细状态 | 13 | 14 |
| NS一键检测 | 14 | 15 |
| 服务器带宽测试 | 15 | 16 |
| 三网回程路由 | 16 | 17 |
| IP质量检测 | 17 | 18 |
| IP质量-IPv4 | 18 | 19 |
| 网络延迟检测 | 19 | 20 |
| 国际互联速度 | 20 | 21 |
| 媒体/AI解锁 | 21 | 22 |
| PF_realm转发 | 22 | 23 |
| 御坂美琴双协议 | 23 | 24 |
| F佬sing box | 24 | 25 |
| 科技lion脚本 | 25 | 26 |
| NS论坛cake调优 | 26 | 27 |
| 酷雪云脚本 | 27 | 28 |
| 部署SOCKS5代理 | 28 | 29 |
| **Sub-Store多实例管理** | **30** | **32** |

</details>

---

## 📋 支持系统

| 系统 | 架构 | 支持状态 |
|------|------|---------|
| **Debian 10+** | x86_64 | ✅ 完整支持 |
| **Ubuntu 20.04+** | x86_64 | ✅ 完整支持 |
| **Debian/Ubuntu** | ARM64 | ✅ 专用脚本 |
| 其他发行版 | - | ❌ 不支持 |

---

## 📊 验证配置

```bash
# 查看拥塞控制算法
sysctl net.ipv4.tcp_congestion_control

# 查看队列算法
sysctl net.core.default_qdisc

# 验证 BBR 版本
modinfo tcp_bbr | grep version
```

**预期输出**：
```
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = cake
version:        3
```

---

## 🔧 高级功能说明

<details>
<summary>🔍 Realm 转发连接分析</summary>

菜单选项 **11**（未安装）/ **12**（已安装）

**核心功能**：
- 🔍 自动检测 Realm 进程
- 📊 智能分析所有转发源 IP
- 🌐 自动查询 IP 归属地（国家/城市/ISP/AS号）
- ✅ 精确识别 IPv4/IPv6 协议类型
- 📈 实时统计连接数和协议分布

**功能亮点**：
1. **一键分析**：无需手动输入IP，自动发现所有转发源
2. **协议识别**：区分纯IPv4和IPv4映射IPv6（`::ffff:` 格式）
3. **IP溯源**：自动查询IP归属地，立即知道是谁在连接
4. **详细报告**：
   - 每个转发源的连接数
   - 本地监听端口
   - 协议类型和分布
   - 总体统计摘要

**交互功能**：
- 查看详细连接列表（所有端口详情）
- 导出分析报告到文件（保存到 `/root/realm_analysis_*.txt`）
- 实时监控模式（每5秒刷新一次）
- 检测特定源 IP（深度分析单个转发源）

**使用场景**：
- ✅ 快速确认 Realm 转发是否走 IPv4
- ✅ 发现未知的转发源（安全检查）
- ✅ 验证中转机到落地机的连接状态
- ✅ 排查连接问题（显示所有活跃连接）

**示例输出**：
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
┌─────────────── 转发源 #1 ───────────────┐
│  源IP地址:   108.247.217.148            │
│  IP归属:     美国 加利福尼亚 DMIT        │
│  AS号:       AS54574                     │
│  连接数:     35 个                       │
│  协议类型:   ✅ 纯IPv4                   │
│  本地监听:   443                         │
│  状态:       ✅ 正常                     │
└──────────────────────────────────────────┘

统计摘要：
  • 转发源总数:     2 个
  • IPv4连接:       63 个 ✅
  • IPv6连接:       0 个
  • 结论:           100% 使用 IPv4 链路 ✅
```

**前置要求**：机器上运行有 Realm 转发服务

</details>

<details>
<summary>🧠 虚拟内存智能计算</summary>

菜单选项 **5**（未安装）/ **6**（已安装）

| 物理内存 | 推荐 SWAP | 计算公式 |
|---------|-----------|---------|
| < 512MB | 1GB（固定） | 固定值 |
| 512MB - 1GB | 内存 × 2 | 例：512MB → 1GB SWAP |
| 1GB - 2GB | 内存 × 1.5 | 例：1GB → 1.5GB SWAP |
| 2GB - 4GB | 内存 × 1 | 例：2GB → 2GB SWAP |
| 4GB - 8GB | 4GB（固定） | 固定值 |
| ≥ 8GB | 4GB（固定） | 固定值 |

</details>

<details>
<summary>⚡ BBR直连/落地优化（智能带宽检测）</summary>

菜单选项 **4**（未安装）/ **5**（已安装）

**智能带宽检测流程**：
1. 🔍 选择检测方式：自动运行 speedtest / 使用通用值
2. 📊 自动提取上传带宽（Upload速度）
3. 🎯 智能计算缓冲区：
   - < 500 Mbps → 8MB
   - 500-1000 Mbps → 12MB
   - 1-2 Gbps → 16MB
   - 2-5 Gbps → 24MB
   - 5-10 Gbps → 28MB
   - > 10 Gbps → 32MB
4. ✅ 询问确认后应用配置

**特性**：
- ✅ 自动检测内存并建议SWAP配置
- ✅ TIME_WAIT重用启用（高并发）
- ✅ 端口范围1024-65535（最大化）
- ✅ 5步验证流程确保配置生效

</details>

<details>
<summary>⚙️ 科技lion高性能模式（6种优化模式）</summary>

菜单选项 **3**（未安装）/ **4**（已安装）

**6种优化模式**：
1. **高性能模式** - 最大化系统性能（文件描述符65535 + BBR + 16MB缓冲区）
2. **均衡模式** - 性能与资源消耗平衡
3. **网站模式** - Web服务器优化（高并发连接处理）
4. **直播模式** - 直播推流优化（减少延迟）
5. **游戏服模式** - 游戏服务器优化（降低响应延迟）
6. **还原默认** - 恢复系统默认配置

**注意**：优化参数在重启后会失效，如需永久生效需写入 `/etc/sysctl.conf`

</details>

<details>
<summary>🌐 IPv6 管理（临时/永久禁用/还原）</summary>

菜单选项 **6**（未安装）/ **7**（已安装）

**三大核心功能**：

1. **临时禁用 IPv6**
   - 执行 `sysctl -w` 命令临时禁用
   - 重启后自动恢复
   - 适合临时测试场景

2. **永久禁用 IPv6**
   - ✅ **自动备份当前状态**（关键特性）
   - 创建配置文件：`/etc/sysctl.d/99-disable-ipv6.conf`
   - 创建备份文件：`/etc/sysctl.d/.ipv6-state-backup.conf`
   - 重启后仍然生效

3. **取消永久禁用（完全还原）**
   - 🎯 **从备份精确恢复到执行永久禁用前的状态**
   - 删除所有相关配置文件（配置 + 备份）
   - 确保系统恢复到"从未执行过禁用"的状态
   - 如果备份不存在，恢复到系统默认（IPv6启用）

**使用场景**：
- IPv6 连接不稳定，需要临时禁用测试
- 某些服务只支持 IPv4
- 减少 DNS 解析时间

**技术亮点**：
- ✨ 智能状态备份与还原机制
- ✨ 隐藏文件备份（`.ipv6-state-backup.conf`）
- ✨ 完全可逆的操作流程

</details>

<details>
<summary>🔌 临时 SOCKS5 代理配置</summary>

菜单选项 **7**（未安装）/ **8**（已安装）

**功能特点**：
- 交互式输入：IP、端口、用户名（可选）、密码（可选）
- 自动生成配置文件：`/tmp/socks5_proxy_YYYYMMDD_HHMMSS.sh`
- 支持有认证和无认证两种模式
- 重启后自动失效（文件保存在 /tmp）

**使用流程**：
1. 📝 运行脚本并选择对应选项
2. 🔧 输入代理服务器信息
3. 📄 生成临时配置文件
4. ✅ 使用 `source` 命令应用代理

**应用代理**：
```bash
# 应用代理配置
source /tmp/socks5_proxy_YYYYMMDD_HHMMSS.sh

# 测试代理是否生效
curl ip.sb  # 应显示代理服务器的IP

# 取消代理
unset http_proxy https_proxy all_proxy
```

**技术说明**：
- 使用 `source` 命令在当前 shell 应用环境变量
- 配置仅对当前终端会话有效
- 关闭终端或重启后自动失效

**适用场景**：
- 临时需要通过代理访问外网
- 测试代理服务器连通性
- 下载需要代理的软件包

</details>

<details>
<summary>🌐 IPv4/IPv6 优先级设置</summary>

- **IPv4优先**：选项 **8**（未安装）/ **9**（已安装）
- **IPv6优先**：选项 **9**（未安装）/ **10**（已安装）

修改 `/etc/gai.conf` 配置，自动显示当前出口 IP

</details>

<details>
<summary>🔐 Xray 配置管理</summary>

- **查看配置**：选项 **10**（未安装）/ **11**（已安装）
- **IPv6出站**：选项 **11**（未安装）/ **12**（已安装）
- **恢复默认**：选项 **12**（未安装）/ **13**（已安装）

自动备份配置，失败自动回滚

</details>

<details>
<summary>🚀 一键部署 SOCKS5 代理（Sing-box服务）</summary>

菜单选项 **28**（未安装）/ **29**（已安装）

基于 Sing-box 的独立 SOCKS5 代理服务，与主系统完全隔离。

**核心特性**：
- ✅ 自动检测 Sing-box
- ✅ 独立部署（服务名 `sbox-socks5`）
- ✅ 7步自动化部署流程
- ✅ 用户名密码认证
- ✅ 智能端口配置（随机/手动）
- ✅ systemd 管理

**使用示例**：
```bash
# 1. 运行脚本并选择 26/27
# 2. 按提示输入端口、用户名、密码
# 3. 测试连接
curl --socks5-hostname username:password@server_ip:port http://httpbin.org/ip
```

**服务管理**：
```bash
systemctl status sbox-socks5   # 查看状态
journalctl -u sbox-socks5 -f   # 查看日志
systemctl restart sbox-socks5  # 重启服务
```

**前置要求**：需先安装 Sing-box（推荐使用菜单中的"F佬一键sing box脚本"）

</details>

<details>
<summary>📦 Sub-Store 多实例管理</summary>

菜单选项 **30**（未安装）/ **32**（已安装）

基于 Docker Compose 的 Sub-Store 订阅转换服务多实例管理系统。

**核心特性**：
- ✅ 多实例独立管理（支持部署多个独立的 Sub-Store 服务）
- ✅ **自定义访问路径**（支持随机生成或自定义，如 `/my-subs`）
- ✅ 端口冲突自动检测
- ✅ Docker/Docker Compose 依赖自动安装
- ✅ 完整生命周期管理（安装/更新/卸载/查看）
- ✅ 配置持久化（独立 YAML 文件）
- ✅ **自动生成 Nginx 和 Cloudflare Tunnel 配置**

**架构说明**：
- 使用 `xream/sub-store:http-meta` 镜像（前后端分离架构）
- 前端端口：9876（监听 127.0.0.1）
- 后端端口：3001（监听 127.0.0.1）
- **必须通过反向代理才能访问**（无法直接通过 IP 访问）

**安装流程**：
```bash
# 1. 运行脚本并选择 Sub-Store 管理
选择 30（未安装）或 32（已安装）

# 2. 选择安装新实例
输入 1 → 安装新实例

# 3. 配置参数
实例编号: 1
后端 API 端口: 3001（回车使用默认）
HTTP-META 端口: 9876（回车使用默认）
访问路径: my-subs（或回车使用随机20位字符）
数据目录: /root/data-sub-store-1（回车使用默认）

# 4. 确认安装
脚本自动完成：
  - 创建 Docker Compose 配置
  - 启动容器
  - 生成 Nginx 配置模板
  - 生成 Cloudflare Tunnel 配置

# 5. 交互式配置向导（NEW！）
安装完成后，脚本会自动引导你配置反向代理：
  - 选择1：Nginx 反向代理（自动化配置，支持 Let's Encrypt）
  - 选择2：Cloudflare Tunnel（全自动部署，无需开端口）
  - 选择3：跳过（稍后手动配置）
```

**访问地址格式**：
```
https://sub.你的域名.com?api=https://sub.你的域名.com/my-subs
         ↑                                       ↑
      前端页面                                后端API路径
```

**反向代理配置（交互式配置 vs 手动配置）**：

### 🎯 方案1：交互式配置向导（推荐）

安装实例后，脚本会自动进入配置向导：

**【选项1】Nginx 自动化配置**
- ✅ 自动检测并安装 Nginx
- ✅ 交互式输入域名
- ✅ 支持 3 种 SSL 证书方式：
  - Cloudflare 证书（手动上传）
  - **Let's Encrypt 自动申请**（推荐）
  - 仅 HTTP（不推荐）
- ✅ 自动生成配置到 `/etc/nginx/conf.d/`
- ✅ 自动测试配置并重载 Nginx
- ✅ 完成后立即显示访问地址

**【选项2】Cloudflare Tunnel 自动化部署**
- ✅ 自动下载并安装 `cloudflared`
- ✅ 引导登录 Cloudflare 账户
- ✅ 自动创建隧道和配置 DNS
- ✅ 生成配置文件并创建 systemd 服务
- ✅ 自动启动服务
- ✅ 完成后立即显示访问地址和管理命令

**【选项3】跳过配置**
- 生成配置模板文件供稍后手动配置

### 📝 方案2：手动配置（适合高级用户）

**【方法1】Nginx 反向代理**
```nginx
server {
    listen 443 ssl http2;
    server_name sub.你的域名.com;
    
    # 前端页面（HTTP-META）
    location / {
        proxy_pass http://127.0.0.1:9876;
    }
    
    # 后端 API
    location /my-subs {
        proxy_pass http://127.0.0.1:3001;
    }
}
```

**【方法2】Cloudflare Tunnel**（无需开端口）
```yaml
ingress:
  - hostname: sub.你的域名.com
    path: /my-subs
    service: http://127.0.0.1:3001
  - hostname: sub.你的域名.com
    service: http://127.0.0.1:9876
  - service: http_status:404
```

**自动生成的文件**：
- Docker Compose 配置：`/root/sub-store-configs/store-{实例编号}.yaml`
- Nginx 配置模板：`/root/sub-store-nginx-{实例编号}.conf`
- CF Tunnel 配置：`/root/sub-store-cf-tunnel-{实例编号}.yaml`
- 数据目录：`/root/data-sub-store-{实例编号}/`

**常用命令**：
```bash
# 查看日志
docker logs sub-store-1

# 重启服务
docker compose -f /root/sub-store-configs/store-1.yaml restart

# 停止服务
docker compose -f /root/sub-store-configs/store-1.yaml down

# 查看容器状态
docker ps | grep sub-store
```

**多实例场景**：
- 🔹 为不同用户部署独立实例
- 🔹 测试环境与生产环境分离
- 🔹 不同订阅源使用不同实例
- 🔹 负载分散到多个实例

**前置要求**：
- 已安装 Docker 和 Docker Compose（脚本可自动安装）
- 准备好域名（用于反向代理）
- 服务器可访问 Docker Hub

**⚠️ 重要提示**：
- Sub-Store 服务监听 `127.0.0.1`，无法直接通过 IP 访问
- 必须配置 Nginx 或 Cloudflare Tunnel 反向代理
- 访问路径支持自定义（建议使用随机路径提高安全性）
- 前端（9876）和后端（3001）都需要代理

</details>

---

## ⚠️ 注意事项

1. **磁盘空间**：确保根分区至少有 3GB 可用空间
2. **内存要求**：低内存 VPS 会自动创建 1GB SWAP
3. **重启需求**：内核升级后必须重启才能生效
4. **兼容性**：仅支持 Debian/Ubuntu，不支持 CentOS/RHEL
5. **root 权限**：所有操作都需要 root 权限

---

## 💬 常见问题

**Q: BBR v3 和 BBR v2 有什么区别？**  
A: BBR v3 改进了拥塞窗口计算，减少了丢包，提升了跨国高延迟链路的性能。

**Q: ARM 服务器能用吗？**  
A: 可以，脚本会自动检测 ARM64 架构并调用专用安装脚本。

**Q: 虚拟内存（SWAP）应该设置多大？**  
A: 使用脚本的智能计算功能（菜单选项 5/6），会根据物理内存自动推荐最佳大小。

**Q: 安装失败怎么办？**  
A: 检查磁盘空间是否充足（≥3GB）、网络连接是否正常、系统是否为 Debian/Ubuntu。

**Q: 为什么系统优化放在BBR调优前面？**  
A: v2.5版本优化了菜单顺序，将常用的系统内核参数优化和CAKE脚本优先展示，方便快速访问。建议先执行系统优化，再执行BBR配置。

---

## 🤝 参考资料

- **XanMod 官网**: [https://xanmod.org/](https://xanmod.org/)
- **BBR v3**: [Google BBR v3](https://github.com/google/bbr)
- **Xray 文档**: [https://xtls.github.io/](https://xtls.github.io/)
- **CAKE 文档**: [Common Applications Kept Enhanced](https://www.bufferbloat.net/projects/codel/wiki/Cake/)

---

## 🌐 相关链接

- **GitHub**: [https://github.com/Eric86777/vps-tcp-tune](https://github.com/Eric86777/vps-tcp-tune)
- **问题反馈**: [Issues](https://github.com/Eric86777/vps-tcp-tune/issues)
- **视频教程**: [B站](https://www.bilibili.com/video/BV14K421x7BS)

---

## 📝 更新日志

<details>
<summary>查看完整更新日志（点击展开）</summary>

### v2.8.0 (2025-01-16) - Sub-Store Multi-Instance Management

- 📦 **新增 Sub-Store 多实例管理功能**
  - 基于 Docker Compose 的完整生命周期管理
  - 支持安装、更新、卸载、查看多个独立实例
  - **自定义访问路径**（支持随机生成或自定义，如 `/my-subs`）
  - 智能端口冲突检测（后端 3001 + 前端 9876）
  - Docker/Docker Compose 依赖自动安装（国内/国外镜像可选）
  - 菜单位置：选项 30（未安装）/ 32（已安装）

- 🎯 **交互式配置向导（核心亮点）**
  - 🚀 **Nginx 自动化配置**
    - 自动检测并安装 Nginx
    - 交互式输入域名
    - 支持 Let's Encrypt 自动申请证书（推荐）
    - 支持 Cloudflare 证书手动上传
    - 支持仅 HTTP 模式
    - 自动生成配置到 `/etc/nginx/conf.d/`
    - 自动测试配置并重载 Nginx
    - 完成后立即显示访问地址
  - 🌐 **Cloudflare Tunnel 自动化部署**
    - 自动下载并安装 `cloudflared`（支持 x86_64/aarch64）
    - 引导登录 Cloudflare 账户
    - 自动创建隧道和配置 DNS 路由
    - 生成配置文件并创建 systemd 服务
    - 自动启动服务并验证状态
    - 完成后显示访问地址和管理命令
  - ⚙️ **灵活选择**
    - 可选择跳过配置，生成模板供稍后手动配置
    - 配置失败时提供详细错误信息和手动修复指南

- 🔧 **反向代理配置自动生成**
  - 自动生成 Nginx 反向代理配置模板
  - 自动生成 Cloudflare Tunnel 配置文件
  - 前后端双端口代理配置（前端 9876 + 后端 3001）
  - 配置文件保存在 `/root/sub-store-nginx-{实例编号}.conf`
  - 支持 SSL/TLS 配置和 WebSocket
  - HTTP → HTTPS 自动重定向

- 🎯 **核心特性**
  - 前后端分离架构（`xream/sub-store:http-meta` 镜像）
  - 监听本地 127.0.0.1（安全隔离，必须通过反向代理访问）
  - 配置持久化（独立 YAML 文件管理）
  - 数据目录独立（支持自定义或使用默认路径）
  - 完整的实例状态显示（运行中/已停止）

- 📋 **使用场景**
  - 为不同用户部署独立 Sub-Store 实例
  - 测试环境与生产环境分离
  - 不同订阅源使用不同实例
  - 负载分散到多个实例

- 📚 **文档完善**
  - README 新增详细的 Sub-Store 功能说明
  - 包含完整的安装流程、配置示例和常用命令
  - **交互式配置向导完整说明**
  - Nginx 和 Cloudflare Tunnel 自动化配置指南
  - 多实例场景说明

### v2.7.0 (2025-10-14) - Realm Analysis & Connection Detection

- 🔍 **新增 Realm 转发连接分析工具**
  - 自动检测 Realm 进程并分析所有转发源
  - 智能识别纯IPv4和IPv4映射IPv6格式（`::ffff:`）
  - 自动查询IP归属地（国家/城市/ISP/AS号）
  - 实时统计连接数和协议分布
  - 4大交互功能：详细列表/导出报告/实时监控/特定IP分析
  - 菜单位置：选项 11（未安装）/ 12（已安装）

- 🌐 **IPv4/IPv6 连接检测工具升级**
  - 出站检测：验证本机到目标服务器的连接协议
  - 入站检测：验证来自源服务器的连接协议
  - 精确统计IPv4/IPv6连接数
  - 完美适配Realm转发场景验证
  - 菜单位置：选项 10（未安装）/ 11（已安装）

- 📋 **菜单系统更新**
  - 新增2个核心功能（Realm分析 + IPv4/IPv6检测）
  - 所有后续选项序号 +2（10→12, 11→13...）
  - 更新菜单对照表文档（MENU_TABLE.md）

- 📚 **文档全面更新**
  - README新增Realm分析功能详细说明
  - 完整示例输出和使用场景
  - 菜单对照表独立文档化

### v2.6.0 (2025-10-12) - Network Management Enhancement

- 🌐 **新增 IPv6 管理功能**
  - 临时禁用 IPv6（重启后自动恢复）
  - 永久禁用 IPv6（重启后仍生效）
  - 取消永久禁用（完全还原到执行前状态）
  - **核心特性**：智能状态备份与精确还原机制
  - 备份文件：`/etc/sysctl.d/.ipv6-state-backup.conf`
  - 配置文件：`/etc/sysctl.d/99-disable-ipv6.conf`
  - 确保"取消禁用"后系统恢复到"从未执行过"的状态

- 🔌 **新增临时 SOCKS5 代理配置功能**
  - 交互式配置代理服务器（IP、端口、认证）
  - 自动生成临时配置文件：`/tmp/socks5_proxy_YYYYMMDD_HHMMSS.sh`
  - 支持有认证和无认证两种模式
  - 使用 `source` 命令应用，重启后自动失效
  - 适合临时代理需求场景

- 📋 **菜单系统优化**
  - 新增2个系统设置选项（IPv6管理、SOCKS5代理配置）
  - 所有后续选项序号 +2（保持功能完整性）
  - XanMod已安装/未安装两种状态的菜单映射已更新

- 📚 **文档完善**
  - 新增《功能测试说明.md》- 详细测试步骤
  - 新增《实现总结.md》- 技术实现细节
  - README 功能说明全面更新

### v2.5.3 (2025-01-11) - SOCKS5 Proxy Deployment

- 🚀 **新增一键部署 SOCKS5 代理功能**
  - 基于 Sing-box 的独立 SOCKS5 代理服务
  - 智能检测 Sing-box 二进制程序
  - 7步自动化部署流程（检测→配置→验证→启动）
  - 支持用户名密码认证
  - 智能端口配置（随机生成或手动指定）
  - 独立服务管理（sbox-socks5）

- 🔧 **脚本执行错误修复**
  - 删除无效的 `--configure` 快捷命令
  - 修复 Xray 配置备份时间戳不匹配问题
  - 优化备份文件命名
  - 确保配置失败回滚时能正确找到备份文件

### v2.5.2 (2025-01-11) - Script Collection Reorganization

- 📂 **脚本合集顺序调整**
  - 调整第三方工具脚本的展示顺序，更符合使用优先级
  - F佬一键sing box脚本（从原25移至22）
  - 科技lion脚本（从原24移至23）
  - NS论坛的cake调优（从原22移至24）
  - 酷雪云脚本（从原23移至25）

### v2.5.1 (2025-01-11) - Menu Refinement Edition

- 🔄 **菜单项交换与重命名**
  - 交换"系统内核参数优化"和"CAKE调优"的位置
  - "单独cake脚本" → "NS论坛CAKE调优"
  - "Linux系统内核参数优化" → "科技lion高性能模式内核参数优化"

- 🎯 **优化理由**
  - 优先展示CAKE队列优化，更直接有效
  - 科技lion品牌化，提升辨识度
  - 保持菜单逻辑清晰，易于查找

[查看更多历史版本](https://github.com/Eric86777/vps-tcp-tune/releases)

</details>

---

## 📄 License

MIT

---

**⭐ 如果这个脚本对你有帮助，欢迎 Star！**

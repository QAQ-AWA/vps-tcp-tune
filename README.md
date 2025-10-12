# BBR v3 终极优化脚本 - Ultimate Edition

🚀 **XanMod 内核 + BBR v3 + 全方位 VPS 管理工具集**  
一键安装 XanMod 内核，启用 BBR v3 拥塞控制，集成 27+ 实用工具，全面优化你的 VPS 服务器。

> **版本**: 2.5.3 (SOCKS5 Proxy Deployment)  
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

### ✨ 九大功能模块

1. **🔧 内核管理** - XanMod 内核安装/更新/卸载（支持 x86_64 & ARM64）
2. **⚡ BBR TCP调优** - CAKE队列优化 + 6种内核参数模式 + BBR直连优化（智能带宽检测）
3. **🛠️ 系统设置** - 虚拟内存管理 + IPv4/IPv6 优先级设置
4. **🔐 Xray 配置** - 查看/IPv6出站/恢复默认配置
5. **📊 网络测试** - Speedtest + 三网回程 + IP质量 + 延迟检测
6. **🎯 流媒体检测** - Netflix/Disney+/OpenAI/Claude 解锁检测
7. **🔌 第三方工具** - PF_realm + 御坂美琴 + sing-box + 科技lion + NS论坛 + 酷雪云
8. **🚀 代理部署** - 一键部署 SOCKS5 代理（基于 Sing-box）
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
| IPv4优先 | 6 | 7 |
| IPv6优先 | 7 | 8 |
| 查看Xray配置 | 8 | 9 |
| Xray IPv6出站 | 9 | 10 |
| 恢复Xray默认 | 10 | 11 |
| 查看详细状态 | 11 | 12 |
| NS一键检测 | 12 | 13 |
| 服务器带宽测试 | 13 | 14 |
| 三网回程路由 | 14 | 15 |
| IP质量检测 | 15 | 16 |
| IP质量-IPv4 | 16 | 17 |
| 网络延迟检测 | 17 | 18 |
| 国际互联速度 | 18 | 19 |
| 媒体/AI解锁 | 19 | 20 |
| PF_realm转发 | 20 | 21 |
| 御坂美琴双协议 | 21 | 22 |
| F佬sing box | 22 | 23 |
| 科技lion脚本 | 23 | 24 |
| NS论坛cake调优 | 24 | 25 |
| 酷雪云脚本 | 25 | 26 |
| 部署SOCKS5代理 | 26 | 27 |

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
<summary>🌐 IPv4/IPv6 优先级设置</summary>

- **IPv4优先**：选项 **6**（未安装）/ **7**（已安装）
- **IPv6优先**：选项 **7**（未安装）/ **8**（已安装）

修改 `/etc/gai.conf` 配置，自动显示当前出口 IP

</details>

<details>
<summary>🔐 Xray 配置管理</summary>

- **查看配置**：选项 **8**（未安装）/ **9**（已安装）
- **IPv6出站**：选项 **9**（未安装）/ **10**（已安装）
- **恢复默认**：选项 **10**（未安装）/ **11**（已安装）

自动备份配置，失败自动回滚

</details>

<details>
<summary>🚀 一键部署 SOCKS5 代理</summary>

菜单选项 **26**（未安装）/ **27**（已安装）

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

# BBR v3 终极优化脚本 - Ultimate Edition

🚀 **XanMod 内核 + BBR v3 + 专业队列算法调优**  
一键安装 XanMod 内核，启用 BBR v3 拥塞控制，并根据使用场景选择最佳队列算法（FQ/FQ_PIE/CAKE）。

> **版本**: 2.0 Ultimate Edition  
> **视频教程**: [B站教程](https://www.bilibili.com/video/BV14K421x7BS)

---

## 🌟 核心特性

### ✨ 三大核心功能
1. **XanMod 内核安装**：官方源安装，支持 x86_64 & ARM64 架构
2. **BBR v3 启用**：最新一代拥塞控制算法
3. **队列算法优化**：FQ / FQ_PIE / CAKE 三种专业方案

### 🎯 适用场景
- **通用 Web 服务器**：BBR + FQ（高吞吐量）
- **游戏/实时应用**：BBR + FQ_PIE（超低延迟）
- **VPN/多用户场景**：BBR + CAKE（智能流量整形）

---

## 🚀 快速开始

### 一键运行（交互式菜单）

```bash
wget https://raw.githubusercontent.com/Eric86777/vps-tcp-tune/main/net-tcp-tune.sh
chmod +x net-tcp-tune.sh
sudo ./net-tcp-tune.sh
```

### 命令行模式（非交互）

```bash
# 仅安装 XanMod 内核
sudo ./net-tcp-tune.sh --install

# 重启后配置 BBR
sudo ./net-tcp-tune.sh --configure
```

---

## 📋 支持系统

| 系统 | 架构 | 支持状态 |
|------|------|---------|
| **Debian 10+** | x86_64 | ✅ 完整支持 |
| **Ubuntu 20.04+** | x86_64 | ✅ 完整支持 |
| **Debian/Ubuntu** | ARM64 | ✅ 专用脚本 |
| 其他发行版 | - | ❌ 不支持 |

---

## 🎛️ 队列算法对比

| 算法 | 延迟 | 吞吐量 | 最佳场景 |
|------|------|--------|---------|
| **FQ** | 中等 | ★★★★★ | 通用高性能服务器、Web 服务、API、文件传输 |
| **FQ_PIE** | 极低 | ★★★★☆ | 游戏服务器、实时视频、VoIP |
| **CAKE** | 低 | ★★★★☆ | VPN 服务器、多用户共享、智能流量整形 |

### 🔬 实测性能数据（200ms RTT 跨国链路）

```
默认 + Cubic:      50 Mbps，延迟 200ms
BBR (无队列):     120 Mbps，延迟 180ms
BBR + FQ:         150 Mbps，延迟 150ms
BBR + FQ_PIE:     140 Mbps，延迟  90ms ⭐ (延迟降低 70%)
BBR + CAKE:       145 Mbps，延迟 120ms
```

---

## 🛠️ 使用流程

### 第一步：安装 XanMod 内核

```bash
sudo ./net-tcp-tune.sh
# 选择菜单选项 1
```

脚本会自动：
- ✅ 检测 CPU 架构（x86-64-v2/v3/v4 自动适配）
- ✅ 添加 XanMod 官方仓库
- ✅ 安装对应内核版本
- ✅ 检查磁盘空间（需要 3GB+）
- ✅ 创建 SWAP（如无虚拟内存）

⚠️ **安装完成后必须重启系统！**

### 第二步：配置 BBR + 队列算法

重启后再次运行脚本：

```bash
sudo ./net-tcp-tune.sh
# 选择菜单选项 3-6
```

**推荐配置：**
- 选项 3：交互式选择（查看详细对比）
- 选项 4：快速启用 BBR + FQ（通用场景）
- 选项 5：快速启用 BBR + FQ_PIE（游戏/低延迟）
- 选项 6：快速启用 BBR + CAKE（VPN/多用户）

---

## 📊 验证配置

### 检查 BBR 状态

```bash
# 查看拥塞控制算法
sysctl net.ipv4.tcp_congestion_control

# 查看队列算法
sysctl net.core.default_qdisc

# 验证 BBR 版本
modinfo tcp_bbr | grep version
```

### 预期输出

```
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq (或 fq_pie/cake)
version:        3
```

---

## 🔧 配置文件说明

脚本生成的配置文件位于：

```
/etc/sysctl.d/99-bbr-ultimate.conf
```

**配置内容：**
```bash
# 队列调度算法
net.core.default_qdisc=fq

# 拥塞控制算法
net.ipv4.tcp_congestion_control=bbr

# TCP 缓冲区优化
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
```

---

## 📈 性能测试建议

### 1. 带宽测试

```bash
# 使用 iperf3
iperf3 -c speedtest.example.com

# 或使用 wget
wget -O /dev/null http://cachefly.cachefly.net/10gb.test
```

### 2. 延迟测试

```bash
# 本地延迟
ping -c 100 8.8.8.8

# 跨国延迟
ping -c 100 目标服务器IP
```

### 3. 实时监控

```bash
# 查看当前连接的拥塞控制算法
ss -ti | grep bbr

# 查看队列状态
tc -s qdisc show
```

---

## 🗑️ 卸载说明

### 卸载 XanMod 内核

```bash
sudo ./net-tcp-tune.sh
# 选择菜单选项 2（仅在已安装 XanMod 后显示）
```

脚本会自动：
- 移除所有 XanMod 内核包
- 删除配置文件 `/etc/sysctl.d/99-bbr-ultimate.conf`
- 更新 GRUB 引导
- 询问是否重启

### 手动清理

```bash
# 卸载内核
sudo apt purge -y 'linux-*xanmod1*'

# 删除配置
sudo rm -f /etc/sysctl.d/99-bbr-ultimate.conf

# 更新引导
sudo update-grub

# 重启
sudo reboot
```

---

## ⚠️ 注意事项

1. **磁盘空间**：确保根分区至少有 3GB 可用空间
2. **内存要求**：低内存 VPS 会自动创建 1GB SWAP
3. **备份建议**：升级内核前建议备份重要数据
4. **重启需求**：内核升级后必须重启才能生效
5. **兼容性**：仅支持 Debian/Ubuntu，不支持 CentOS/RHEL

---

## 🆚 与旧版脚本区别

| 特性 | 旧版（BDP调优） | 新版（BBR v3 Ultimate） |
|------|----------------|----------------------|
| 内核升级 | ❌ 不支持 | ✅ 自动安装 XanMod |
| BBR 版本 | 系统自带（v1/v2） | ✅ BBR v3 |
| 队列算法 | 仅 FQ | ✅ FQ/FQ_PIE/CAKE 可选 |
| 场景优化 | 通用 | ✅ 游戏/VPN/Web 专项优化 |
| ARM 支持 | ❌ 无 | ✅ ARM64 专用脚本 |

---

## 🤝 参考资料

- **XanMod 官网**: [https://xanmod.org/](https://xanmod.org/)
- **BBR v3 论文**: [Google BBR v3](https://github.com/google/bbr)
- **队列算法文档**:
  - [FQ (Fair Queue)](https://www.kernel.org/doc/html/latest/networking/fq.html)
  - [FQ_PIE](https://tools.ietf.org/html/rfc8033)
  - [CAKE](https://www.bufferbloat.net/projects/codel/wiki/CAKE/)

---

## 📄 License

MIT

---

## 💬 常见问题

### Q: BBR v3 和 BBR v2 有什么区别？
A: BBR v3 改进了拥塞窗口计算，减少了丢包，提升了跨国高延迟链路的性能。

### Q: 为什么游戏服务器推荐 FQ_PIE？
A: FQ_PIE 使用主动队列管理（AQM），可降低缓冲区膨胀，减少延迟抖动，适合实时应用。

### Q: CAKE 和 FQ 的主要区别？
A: CAKE 内置智能流量整形，能自动识别和优先处理游戏/视频流量，适合多用户共享场景。

### Q: ARM 服务器能用吗？
A: 可以，脚本会自动检测 ARM64 架构并调用专用安装脚本。

### Q: 安装失败怎么办？
A: 检查磁盘空间、网络连接，确保系统是 Debian/Ubuntu，可尝试更换软件源。

---

## 🌐 相关链接

- **GitHub**: [https://github.com/Eric86777/vps-tcp-tune](https://github.com/Eric86777/vps-tcp-tune)
- **问题反馈**: [Issues](https://github.com/Eric86777/vps-tcp-tune/issues)
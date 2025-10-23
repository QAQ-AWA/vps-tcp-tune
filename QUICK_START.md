# 🚀 快速使用指南

## 📖 你的问题：命令太长怎么办？

**原始命令**（太长了！）：
```bash
bash <(wget -qO- https://raw.githubusercontent.com/QAQ-AWA/vps-tcp-tune/main/net-tcp-tune.sh)
```

**解决方案**：安装快捷别名，以后只需输入 `bbr` 即可！

---

## ⚡ 3步搞定快捷方式

### 第一步：安装快捷别名（只需一次）

```bash
bash <(wget -qO- https://raw.githubusercontent.com/QAQ-AWA/vps-tcp-tune/main/install-alias.sh)
```

### 第二步：重新加载配置

```bash
# 如果使用 zsh（大多数现代系统）
source ~/.zshrc

# 如果使用 bash（传统系统）
source ~/.bashrc
```

### 第三步：享受快捷命令

```bash
bbr        # 只需输入这个！🎉
```

---

## 🎯 快捷命令

安装后，只需输入一个命令：

| 命令 | 说明 | 长度 |
|------|------|------|
| `bbr` | 一键运行⭐⭐⭐⭐⭐ | 3个字符 |

**对比原始命令**：
- 原始：95个字符
- `bbr`：3个字符
- **缩短了 96.8%！** 🎉

---

## 💡 工作原理

### 原始命令解析

```bash
bash <(wget -qO- https://raw.githubusercontent.com/.../net-tcp-tune.sh)
     │  │      └─── GitHub上的脚本链接
     │  └────────── 下载但不保存到本地（输出到标准输出）
     └───────────── 直接执行下载的内容
```

**特点**：
- ✅ 每次都是最新版
- ✅ 不占用本地空间
- ❌ 命令太长不好记

### 快捷别名原理

安装别名后，在你的配置文件（`~/.zshrc` 或 `~/.bashrc`）中会自动写入：

```bash
vtt_net_tcp_tune_runner() {
    local owner="\${VTT_REPO_OWNER:-QAQ-AWA}"
    local name="\${VTT_REPO_NAME:-vps-tcp-tune}"
    local branch="\${VTT_REPO_BRANCH:-main}"
    local primary="https://raw.githubusercontent.com/\${owner}/\${name}/\${branch}/net-tcp-tune.sh"
    local cdn="https://cdn.jsdelivr.net/gh/\${owner}/\${name}@\${branch}/net-tcp-tune.sh"
    # ... 省略: 自动选择 curl / wget，并在主源失败时启用 jsDelivr CDN 回退
}
alias bbr='vtt_net_tcp_tune_runner'
```

**当你输入 `bbr` 时**：
1. Shell 自动展开为完整命令
2. 使用时间戳参数绕过缓存
3. 下载并运行最新版脚本

**优点**：
- ✅ 超短命令（只需3个字符）
- ✅ 永久有效（安装一次，终身使用）
- ✅ 自动获取最新版（每次都是最新）
- ✅ 随处可用（所有终端都生效）

---

## 🔧 其他方式

### 方式2：下载本地脚本

如果你想保存到本地：

```bash
# 下载主脚本
wget https://raw.githubusercontent.com/QAQ-AWA/vps-tcp-tune/main/net-tcp-tune.sh
chmod +x net-tcp-tune.sh

# 运行
./net-tcp-tune.sh
```

### 方式3：使用快速启动脚本

```bash
# 下载快速启动脚本
wget https://raw.githubusercontent.com/QAQ-AWA/vps-tcp-tune/main/bbr.sh
chmod +x bbr.sh

# 运行（会自动下载并运行最新版）
./bbr.sh
```

---

## 📊 对比表

| 方式 | 命令长度 | 保存本地 | 最新版 | 推荐度 |
|------|---------|---------|--------|-------|
| **原始命令** | 95字符 | ❌ | ✅ | ⭐⭐⭐ |
| **快捷别名（bbr）** | 3字符 | ❌ | ✅ | ⭐⭐⭐⭐⭐ |
| **本地脚本** | 18字符 | ✅ | ❌ | ⭐⭐⭐⭐ |
| **快速启动（bbr.sh）** | 9字符 | ✅ | ✅ | ⭐⭐⭐⭐⭐ |

---

## ❓ 常见问题

### Q1: 别名会永久有效吗？
**A**: 是的！安装一次后，只要不删除配置文件，永久有效。

### Q2: 重启服务器后还能用吗？
**A**: 能用！别名配置保存在你的 Shell 配置文件中，会自动加载。

### Q3: 我用的是 Windows/Mac，能用吗？
**A**: 
- **Mac**：完全可以！（你现在就是Mac）
- **Windows**：需要 WSL（Windows Subsystem for Linux）
- **VPS服务器**：完全可以！（推荐）

### Q4: 安装别名后，原始命令还能用吗？
**A**: 当然可以！别名只是快捷方式，不影响原始命令。

### Q5: 我想卸载别名怎么办？
**A**: 编辑你的配置文件，删除相关行：
```bash
# 编辑配置文件
vim ~/.zshrc    # 或 ~/.bashrc

# 删除这一行：
# alias bbr="..."

# 重新加载
source ~/.zshrc
```

---

## 🎯 推荐使用场景

### 场景1：你的VPS服务器（最推荐）
```bash
# 第一次：安装别名
bash <(wget -qO- https://raw.githubusercontent.com/QAQ-AWA/vps-tcp-tune/main/install-alias.sh)
source ~/.bashrc

# 以后：直接使用
bbr
```

### 场景2：临时使用（不想安装）
```bash
# 下载快速启动脚本
wget https://raw.githubusercontent.com/QAQ-AWA/vps-tcp-tune/main/bbr.sh
chmod +x bbr.sh

# 使用
./bbr.sh
```

### 场景3：多台服务器
```bash
# 在每台服务器上都安装一次别名
# 以后在任何服务器上都只需输入 bbr
```

---

## 📞 需要帮助？

- **GitHub Issues**: https://github.com/QAQ-AWA/vps-tcp-tune/issues
- **完整文档**: 查看 [README.md](README.md)
- **视频教程**: [B站教程](https://www.bilibili.com/video/BV14K421x7BS)

---

**祝你使用愉快！** 🎉


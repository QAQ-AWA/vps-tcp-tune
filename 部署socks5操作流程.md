# Sing-box SOCKS5 独立部署完整指南（优化版）

## 📋 部署信息
- VPS IP: `示例IP`
- SOCKS5 端口: `23847`
- 用户名: `root108247217182`
- 密码: `jjeD0xTyMs2WkXpCGCZ8`
- 部署目录: `/etc/sbox_socks5/`

---

## 🔍 前置步骤：检查 Sing-box 安装

```bash
# 查找 sing-box 二进制程序（不是脚本！）
echo "=== 查找 sing-box 程序 ==="

# 方法1：检查常见位置
for path in /etc/sing-box/sing-box /usr/local/bin/sing-box /opt/sing-box/sing-box; do
    if [ -x "$path" ]; then
        file "$path" | grep -q "ELF" && echo "✅ 找到二进制程序: $path" && $path version
    fi
done

# 方法2：如果上面没找到，检查 sb 命令
if command -v sb &>/dev/null; then
    SB_PATH=$(which sb)
    if file "$SB_PATH" | grep -q "ELF"; then
        echo "✅ sb 是二进制程序: $SB_PATH"
    else
        echo "⚠️  sb 是管理脚本，不是二进制程序"
        echo "需要找到真正的 sing-box 程序"
    fi
fi
```

**⚠️ 重要提醒：**
- **`/usr/bin/sb`** 通常是管理脚本，**不能直接用于服务**
- 真正的 sing-box 程序通常在：
  - `/etc/sing-box/sing-box`
  - `/usr/local/bin/sing-box`
  - `/opt/sing-box/sing-box`
- 必须使用**二进制程序**，不能用脚本

---

## 🛠️ 第一步：创建SOCKS5专用目录

```bash
# 创建专用目录
mkdir -p /etc/sbox_socks5

# 进入目录
cd /etc/sbox_socks5
```

---

## 📝 第二步：创建SOCKS5配置文件

### 2.1 创建配置文件
```bash
nano /etc/sbox_socks5/config.json
```

### 2.2 配置文件内容
```json
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
      "listen_port": 23847,
      "users": [
        {
          "username": "root108247217182",
          "password": "jjeD0xTyMs2WkXpCGCZ8"
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
```

### 2.3 保存并退出
- 按 `Ctrl + X`
- 按 `Y` 确认保存
- 按 `Enter` 确认文件名

---

## 🔧 第三步：创建systemd服务文件（智能检测版）

### 方案A：自动检测并创建（推荐）

```bash
# 一键自动创建服务文件（智能检测二进制程序）
cat << 'SERVICEEOF' > /tmp/create_socks5_service.sh
#!/bin/bash

echo "=== 查找 sing-box 二进制程序 ==="

SINGBOX_CMD=""

# 优先查找常见的二进制程序位置
for path in /etc/sing-box/sing-box /usr/local/bin/sing-box /opt/sing-box/sing-box; do
    if [ -x "$path" ] && [ ! -L "$path" ]; then
        # 验证是 ELF 二进制文件，不是脚本
        if file "$path" 2>/dev/null | grep -q "ELF"; then
            SINGBOX_CMD="$path"
            echo "✅ 找到二进制程序: $SINGBOX_CMD"
            break
        fi
    fi
done

# 如果没找到，检查 PATH 中的命令
if [ -z "$SINGBOX_CMD" ]; then
    for cmd in sing-box sb; do
        if command -v "$cmd" &>/dev/null; then
            cmd_path=$(which "$cmd")
            if file "$cmd_path" 2>/dev/null | grep -q "ELF"; then
                SINGBOX_CMD="$cmd_path"
                echo "✅ 找到二进制程序: $SINGBOX_CMD"
                break
            else
                echo "⚠️  $cmd_path 是脚本，跳过"
            fi
        fi
    done
fi

if [ -z "$SINGBOX_CMD" ]; then
    echo "❌ 未找到 sing-box 二进制程序"
    echo "请检查 sing-box 是否已正确安装"
    exit 1
fi

# 验证程序能运行
echo ""
echo "=== 验证程序版本 ==="
$SINGBOX_CMD version || {
    echo "❌ 程序无法运行"
    exit 1
}

# 创建服务文件
echo ""
echo "=== 创建服务文件 ==="
cat > /etc/systemd/system/sbox-socks5.service << EOF
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
EOF

echo "✅ 服务文件已创建，使用程序: $SINGBOX_CMD"
echo ""
echo "=== 服务文件内容 ==="
grep "ExecStart" /etc/systemd/system/sbox-socks5.service

SERVICEEOF

# 执行脚本
bash /tmp/create_socks5_service.sh
```

### 方案B：手动创建（如果方案A失败）

```bash
# 1. 先找到真正的 sing-box 二进制程序
echo "=== 查找 sing-box 程序 ==="

# 检查常见位置
ls -lh /etc/sing-box/sing-box 2>/dev/null
ls -lh /usr/local/bin/sing-box 2>/dev/null
ls -lh /opt/sing-box/sing-box 2>/dev/null

# 验证是否是二进制文件（不是脚本）
file /etc/sing-box/sing-box 2>/dev/null

# 2. 记住你找到的路径（比如 /etc/sing-box/sing-box）
# 3. 创建服务文件
nano /etc/systemd/system/sbox-socks5.service
```

**配置示例（根据实际路径修改 ExecStart 行）：**

```ini
[Unit]
Description=Sing-box SOCKS5 Service
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
# ⚠️ 重要：这里填你找到的二进制程序路径
# 常见路径示例：
# /etc/sing-box/sing-box (F佬脚本常用)
# /usr/local/bin/sing-box (官方安装)
# /opt/sing-box/sing-box (自定义位置)
ExecStart=/etc/sing-box/sing-box run -c /etc/sbox_socks5/config.json
ExecReload=/bin/kill -HUP $MAINPID
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
```

保存并退出（Ctrl+X → Y → Enter）

**⚠️ 关键提醒：**
- **不要使用** `/usr/bin/sb`，这是管理脚本
- **必须使用** 真正的二进制程序（用 `file` 命令验证显示 ELF）

---

## 🔐 第四步：设置文件权限

```bash
# 设置配置文件权限（仅root可读写）
chmod 600 /etc/sbox_socks5/config.json

# 设置服务文件权限
chmod 644 /etc/systemd/system/sbox-socks5.service
```

---

## 🚀 第五步：启动SOCKS5服务

### 5.1 重载systemd配置
```bash
systemctl daemon-reload
```

### 5.2 启用并启动服务
```bash
# 设置开机自启
systemctl enable sbox-socks5

# 启动服务
systemctl start sbox-socks5

# 检查服务状态
systemctl status sbox-socks5
```

### 5.3 预期输出
如果一切正常，你应该看到类似以下输出：
```
● sbox-socks5.service - Sing-box SOCKS5 Service
   Loaded: loaded (/etc/systemd/system/sbox-socks5.service; enabled; vendor preset: enabled)
   Active: active (running) since...
   Main PID: xxxx (sing-box)
   ...
```

---

## ✅ 第六步：验证部署

### 6.1 检查服务状态
```bash
# 检查服务是否运行
systemctl is-active sbox-socks5
```

### 6.2 检查端口监听
```bash
# 检查端口是否在监听
ss -tulpn | grep 23847
```

### 6.3 验证配置文件语法
```bash
# 找到你的 sing-box 程序路径
SINGBOX=$(grep ExecStart /etc/systemd/system/sbox-socks5.service | awk '{print $2}')

# 验证配置
$SINGBOX check -c /etc/sbox_socks5/config.json

# 或者手动指定（根据你的实际路径）
/etc/sing-box/sing-box check -c /etc/sbox_socks5/config.json
```

### 6.4 本地测试
```bash
# 在服务器上测试连接（记得替换成你的实际IP）
curl --socks5-hostname root108247217182:jjeD0xTyMs2WkXpCGCZ8@你的服务器IP:23847 http://httpbin.org/ip
```

---

## 🔍 第七步：连接测试

### 7.1 SOCKS5连接信息
```
服务器地址: 示例IP
端口: 23847
协议: SOCKS5
用户名: root108247217182
密码: jjeD0xTyMs2WkXpCGCZ8
```

### 7.2 客户端测试（在你的本地电脑）
```bash
# 测试HTTP请求
curl --socks5-hostname root108247217182:jjeD0xTyMs2WkXpCGCZ8@108.247.217.182:23847 http://httpbin.org/ip
```

### 7.3 浏览器测试
1. 打开浏览器代理设置
2. 设置SOCKS5代理：
   - 地址：`示例IP`
   - 端口：`23847`
   - 用户名：`root108247217182`
   - 密码：`jjeD0xTyMs2WkXpCGCZ8`
3. 访问 `http://whatismyipaddress.com` 检查IP是否为VPS IP

---

## 🔧 故障排除

### 常见问题及解决方案

#### 问题1：服务启动失败（错误码 203/EXEC）
**原因：** sing-box 命令路径不正确

```bash
# 1. 查看详细错误信息
journalctl -u sbox-socks5 -n 50 --no-pager

# 2. 确认你的 sing-box 命令
which sing-box
which sb

# 3. 如果找到了，修复服务文件
# 假设你的命令是 /usr/bin/sb
nano /etc/systemd/system/sbox-socks5.service
# 修改 ExecStart 行为正确的路径

# 4. 重新加载并启动
systemctl daemon-reload
systemctl restart sbox-socks5
```

#### 问题2：使用了管理脚本而不是二进制程序
**症状：** 服务显示菜单，端口不监听

```bash
# 检查当前服务使用的程序
grep ExecStart /etc/systemd/system/sbox-socks5.service

# 验证是否是脚本
CURRENT_CMD=$(grep ExecStart /etc/systemd/system/sbox-socks5.service | awk '{print $2}')
file $CURRENT_CMD

# 如果显示 "shell script" 或 "Bourne-Again shell script"，说明用错了
# 正确应该显示 "ELF 64-bit LSB executable"

# 修复：找到真正的二进制程序
ls -lh /etc/sing-box/sing-box
file /etc/sing-box/sing-box

# 更新服务文件
nano /etc/systemd/system/sbox-socks5.service
# 修改 ExecStart 为正确的路径

# 重启
systemctl daemon-reload
systemctl restart sbox-socks5
```

#### 问题3：配置文件语法错误
```bash
# 查看当前使用的程序
SINGBOX=$(grep ExecStart /etc/systemd/system/sbox-socks5.service | awk '{print $2}')

# 检查配置文件语法
$SINGBOX check -c /etc/sbox_socks5/config.json

# 查看配置文件
cat /etc/sbox_socks5/config.json
```

#### 问题4：端口被占用
```bash
# 查看端口占用
lsof -i :23847

# 更换端口（修改配置文件中的listen_port）
nano /etc/sbox_socks5/config.json
```

#### 问题5：无法连接
```bash
# 检查防火墙
iptables -L

# 检查云服务商安全组设置（重要！）
# 需要在云服务商控制面板开放 TCP 23847 端口
```

#### 问题6：重启服务
```bash
# 重启SOCKS5服务
systemctl restart sbox-socks5

# 查看服务状态
systemctl status sbox-socks5 --no-pager

# 查看实时日志
journalctl -u sbox-socks5 -f
```

---

## 📋 管理命令速查

### 服务管理
```bash
# 启动服务
systemctl start sbox-socks5

# 停止服务
systemctl stop sbox-socks5

# 重启服务
systemctl restart sbox-socks5

# 查看状态
systemctl status sbox-socks5

# 查看日志
journalctl -u sbox-socks5 -f

# 禁用服务
systemctl disable sbox-socks5

# 启用服务
systemctl enable sbox-socks5
```

### 配置管理
```bash
# 编辑配置
nano /etc/sbox_socks5/config.json

# 查看当前使用的 sing-box 程序
grep ExecStart /etc/systemd/system/sbox-socks5.service

# 检查配置语法（使用你的实际路径）
# 方法1：自动获取路径
SINGBOX=$(grep ExecStart /etc/systemd/system/sbox-socks5.service | awk '{print $2}')
$SINGBOX check -c /etc/sbox_socks5/config.json

# 方法2：手动指定（根据实际情况）
/etc/sing-box/sing-box check -c /etc/sbox_socks5/config.json

# 重载配置（修改配置后）
systemctl restart sbox-socks5
```

---

## ✅ 部署完成确认清单

- [ ] SSH成功连接到VPS
- [ ] **找到了真正的 sing-box 二进制程序（用 `file` 命令验证是 ELF 而不是 script）**
- [ ] **确认服务文件使用的是二进制程序路径（不是 `/usr/bin/sb` 脚本）**
- [ ] 创建了独立的配置目录 `/etc/sbox_socks5/`
- [ ] 配置文件 `config.json` 创建成功并设置正确权限
- [ ] systemd服务文件创建成功
- [ ] 配置文件语法验证通过（`<你的sing-box路径> check`）
- [ ] 服务启动成功并显示为 `active (running)`
- [ ] **端口23847正在监听（`ss -tulpn | grep 23847` 有输出）**
- [ ] 服务日志正常（没有显示交互式菜单）
- [ ] 本地测试连接成功（`curl --socks5 127.0.0.1:23847`）
- [ ] **重要：云服务商安全组已开放 TCP 23847 端口**
- [ ] 客户端测试连接成功
- [ ] 确认与现有节点无冲突

**关键验证命令：**
```bash
# 1. 验证使用的是二进制程序
grep ExecStart /etc/systemd/system/sbox-socks5.service
file $(grep ExecStart /etc/systemd/system/sbox-socks5.service | awk '{print $2}')
# 应该显示 "ELF 64-bit LSB executable"

# 2. 验证端口监听
ss -tulpn | grep 23847
# 应该有输出

# 3. 验证服务运行正常
systemctl status sbox-socks5
# 应该显示 "active (running)"

# 4. 测试连接
curl --socks5-hostname root108247217182:jjeD0xTyMs2WkXpCGCZ8@127.0.0.1:23847 http://httpbin.org/ip
# 应该返回你的服务器IP
```

---

## 🎉 恭喜！

你的SOCKS5代理已经成功部署！现在你可以使用以下信息连接：

**连接信息：**
- 服务器：`示例IP`
- 端口：`23847`
- 用户名：`root108247217182`
- 密码：`jjeD0xTyMs2WkXpCGCZ8`
- 协议：`SOCKS5`

**重要提醒：**
此SOCKS5代理完全独立运行，不会影响你现有的VL/VM/HY2/TUN5节点。如果遇到连接问题，请首先检查云服务商的安全组/防火墙设置是否开放了23847端口。

---

## 🚀 快速部署脚本（一键完成）

如果你想快速完成整个部署，可以使用这个自动化脚本：

```bash
# 一键部署 SOCKS5 代理
cat << 'DEPLOYEOF' > /tmp/deploy_socks5.sh
#!/bin/bash

set -e

echo "====================================="
echo "   Sing-box SOCKS5 快速部署脚本"
echo "====================================="
echo ""

# 检测 sing-box 二进制程序
echo "[1/7] 检测 sing-box 安装..."

SINGBOX_CMD=""

# 优先查找常见的二进制程序位置
for path in /etc/sing-box/sing-box /usr/local/bin/sing-box /opt/sing-box/sing-box; do
    if [ -x "$path" ] && [ ! -L "$path" ]; then
        # 验证是 ELF 二进制文件，不是脚本
        if file "$path" 2>/dev/null | grep -q "ELF"; then
            SINGBOX_CMD="$path"
            echo "✅ 找到二进制程序: $SINGBOX_CMD"
            break
        fi
    fi
done

# 如果没找到，检查 PATH 中的命令
if [ -z "$SINGBOX_CMD" ]; then
    for cmd in sing-box sb; do
        if command -v "$cmd" &>/dev/null; then
            cmd_path=$(which "$cmd")
            if file "$cmd_path" 2>/dev/null | grep -q "ELF"; then
                SINGBOX_CMD="$cmd_path"
                echo "✅ 找到二进制程序: $SINGBOX_CMD"
                break
            else
                echo "⚠️  $cmd_path 是脚本，跳过"
            fi
        fi
    done
fi

if [ -z "$SINGBOX_CMD" ]; then
    echo "❌ 未找到 sing-box 二进制程序"
    echo "请先正确安装 sing-box"
    exit 1
fi

$SINGBOX_CMD version

# 创建目录
echo ""
echo "[2/7] 创建配置目录..."
mkdir -p /etc/sbox_socks5
echo "✅ 目录创建成功"

# 创建配置文件
echo ""
echo "[3/7] 创建配置文件..."
cat > /etc/sbox_socks5/config.json << 'CONFIGEOF'
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
      "listen_port": 23847,
      "users": [
        {
          "username": "root108247217182",
          "password": "jjeD0xTyMs2WkXpCGCZ8"
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
echo "✅ 配置文件创建成功"

# 验证配置
echo ""
echo "[4/7] 验证配置文件语法..."
$SINGBOX_CMD check -c /etc/sbox_socks5/config.json
echo "✅ 配置文件语法正确"

# 创建服务文件
echo ""
echo "[5/7] 创建 systemd 服务..."
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
echo "✅ 服务文件创建成功"

# 启动服务
echo ""
echo "[6/7] 启动服务..."
systemctl daemon-reload
systemctl enable sbox-socks5
systemctl start sbox-socks5

# 等待服务启动
sleep 3

# 验证部署
echo ""
echo "[7/7] 验证部署..."
echo ""

if systemctl is-active --quiet sbox-socks5; then
    echo "✅ 服务状态: Running"
else
    echo "❌ 服务状态: Failed"
    systemctl status sbox-socks5 --no-pager
    exit 1
fi

if ss -tulpn | grep -q 23847; then
    echo "✅ 端口监听: 23847"
else
    echo "❌ 端口未监听"
    exit 1
fi

echo ""
echo "====================================="
echo "   🎉 部署成功！"
echo "====================================="
echo ""
echo "连接信息："
echo "  服务器: $(curl -s --max-time 3 ifconfig.me || echo '请手动获取')"
echo "  端口: 23847"
echo "  用户名: root108247217182"
echo "  密码: jjeD0xTyMs2WkXpCGCZ8"
echo "  协议: SOCKS5"
echo ""
echo "⚠️  重要提醒："
echo "  1. 确保云服务商安全组已开放 TCP 23847 端口"
echo "  2. 查看日志: journalctl -u sbox-socks5 -f"
echo "  3. 重启服务: systemctl restart sbox-socks5"
echo ""

DEPLOYEOF

# 执行部署脚本
bash /tmp/deploy_socks5.sh
```

这个脚本会自动完成所有步骤，包括：
- ✅ 检测 sing-box 命令
- ✅ 创建配置目录
- ✅ 生成配置文件
- ✅ 验证配置语法
- ✅ 创建 systemd 服务
- ✅ 启动并验证服务

**如果部署失败，请按照前面的手动步骤逐步排查。**
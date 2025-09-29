# vps-tcp-tune

来自 NodeSeek Cake 调优脚本的二次推荐：**BBR + fq TCP 网络调优脚本**  
一键优化 VPS 网络，自动计算合适的缓冲区大小，清理冲突配置，启用 BBR 拥塞控制。

---

## 🚀 一键运行

在你的 VPS 上执行以下命令即可：

```bash
wget https://raw.githubusercontent.com/Eric86777/vps-tcp-tune/main/net-tcp-tune.sh
chmod +x net-tcp-tune.sh
sudo ./net-tcp-tune.sh
```

---

## ⚙️ 参数模式

脚本支持自动检测，也可以手动传参数（非交互模式）。**推荐先下载再执行**：

```bash
# 方法1：下载后执行（推荐）
wget https://raw.githubusercontent.com/Eric86777/vps-tcp-tune/main/net-tcp-tune.sh
chmod +x net-tcp-tune.sh
sudo ./net-tcp-tune.sh -y --bw 1000 --rtt 80
```

```bash
# 方法2：一行命令（备用）
curl -fsSL https://raw.githubusercontent.com/Eric86777/vps-tcp-tune/main/net-tcp-tune.sh -o net-tcp-tune.sh && chmod +x net-tcp-tune.sh && sudo ./net-tcp-tune.sh -y --bw 1000 --rtt 80
```

**参数说明：**
- `-y` ：跳过交互，使用自动检测或手动输入的参数
- `--bw` ：带宽，单位 Mbps（默认 1000）
- `--rtt` ：延迟，单位 ms（默认自动检测，不成功时用 150）

> **注意**：避免使用 `curl ... | bash` 管道执行，可能因交互冲突导致脚本失败

---

## 🔄 回滚

如果需要恢复配置，可以执行：

```bash
ROLLBACK=1 sudo ./net-tcp-tune.sh
```

脚本会恢复之前的备份文件，并删除生成的 `999-net-bbr-fq.conf`。

---

## 📌 功能特性

- 自动检测内存大小、RTT 延迟
- 计算 BDP 并选择合理的缓冲区大小
- 清理 `/etc/sysctl.conf` 和 `/etc/sysctl.d/` 中的冲突项
- 启用 BBR + fq 拥塞控制
- 结果自动保存到 `/etc/sysctl.d/999-net-bbr-fq.conf`

---

## 📄 License

MIT
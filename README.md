# 打印机扫描 FTP 服务器部署

## 快速部署

### 1. 上传脚本到云服务器

```bash
scp setup_ftp.sh root@你的服务器IP:/root/
```

### 2. 修改配置

SSH 登录服务器后，编辑脚本开头的配置：

```bash
nano /root/setup_ftp.sh
```

必须修改的项：
- `FTP_PASS` — 改为你自己的强密码
- `SERVER_IP` — 如果自动获取不准确，手动填入公网 IP

### 3. 执行部署

```bash
chmod +x /root/setup_ftp.sh
sudo bash /root/setup_ftp.sh
```

### 4. 云服务器安全组

在云服务商控制台（阿里云/腾讯云/华为云等），放通以下端口：

| 端口 | 协议 | 用途 |
|------|------|------|
| 21 | TCP | FTP 控制连接 |
| 40000-40100 | TCP | FTP 被动模式数据传输 |

### 5. 打印机配置

在打印机的「扫描后发送」界面填入：

| 字段 | 值 |
|------|-----|
| 通信协议 | FTP |
| 主机名 | 你的服务器公网 IP |
| 文件夹路径 | /scans |
| 用户名 | scanner |
| 密码 | 你设置的密码 |

## 常用维护命令

```bash
# 查看 FTP 服务状态
systemctl status vsftpd

# 查看传输日志
tail -f /var/log/vsftpd.log

# 查看已接收的扫描文件
ls -la /home/scanner/ftp/scans/

# 重启服务
systemctl restart vsftpd
```

## 故障排查

```bash
# 本地测试 FTP 连接
ftp localhost

# 检查端口监听
ss -tlnp | grep 21

# 查看 vsftpd 日志
journalctl -u vsftpd -f
```

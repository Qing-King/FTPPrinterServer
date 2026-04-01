# 打印机扫描 FTP 服务器部署

## 快速部署

```bash
git clone git@github.com:Qing-King/FTPPrinterServer.git
cd FTPPrinterServer
```

### 1. 修改配置

编辑两个脚本开头的配置区域：

```bash
nano setup_ftp.sh   # 修改 FTP_PASS
nano setup_web.sh   # 修改 WEB_PASS
```

### 2. 部署 FTP 服务器

```bash
sudo bash setup_ftp.sh
```

### 3. 部署 Web 文件管理器

```bash
sudo bash setup_web.sh
```

部署完成后，浏览器访问 `http://你的服务器IP:8080` 即可在线查看和下载扫描文件。

### 4. 云服务器安全组

在云服务商控制台（阿里云/腾讯云/华为云等），放通以下端口：

| 端口 | 协议 | 用途 |
|------|------|------|
| 21 | TCP | FTP 控制连接 |
| 8080 | TCP | Web 文件管理器 |
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
# 查看服务状态
systemctl status vsftpd
systemctl status filebrowser

# 查看传输日志
tail -f /var/log/vsftpd.log

# 查看已接收的扫描文件
ls -la /home/scanner/ftp/scans/

# 重启服务
systemctl restart vsftpd
systemctl restart filebrowser
```

## 故障排查

```bash
# 本地测试 FTP 连接
ftp localhost

# 检查端口监听
ss -tlnp | grep -E '21|8080'

# 查看日志
journalctl -u vsftpd -f
journalctl -u filebrowser -f
```

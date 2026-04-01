#!/bin/bash
# ============================================
# FTP 服务器一键部署脚本 (Ubuntu)
# 用途：配合打印机扫描发送功能
# ============================================

set -e

# ---------- 配置区域（请根据实际情况修改） ----------
FTP_USER="scanner"           # FTP 登录用户名
FTP_PASS="YourStrongPass123" # FTP 登录密码（请修改为强密码）
FTP_ROOT="/home/$FTP_USER/ftp"      # FTP 登录后的根目录
FTP_DIR="$FTP_ROOT/scans"           # 扫描文件存储目录
PASV_MIN=40000               # 被动模式端口范围（起始）
PASV_MAX=40100               # 被动模式端口范围（结束）
SERVER_IP=""                 # 云服务器公网 IP（留空则自动获取）
# ---------------------------------------------------

echo "=========================================="
echo "  FTP 服务器部署脚本 - 打印机扫描专用"
echo "=========================================="

# 自动获取公网 IP
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(curl -s ifconfig.me || curl -s icanhazip.com)
    echo "[INFO] 自动检测公网 IP: $SERVER_IP"
fi

# 1. 安装 vsftpd
echo "[1/6] 安装 vsftpd..."
apt update -y
apt install -y vsftpd

# 2. 创建 FTP 用户
echo "[2/6] 创建 FTP 用户: $FTP_USER"
if id "$FTP_USER" &>/dev/null; then
    echo "  用户 $FTP_USER 已存在，跳过创建"
else
    useradd -m -s /usr/sbin/nologin "$FTP_USER"
    echo "$FTP_USER:$FTP_PASS" | chpasswd
    echo "  用户创建完成"
fi

# 允许 nologin 用户使用 FTP
echo "/usr/sbin/nologin" >> /etc/shells
sort -u /etc/shells -o /etc/shells

# 3. 创建扫描文件目录
echo "[3/6] 创建扫描文件目录: $FTP_DIR"
mkdir -p "$FTP_ROOT" "$FTP_DIR"
# vsftpd 要求 chroot 根目录不可写，因此根目录交给 root 持有
chown root:root "$FTP_ROOT"
chmod 555 "$FTP_ROOT"
# 扫描文件子目录可写
chown -R "$FTP_USER":"$FTP_USER" "$FTP_DIR"
chmod 755 "$FTP_DIR"

# 4. 备份并写入 vsftpd 配置
echo "[4/6] 配置 vsftpd..."
[ -f /etc/vsftpd.conf ] && cp /etc/vsftpd.conf /etc/vsftpd.conf.bak

cat > /etc/vsftpd.conf << EOF
# ---- 基本配置 ----
listen=YES
listen_ipv6=NO

# ---- 访问控制 ----
anonymous_enable=NO
local_enable=YES
write_enable=YES

# ---- 限制用户在主目录 ----
chroot_local_user=YES
allow_writeable_chroot=NO
local_root=$FTP_ROOT

# ---- 被动模式（云服务器必须配置） ----
pasv_enable=YES
pasv_min_port=$PASV_MIN
pasv_max_port=$PASV_MAX
pasv_address=$SERVER_IP

# ---- 文件权限 ----
local_umask=022
file_open_mode=0644

# ---- 日志 ----
xferlog_enable=YES
xferlog_std_format=YES
xferlog_file=/var/log/vsftpd.log

# ---- 安全设置 ----
ssl_enable=NO
# 如果打印机支持 FTPS，可以改为 YES 并配置证书

# ---- 用户列表 ----
userlist_enable=YES
userlist_deny=NO
userlist_file=/etc/vsftpd.userlist

# ---- 其他 ----
use_localtime=YES
seccomp_sandbox=NO
EOF

# 5. 创建允许登录的用户列表
echo "[5/6] 配置用户白名单..."
echo "$FTP_USER" > /etc/vsftpd.userlist

# 6. 配置防火墙
echo "[6/6] 配置防火墙..."
if command -v ufw &>/dev/null; then
    ufw allow 20/tcp   # FTP 数据
    ufw allow 21/tcp   # FTP 控制
    ufw allow ${PASV_MIN}:${PASV_MAX}/tcp  # 被动模式
    ufw reload 2>/dev/null || true
    echo "  UFW 规则已添加"
else
    echo "  未检测到 ufw，请手动配置防火墙"
fi

# 重启服务
systemctl restart vsftpd
systemctl enable vsftpd

echo ""
echo "=========================================="
echo "  部署完成！"
echo "=========================================="
echo ""
echo "  打印机配置信息："
echo "  ┌─────────────────────────────────┐"
echo "  │ 通信协议：FTP                    │"
echo "  │ 主机名：  $SERVER_IP            │"
echo "  │ 文件夹路径：/scans              │"
echo "  │ 用户名：  $FTP_USER             │"
echo "  │ 密码：    $FTP_PASS             │"
echo "  └─────────────────────────────────┘"
echo ""
echo "  扫描文件保存位置：$FTP_DIR"
echo "  日志文件：/var/log/vsftpd.log"
echo ""
echo "  ⚠ 重要提醒："
echo "  1. 请确保云服务器安全组放通端口：21, ${PASV_MIN}-${PASV_MAX}"
echo "  2. 请修改脚本中的默认密码"
echo "  3. 测试命令：ftp $SERVER_IP"
echo ""
echo "  📂 如需通过浏览器下载扫描文件，请继续运行："
echo "     sudo bash setup_web.sh"
echo "=========================================="

#!/bin/bash
# ============================================
# Web 文件管理器部署脚本 (FileBrowser)
# 用途：通过浏览器下载打印机扫描的文件
# ============================================

set -e

# ---------- 配置区域 ----------
WEB_PORT=8080                         # Web 访问端口
WEB_USER="admin"                      # Web 登录用户名
WEB_PASS="admin123"                   # Web 登录密码（请修改）
SCAN_DIR="/home/scanner/ftp/scans"    # 扫描文件目录（与 FTP 一致）
# ------------------------------

echo "=========================================="
echo "  Web 文件管理器部署 (FileBrowser)"
echo "=========================================="

# 1. 安装 FileBrowser
echo "[1/4] 安装 FileBrowser..."
if command -v filebrowser &>/dev/null; then
    echo "  FileBrowser 已安装，跳过"
else
    curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash
    echo "  安装完成"
fi

# 2. 初始化配置
echo "[2/4] 初始化配置..."
FB_DB="/etc/filebrowser/filebrowser.db"
FB_CONFIG="/etc/filebrowser/config.json"
mkdir -p /etc/filebrowser

# 写入配置文件
cat > "$FB_CONFIG" << EOF
{
  "port": $WEB_PORT,
  "address": "0.0.0.0",
  "database": "$FB_DB",
  "root": "$SCAN_DIR",
  "log": "/var/log/filebrowser.log",
  "locale": "zh-cn"
}
EOF

# 初始化数据库并设置管理员账号
rm -f "$FB_DB"
filebrowser config init -c "$FB_CONFIG"
filebrowser users add "$WEB_USER" "$WEB_PASS" --perm.admin -c "$FB_CONFIG"

# 3. 创建 systemd 服务
echo "[3/4] 创建系统服务..."
cat > /etc/systemd/system/filebrowser.service << EOF
[Unit]
Description=FileBrowser - Web File Manager
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/filebrowser -c $FB_CONFIG
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable filebrowser
systemctl restart filebrowser

# 4. 配置防火墙
echo "[4/4] 配置防火墙..."
if command -v ufw &>/dev/null; then
    ufw allow ${WEB_PORT}/tcp
    ufw reload 2>/dev/null || true
    echo "  UFW 规则已添加"
else
    echo "  未检测到 ufw，请手动放通端口 $WEB_PORT"
fi

# 获取公网 IP
SERVER_IP=$(curl -s ifconfig.me || curl -s icanhazip.com)

echo ""
echo "=========================================="
echo "  部署完成！"
echo "=========================================="
echo ""
echo "  浏览器访问："
echo "  ┌─────────────────────────────────────┐"
echo "  │ 地址：http://$SERVER_IP:$WEB_PORT   │"
echo "  │ 用户名：$WEB_USER                   │"
echo "  │ 密码：$WEB_PASS                     │"
echo "  └─────────────────────────────────────┘"
echo ""
echo "  ⚠ 重要提醒："
echo "  1. 请确保云服务器安全组放通端口：$WEB_PORT"
echo "  2. 请登录后立即修改默认密码"
echo "  3. 如需 HTTPS，建议用 Nginx 反向代理 + Let's Encrypt"
echo "=========================================="

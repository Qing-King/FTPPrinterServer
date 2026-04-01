#!/bin/bash
# ============================================
# Web 文件管理器部署脚本 (Python + Flask)
# 用途：通过浏览器下载打印机扫描的文件
# ============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.sh"

if [ -f "$CONFIG_FILE" ]; then
    # Load local overrides that stay outside Git.
    . "$CONFIG_FILE"
fi

# ---------- 配置区域 ----------
FTP_USER="${FTP_USER:-scanner}"                 # FTP 登录用户名
FTP_ROOT="${FTP_ROOT:-/home/$FTP_USER/ftp}"     # FTP 登录后的根目录
SCAN_DIR="${SCAN_DIR:-$FTP_ROOT/scans}"         # 扫描文件目录（与 FTP 一致）
WEB_PORT="${WEB_PORT:-9090}"                    # Web 访问端口
WEB_USER="${WEB_USER:-admin}"                   # Web 登录用户名
WEB_PASS="${WEB_PASS:-admin123}"                # Web 登录密码（请修改）
# ------------------------------

INSTALL_DIR="/opt/scan-web"

echo "=========================================="
echo "  Web 文件管理器部署 (Python + Flask)"
echo "=========================================="

# 1. 安装 Python 依赖
echo "[1/4] 安装 Python 环境..."
apt update -y
apt install -y python3 python3-venv python3-pip

# 2. 部署应用
echo "[2/4] 部署应用到 $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cp -r "$SCRIPT_DIR"/web/* "$INSTALL_DIR"/

# 创建虚拟环境并安装依赖
python3 -m venv "$INSTALL_DIR/venv"
"$INSTALL_DIR/venv/bin/pip" install -r "$INSTALL_DIR/requirements.txt"

# 3. 创建 systemd 服务
echo "[3/4] 创建系统服务..."
cat > /etc/systemd/system/scan-web.service << EOF
[Unit]
Description=Scan File Web Manager
After=network.target

[Service]
Type=simple
Environment="SCAN_DIR=$SCAN_DIR"
Environment="WEB_USER=$WEB_USER"
Environment="WEB_PASS=$WEB_PASS"
Environment="SECRET_KEY=$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/venv/bin/gunicorn -w 2 -b 0.0.0.0:$WEB_PORT app:app
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable scan-web
systemctl restart scan-web

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
echo "  2. 请登录后修改默认密码（或修改脚本重新部署）"
echo "=========================================="

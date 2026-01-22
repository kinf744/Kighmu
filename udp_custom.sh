#!/bin/bash
set -euo pipefail

# =================== ROOT CHECK ===================
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root"
  exit 1
fi

# =================== UPDATE SYSTEM ===================
apt update -y
apt upgrade -y

# =================== INSTALL TOOLS ===================
apt install -y lolcat figlet neofetch screenfetch sysvbanner wget curl

# =================== PREPARE DIR ===================
cd /root
rm -rf /root/udp
mkdir -p /root/udp

clear
banner UDP-CUSTOM || true
sleep 3

# =================== TIMEZONE ===================
echo "Change timezone to GMT+5:30 (Sri Lanka)"
ln -fs /usr/share/zoneinfo/Asia/Colombo /etc/localtime
timedatectl set-timezone Asia/Colombo

# =================== DOWNLOAD UDP CUSTOM ===================
echo "Downloading udp-custom binary..."
wget -q https://github.com/noobconner21/UDP-Custom-Script/raw/main/udp-custom-linux-amd64 -O /root/udp/udp-custom
chmod +x /root/udp/udp-custom

# =================== VERIFY BINARY ===================
if ! /root/udp/udp-custom --help >/dev/null 2>&1; then
  echo "❌ udp-custom binary is invalid or incompatible"
  exit 1
fi

# =================== DOWNLOAD CONFIG ===================
echo "Downloading default config.json..."
wget -q https://raw.githubusercontent.com/noobconner21/UDP-Custom-Script/main/config.json -O /root/udp/config.json
chmod 644 /root/udp/config.json

# =================== SYSTEMD SERVICE ===================
if [ -z "${1:-}" ]; then
cat > /etc/systemd/system/udp-custom.service <<EOF
[Unit]
Description=UDP Custom by ePro Dev. Team (Modified)
After=network.target

[Service]
User=root
Type=simple
WorkingDirectory=/root/udp
ExecStart=/root/udp/udp-custom server
Restart=always
RestartSec=3
StandardOutput=append:/var/log/udp-custom.log
StandardError=append:/var/log/udp-custom.log

[Install]
WantedBy=multi-user.target
EOF
else
cat > /etc/systemd/system/udp-custom.service <<EOF
[Unit]
Description=UDP Custom by ePro Dev. Team (Modified)
After=network.target

[Service]
User=root
Type=simple
WorkingDirectory=/root/udp
ExecStart=/root/udp/udp-custom server -exclude $1
Restart=always
RestartSec=3
StandardOutput=append:/var/log/udp-custom.log
StandardError=append:/var/log/udp-custom.log

[Install]
WantedBy=multi-user.target
EOF
fi

# =================== SYSTEMD RELOAD ===================
systemctl daemon-reload

# =================== FIREWALL (OPTIONAL SAFE OPEN) ===================
if command -v ufw >/dev/null 2>&1; then
  ufw allow 1:65535/udp || true
fi

# =================== START SERVICE ===================
systemctl enable udp-custom >/dev/null 2>&1
systemctl restart udp-custom

clear
echo "========================================="
echo "   UDP Custom Installation Completed"
echo "========================================="
echo ""
echo "Check status  : systemctl status udp-custom"
echo "View logs     : tail -f /var/log/udp-custom.log"
echo ""

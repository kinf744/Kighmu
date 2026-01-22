#!/bin/bash
apt update -y
apt upgrade -y
apt install lolcat -y
apt install figlet -y
apt install neofetch -y
apt install screenfetch -y
cd
rm -rf /root/udp
mkdir -p /root/udp

# banner
clear

sleep 5
# change to time GMT+5:30

echo "change to time GMT+5:30 Sri Lanka"
ln -fs /usr/share/zoneinfo/Asia/Colombo /etc/localtime

# install udp-custom
echo downloading udp-custom
wget "https://github.com/noobconner21/UDP-Custom-Script/raw/main/udp-custom-linux-amd64" -O /root/udp/udp-custom
chmod +x /root/udp/udp-custom

echo downloading default config
wget "https://raw.githubusercontent.com/noobconner21/UDP-Custom-Script/main/config.json" -O /root/udp/config.json
chmod 644 /root/udp/config.json

if [ -z "$1" ]; then
cat <<EOF > /etc/systemd/system/udp-custom.service
[Unit]
Description=UDP Custom by ePro Dev. Team and modify by sslablk

[Service]
User=root
Type=simple
ExecStart=/root/udp/udp-custom server
WorkingDirectory=/root/udp/
Restart=always
RestartSec=2s

[Install]
WantedBy=default.target
EOF
else
cat <<EOF > /etc/systemd/system/udp-custom.service
[Unit]
Description=UDP Custom by ePro Dev. Team and modify by sslablk

[Service]
User=root
Type=simple
ExecStart=/root/udp/udp-custom server -exclude $1
WorkingDirectory=/root/udp/
Restart=always
RestartSec=2s

[Install]
WantedBy=default.target
EOF
fi

clear
echo 'UDP Install Script By Project SSLAB LK Dev.Team'
echo 'UDP Custom By ePro Dev. Team'
echo ''
sleep 5

echo start service udp-custom
systemctl start udp-custom &>/dev/null

echo enable service udp-custom
systemctl enable udp-custom &>/dev/null

echo -e "✅ Installation complète"

read -p "Appuyez sur Entrée pour continuer..."

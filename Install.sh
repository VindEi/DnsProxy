#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'

CONFIG_DIR="/etc/coredns/conf.d"
COREFILE="/etc/coredns/Corefile"
SERVICE_FILE="/etc/systemd/system/coredns.service"
COREDNS_BIN="/usr/local/bin/coredns"

function install_CoreDNS() {
    echo -e "${YELLOW}🚀 Installing CoreDNS...${RESET}"
    LATEST_VERSION=$(curl -sL https://api.github.com/repos/coredns/coredns/releases/latest | grep '"tag_name":' | cut -d'"' -f4)
    DOWNLOAD_URL="https://github.com/coredns/coredns/releases/download/$LATEST_VERSION/coredns_${LATEST_VERSION:1}_linux_amd64.tgz"

    sudo mkdir -p "$(dirname "$COREDNS_BIN")"
    if curl -sL "$DOWNLOAD_URL" | sudo tar -xz -C "$(dirname "$COREDNS_BIN")"; then
        echo -e "${GREEN}✅ CoreDNS binary downloaded to $COREDNS_BIN${RESET}"
    else
        echo -e "${RED}❌ Failed to download/extract CoreDNS.${RESET}"
        return 1
    fi

    sudo mkdir -p "$CONFIG_DIR"

    echo -e "${YELLOW}📝 Writing Corefile...${RESET}"
    sudo tee "$COREFILE" > /dev/null <<EOF
import conf.d/*.conf

. {
    forward . 8.8.8.8 1.1.1.1
    log
    errors
}
EOF

    echo -e "${YELLOW}🔧 Creating CoreDNS systemd service...${RESET}"
    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=CoreDNS
After=network.target

[Service]
ExecStart=$COREDNS_BIN -conf $COREFILE
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    echo -e "${GREEN}✅ CoreDNS installed.${RESET}"
}

function configure_nginx_stream() {
    echo -e "${YELLOW}📝 Configuring NGINX stream for dynamic SNI...${RESET}"

    sudo mkdir -p /etc/nginx/stream.d
    # Include the stream config from main nginx.conf
    sudo sed -i '/^stream {/d' /etc/nginx/nginx.conf
    sudo sed -i '/^}/d' /etc/nginx/nginx.conf
    echo -e "\nstream {\n    include /etc/nginx/stream.d/*.conf;\n}" | sudo tee -a /etc/nginx/nginx.conf

    sudo tee /etc/nginx/stream.d/unblocker.conf > /dev/null <<EOF
resolver 1.1.1.1 8.8.8.8 valid=30s;

server {
    listen 443;
    proxy_pass \$ssl_preread_server_name:443;
    ssl_preread on;
}

server {
    listen 80;
    proxy_pass \$ssl_preread_server_name:80;
    ssl_preread on;
}
EOF

    sudo nginx -t && sudo systemctl restart nginx
    echo -e "${GREEN}✅ NGINX stream ready.${RESET}"
}

function install_Service() {
    clear
    echo -e "${YELLOW}📦 Updating and installing packages...${RESET}"
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y nginx-extras ufw curl tar

    install_CoreDNS || return 1
    configure_nginx_stream

    echo -e "${YELLOW}🔐 Configuring UFW...${RESET}"
    sudo ufw allow ssh comment 'SSH'
    sudo ufw allow 53 comment 'DNS'
    sudo ufw allow 80 comment 'HTTP'
    sudo ufw allow 443 comment 'HTTPS'
    sudo ufw --force enable

    echo -e "${YELLOW}🔄 Enabling services...${RESET}"
    sudo systemctl daemon-reload
    sudo systemctl enable --now coredns
    sudo systemctl enable --now nginx

    echo -e "${GREEN}✅ CoreDNS + NGINX (SNI stream) installed successfully.${RESET}"
    read -p "Press enter to return..."
}

install_Service

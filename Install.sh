#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

CONFIG_DIR="/etc/coredns/conf.d"
COREFILE="/etc/coredns/Corefile"
SERVICE_FILE="/etc/systemd/system/coredns.service"
COREDNS_BIN="/usr/local/bin/coredns"

function install_CoreDNS() {
    echo -e "${YELLOW}🚀 Installing CoreDNS...${RESET}"
    LATEST_VERSION=$(curl -sL https://api.github.com/repos/coredns/coredns/releases/latest | grep '"tag_name":' | cut -d'"' -f4)
    DOWNLOAD_URL="https://github.com/coredns/coredns/releases/download/$LATEST_VERSION/coredns_${LATEST_VERSION:1}_linux_amd64.tgz"

    if curl -sL "$DOWNLOAD_URL" | sudo tar -xz -C "$(dirname "$COREDNS_BIN")"; then
        echo -e "${GREEN}✅ CoreDNS binary downloaded and placed in $COREDNS_BIN${RESET}"
    else
        echo -e "${RED}❌ Failed to download and extract CoreDNS. Aborting.${RESET}"
        return 1
    fi

    echo -e "${YELLOW}📁 Setting up config directories...${RESET}"
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

    echo -e "${YELLOW}🔧 Creating CoreDNS systemd service file...${RESET}"
    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=CoreDNS
Documentation=https://coredns.io
After=network.target

[Service]
ExecStart=$COREDNS_BIN -conf $COREFILE
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    echo -e "${GREEN}✅ CoreDNS installation and setup is complete.${RESET}"
    return 0
}

function configure_nginx_stream() {
    echo -e "${YELLOW}📝 Configuring NGINX stream mode for dynamic SNI TCP proxy...${RESET}"

    sudo mkdir -p /etc/nginx/stream.conf.d

    sudo tee /etc/nginx/stream.conf.d/unblocker.conf > /dev/null <<EOF
stream {
    resolver 1.1.1.1 8.8.8.8 valid=30s;

    # HTTPS/TLS forwarding with SNI
    server {
        listen 443;
        proxy_pass \$ssl_preread_server_name:443;
        ssl_preread on;
    }

    # HTTP forwarding
    server {
        listen 80;
        proxy_pass \$ssl_preread_server_name:80;
        ssl_preread on;
    }
}
EOF

    sudo nginx -t
    sudo systemctl restart nginx

    echo -e "${GREEN}✅ NGINX stream mode with dynamic SNI is ready.${RESET}"
}

function install_Service() {
    clear
    echo -e "${YELLOW}📦 Updating and installing packages...${RESET}"
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y nginx-extras ufw

    install_CoreDNS
    if [ $? -ne 0 ]; then
        return 1
    fi

    configure_nginx_stream

    echo -e "${YELLOW}🔐 Configuring UFW...${RESET}"
    sudo ufw allow ssh comment 'SSH port'
    sudo ufw allow 53 comment 'CoreDNS DNS traffic'
    sudo ufw allow 80 comment 'NGINX HTTP traffic'
    sudo ufw allow 443 comment 'NGINX HTTPS traffic'
    sudo ufw --force enable

    echo -e "${YELLOW}🔄 Reloading systemd daemon and enabling services...${RESET}"
    sudo systemctl daemon-reload
    sudo systemctl enable coredns
    sudo systemctl restart coredns
    sudo systemctl enable nginx
    sudo systemctl restart nginx

    echo -e "${GREEN}✅ CoreDNS + NGINX (dynamic SNI) installed and configured successfully.${RESET}"
    read -p "Press enter to return to menu..."
}

#!/bin/bash
set -euo pipefail

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

    # Create config directories
    sudo mkdir -p "$CONFIG_DIR"

    # Write placeholder so Corefile glob doesn't warning-loop on first boot
    sudo touch "${CONFIG_DIR}/.placeholder.conf"

    # CoreDNS runs on default Port 53 directly
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

function configure_nginx() {
    echo -e "${YELLOW}📝 Writing main Nginx Configuration...${RESET}"

    sudo tee /etc/nginx/nginx.conf > /dev/null <<'EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
error_log /var/log/nginx/error.log;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 768;
}

http {
    sendfile on;
    tcp_nopush on;
    types_hash_max_size 2048;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    access_log /var/log/nginx/access.log;
    gzip on;

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}

stream {
    include /etc/nginx/stream.d/*.conf;
}
EOF

    sudo mkdir -p /etc/nginx/stream.d
    sudo mkdir -p /etc/nginx/conf.d
    
    echo -e "${YELLOW}📝 Configuring Port 80 HTTP Proxy...${RESET}"
    sudo tee /etc/nginx/conf.d/http_proxy.conf > /dev/null <<'EOF'
server {
    listen 80;
    resolver 1.1.1.1 8.8.8.8 valid=300s;
    resolver_timeout 5s;
    
    location / {
        proxy_pass http://$http_host;
        proxy_set_header Host $http_host;
    }
}
EOF

    echo -e "${YELLOW}📝 Configuring Port 443 Stream Proxy...${RESET}"
    sudo tee /etc/nginx/stream.d/smartdns.conf > /dev/null <<'EOF'
server {
    listen 443;
    proxy_pass $ssl_preread_server_name:443;
    ssl_preread on;
}
EOF

    sudo nginx -t && sudo systemctl restart nginx
    echo -e "${GREEN}✅ NGINX stream and HTTP proxy configurations complete.${RESET}"
}

function install_Service() {
    clear
    echo -e "${YELLOW}📦 Installing required packages...${RESET}"
    sudo apt install -y nginx-extras ufw curl tar

    install_CoreDNS || return 1
    configure_nginx

    echo -e "${YELLOW}💾 Saving public IP for dashboard...${RESET}"
    sudo mkdir -p /etc/dnsproxy
    curl -s https://api.ipify.org | sudo tee /etc/dnsproxy/vps_ip.txt > /dev/null

    echo -e "${YELLOW}🔐 Configuring UFW...${RESET}"
    sudo ufw allow ssh comment 'SSH'
    sudo ufw allow 53 comment 'DNS (UDP/TCP)'
    sudo ufw allow 80 comment 'HTTP'
    sudo ufw allow 443 comment 'HTTPS'
    sudo ufw --force enable

    echo -e "${YELLOW}🔄 Enabling services...${RESET}"
    sudo systemctl daemon-reload
    sudo systemctl enable --now coredns
    sudo systemctl enable --now nginx

    echo -e "${GREEN}✅ Installation successfully completed.${RESET}"
    read -p "Press enter to return..."
}

install_Service
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

    # Overwrite nginx.conf with correct streams enabled
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
    
    # 1. Configured generic HTTP Proxy on Port 80
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

    # 2. Configured Port 443 Stream multiplexer (VPN on 4443 and Proxy on default fallback)
    echo -e "${YELLOW}📝 Configuring Port 443 Stream multiplexer...${RESET}"
    sudo tee /etc/nginx/stream.d/smartdns.conf > /dev/null <<'EOF'
resolver 1.1.1.1 8.8.8.8 valid=300s;
resolver_timeout 5s;
log_format basic '$remote_addr [$time_local] $ssl_preread_server_name -> $upstream_addr';
access_log /var/log/nginx/stream_access.log basic;

map $ssl_preread_server_name $backend {
    hostnames;

    # Protect against empty SNI probes
    ""                    127.0.0.1:9999;

    # Helsinki Reality SNIs route internally to local Xray
    www.helsinki.fi      127.0.0.1:4443;
    helsinki.fi          127.0.0.1:4443;
    
    # All other traffic routes dynamically to target domain
    default               $ssl_preread_server_name:443;
}

server {
    listen 443;
    proxy_pass $backend;
    ssl_preread on;
}
EOF

    sudo nginx -t && sudo systemctl restart nginx
    echo -e "${GREEN}✅ NGINX stream and HTTP proxy configurations complete.${RESET}"
}

function install_Service() {
    clear
    echo -e "${YELLOW}📦 Updating and installing packages...${RESET}"
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y nginx-extras ufw curl tar

    install_CoreDNS || return 1
    configure_nginx

    echo -e "${YELLOW}🔐 Configuring UFW...${RESET}"
    sudo ufw allow ssh comment 'SSH'
    sudo ufw allow 53 comment 'DNS (UDP/TCP)'
    sudo ufw allow 80 comment 'HTTP'
    sudo ufw allow 443 comment 'HTTPS (Shared)'
    sudo ufw --force enable

    echo -e "${YELLOW}🔄 Enabling services...${RESET}"
    sudo systemctl daemon-reload
    sudo systemctl enable --now coredns
    sudo systemctl enable --now nginx

    echo -e "${GREEN}✅ Installation successfully completed.${RESET}"
    read -p "Press enter to return..."
}

install_Service
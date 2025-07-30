#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

CONFIG_DIR="/etc/coredns/conf.d"
COREFILE="/etc/coredns/Corefile"

function install_vinde() {
    clear
    echo -e "${YELLOW}📦 Updating and installing packages...${RESET}"
    apt update && apt upgrade -y
    apt install -y coredns sniproxy ufw

    echo -e "${YELLOW}🔐 Configuring UFW...${RESET}"
    ufw allow ssh
    ufw allow 53
    ufw allow 80
    ufw allow 443
    ufw --force enable

    echo -e "${YELLOW}📁 Setting up config directories...${RESET}"
    mkdir -p "$CONFIG_DIR"

    echo -e "${YELLOW}📝 Writing Corefile...${RESET}"
    tee "$COREFILE" > /dev/null <<EOF
import conf.d/*.conf

. {
    forward . 8.8.8.8 1.1.1.1
    log
    errors
}
EOF

    systemctl enable coredns
    systemctl restart coredns
    systemctl enable sniproxy
    systemctl restart sniproxy

    echo -e "${GREEN}✅ $PROJECT_NAME installed successfully.${RESET}"
    read -p "Press enter to return to menu..."
}

install_vinde

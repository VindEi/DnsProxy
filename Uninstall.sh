#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

CONFIG_DIR="/etc/coredns/conf.d"
COREFILE="/etc/coredns/Corefile"

function uninstall_vinde() {
    clear
    echo -e "${YELLOW}🗑️  Removing packages and configs...${RESET}"

    systemctl stop coredns sniproxy
    systemctl disable coredns sniproxy

    apt purge -y coredns sniproxy ufw
    apt autoremove -y

    echo -e "${YELLOW}🔐 Closing UFW ports...${RESET}"
    ufw deny 53
    ufw deny 80
    ufw deny 443

    echo -e "${YELLOW}🗃️  Removing config files...${RESET}"
    rm -rf "$CONFIG_DIR"
    rm -f "$COREFILE"

    echo -e "${GREEN}✅ $PROJECT_NAME uninstalled successfully.${RESET}"
    read -p "Press enter to return to menu..."
}

uninstall_vinde

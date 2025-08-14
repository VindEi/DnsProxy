#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Paths to files and directories
CONFIG_DIR="/etc/coredns/conf.d"
COREFILE="/etc/coredns/Corefile"
SERVICE_FILE="/etc/systemd/system/coredns.service"
COREDNS_BIN="/usr/local/bin/coredns"
NGINX_STREAM_DIR="/etc/nginx/stream.d"

function uninstall() {
    clear
    echo -e "${YELLOW}🗑️  Starting the uninstallation process...${RESET}"

    # Stop and disable services
    echo -e "${CYAN}Stopping and disabling services...${RESET}"
    sudo systemctl stop coredns nginx
    sudo systemctl disable coredns nginx

    # Remove packages
    echo -e "${CYAN}Removing installed packages...${RESET}"
    sudo apt purge -y nginx-extras ufw curl tar

    # Remove CoreDNS binary and systemd service
    echo -e "${CYAN}Removing CoreDNS binary and service file...${RESET}"
    sudo rm -f "$COREDNS_BIN"
    sudo rm -f "$SERVICE_FILE"

    # Remove configuration files
    echo -e "${CYAN}Removing CoreDNS and NGINX configuration files...${RESET}"
    sudo rm -rf "$CONFIG_DIR"
    sudo rm -f "$COREFILE"
    sudo rm -rf "$NGINX_STREAM_DIR"

    # Remove UFW rules for DNS, HTTP, HTTPS
    echo -e "${CYAN}Removing UFW rules...${RESET}"
    sudo ufw delete allow 53
    sudo ufw delete allow 80
    sudo ufw delete allow 443

    # Clean up any unused dependencies
    echo -e "${CYAN}Cleaning up system...${RESET}"
    sudo apt autoremove -y

    echo -e "${GREEN}✅ Uninstallation completed successfully.${RESET}"
    read -p "Press enter to return to menu..."
}

uninstall

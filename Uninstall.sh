#!/bin/bash
set -euo pipefail

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
    sudo systemctl stop coredns nginx || true
    sudo systemctl disable coredns nginx || true

    # Remove packages (Preserving critical system dependencies like curl and tar)
    echo -e "${CYAN}Removing installed packages...${RESET}"
    sudo apt purge -y nginx-extras ufw

    # Remove CoreDNS binary and systemd service
    echo -e "${CYAN}Removing CoreDNS binary and service file...${RESET}"
    sudo rm -f "$COREDNS_BIN"
    sudo rm -f "$SERVICE_FILE"

    # Remove CoreDNS, Nginx stream configurations, and cached folders
    echo -e "${CYAN}Removing DnsProxy configuration files & databases...${RESET}"
    sudo rm -rf "$CONFIG_DIR"
    sudo rm -f "$COREFILE"
    sudo rm -rf /etc/coredns
    sudo rm -rf "$NGINX_STREAM_DIR"
    sudo rm -f /etc/nginx/conf.d/http_proxy.conf
    
    # Clean up orphan DnsProxy reference databases and cached IPs
    sudo rm -rf /etc/unblocker
    sudo rm -rf /etc/dnsproxy

    # Clean up the system-wide command link (No more dead command errors)
    echo -e "${CYAN}Cleaning up system-wide command symlink...${RESET}"
    sudo rm -f /usr/local/bin/dnsproxy

    # Remove UFW rules for DNS, HTTP, HTTPS
    echo -e "${CYAN}Removing UFW rules...${RESET}"
    sudo ufw delete allow 53 || true
    sudo ufw delete allow 80 || true
    sudo ufw delete allow 443 || true

    # Clean up any unused dependencies
    echo -e "${CYAN}Cleaning up system packages...${RESET}"
    sudo apt autoremove -y

    echo -e "${GREEN}✅ Uninstallation completed successfully.${RESET}"
    read -p "Press Enter to return to menu..."
}

uninstall
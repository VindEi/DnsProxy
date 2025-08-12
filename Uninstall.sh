#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Define paths to files and directories to be removed
CONFIG_DIR="/etc/coredns/conf.d"
COREFILE="/etc/coredns/Corefile"
SERVICE_FILE="/etc/systemd/system/coredns.service"
COREDNS_BIN="/usr/local/bin/coredns"

function uninstall() {
    clear
    echo -e "${YELLOW}🗑️  Starting the uninstallation process...${RESET}"

    # Stop and disable services
    echo -e "${CYAN}Stopping and disabling services...${RESET}"
    sudo systemctl stop coredns sniproxy
    sudo systemctl disable coredns sniproxy

    # Remove packages
    echo -e "${CYAN}Removing installed packages...${RESET}"
    sudo apt purge -y sniproxy

    # Since CoreDNS was installed as a binary, apt purge won't work.
    # We must remove the binary and systemd service file manually.
    echo -e "${CYAN}Removing CoreDNS binary and service file...${RESET}"
    sudo rm -f "$COREDNS_BIN"
    sudo rm -f "$SERVICE_FILE"

    # Remove the created configuration files and directories
    echo -e "${CYAN}Removing configuration files...${RESET}"
    sudo rm -rf "$CONFIG_DIR"
    sudo rm -f "$COREFILE"

    # Remove UFW rules. Using 'ufw delete' is the correct way to remove specific rules.
    echo -e "${CYAN}Removing UFW rules for DNS, HTTP, and HTTPS...${RESET}"
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

#!/bin/bash

# --- Script Configuration ---
CONF_DIR="/etc/coredns/conf.d"
HOSTS_DIR="/etc/unblocker"

# Dynamic VPS IP detection
SNIPROXY_IP=$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')

PYTHON_SCRIPT_PATH="$(dirname "$0")/AutoDomain.py"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Check for required arguments
if [ "$#" -ne 2 ]; then
    echo -e "${RED}❌ Usage: $0 <service_name> <method_choice>${RESET}"
    echo "  <method_choice> should be 'auto' or 'manual'."
    exit 1
fi

SERVICE_NAME="$1"
CHOICE="$2"

# Ensure the required directories exist
mkdir -p "$CONF_DIR"
mkdir -p "$HOSTS_DIR"

# --- Main Script Logic ---

case "$CHOICE" in
    "auto")
        echo -e "${YELLOW}---${RESET}"
        echo -e "${CYAN}Launching automatic configuration for '$SERVICE_NAME'...${RESET}"

        if [ ! -f "$PYTHON_SCRIPT_PATH" ]; then
            echo -e "${RED}❌ Error: The Python script was not found at '$PYTHON_SCRIPT_PATH'.${RESET}"
            exit 1
        fi
        
        if [ ! -x "$PYTHON_SCRIPT_PATH" ]; then
            echo -e "${YELLOW}⚠️ Warning: The script is not executable. Attempting to run with 'python3'.${RESET}"
        fi
        
        python3 "$PYTHON_SCRIPT_PATH" "$SERVICE_NAME" "$SNIPROXY_IP"
        echo -e "${YELLOW}Automatic script finished.${RESET}"
        ;;
    "manual")
        echo -e "${YELLOW}---${RESET}"
        echo -e "${CYAN}Proceeding with manual configuration for '$SERVICE_NAME'.${RESET}"

        CONF_FILE="${CONF_DIR}/${SERVICE_NAME}.conf"
        HOSTS_FILE="${HOSTS_DIR}/${SERVICE_NAME}.hosts"

        if [ -f "$CONF_FILE" ]; then
            echo -e "${RED}❌ Error: Configuration for '$SERVICE_NAME' already exists. Exiting.${RESET}"
            exit 1
        fi

        echo -e "${YELLOW}Enter the root domain (e.g., example.com).${RESET}"
        read -p "> " ROOT_DOMAIN

        if [[ -z "$ROOT_DOMAIN" ]]; then
            echo -e "${RED}❌ No domain entered. Exiting.${RESET}"
            exit 1
        fi

        # Write the simple, clean hosts entry
        echo -e "${SNIPROXY_IP} ${ROOT_DOMAIN}" > "$HOSTS_FILE"
        echo -e "${GREEN}✅ Created hosts file: ${HOSTS_FILE}${RESET}"

        # Escape dots for rewrite regex (e.g. example.com -> example\.com)
        ESCAPED_DOMAIN=$(echo "$ROOT_DOMAIN" | sed 's/\./\\./g')

        # Write CoreDNS config using rewrite and hosts approach
        cat <<EOL > "$CONF_FILE"
${ROOT_DOMAIN} {
    # Rewrite all wildcard subdomains to the root domain internally
    rewrite stop {
        name regex (.*)\.${ESCAPED_DOMAIN} ${ROOT_DOMAIN}
        answer auto
    }
    hosts ${HOSTS_FILE} {
        fallthrough
        ttl 300
    }
    forward . 1.1.1.1 8.8.8.8
    log
    errors
}
EOL

        echo -e "${GREEN}✅ Created CoreDNS config file: ${CONF_FILE}${RESET}"
        echo -e "${CYAN}Restarting CoreDNS...${RESET}"
        sudo systemctl restart coredns
        echo -e "${GREEN}[+] CoreDNS restarted successfully.${RESET}"
        ;;
    *)
        echo -e "${RED}❌ Invalid choice. Exiting.${RESET}"
        exit 1
        ;;
esac
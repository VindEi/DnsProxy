#!/bin/bash

# --- Script Configuration ---
# Set the base directories based on your CoreDNS setup
CONF_DIR="/etc/coredns/conf.d"
HOSTS_DIR="/etc/unblocker"
# The sniproxy IP address is hardcoded here, as requested.
SNIPROXY_IP="193.56.135.102"
# Set the full path to your Python script
# NOTE: This path should be updated to your actual location
PYTHON_SCRIPT_PATH="$(dirname "$0")/AutoDomain.py"
# --- Colors for a better user experience ---
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
        # Handle the 'automatic' option by launching a separate Python script
        echo -e "${YELLOW}---${RESET}"
        echo -e "${CYAN}Launching automatic configuration for '$SERVICE_NAME'...${RESET}"

        if [ ! -f "$PYTHON_SCRIPT_PATH" ]; then
            echo -e "${RED}❌ Error: The Python script was not found at '$PYTHON_SCRIPT_PATH'.${RESET}"
            exit 1
        fi
        
        if [ ! -x "$PYTHON_SCRIPT_PATH" ]; then
            echo -e "${YELLOW}⚠️ Warning: The script is not executable. Attempting to run with 'python3'.${RESET}"
        fi
        
        # Launch the Python script with the necessary arguments
        python3 "$PYTHON_SCRIPT_PATH" "$SERVICE_NAME" "$SNIPROXY_IP"
        
        echo -e "${YELLOW}Automatic script finished.${RESET}"
        ;;
    "manual")
        # Handle the 'manual' option
        echo -e "${YELLOW}---${RESET}"
        echo -e "${CYAN}Proceeding with manual configuration for '$SERVICE_NAME'.${RESET}"

        # Define file paths
        HOSTS_FILE="${HOSTS_DIR}/${SERVICE_NAME}.hosts"
        CONF_FILE="${CONF_DIR}/${SERVICE_NAME}.conf"

        # Check if files already exist
        if [ -f "$CONF_FILE" ]; then
            echo -e "${RED}❌ Error: Configuration for '$SERVICE_NAME' already exists. Exiting.${RESET}"
            exit 1
        fi

        # Create hosts file with an interactive loop
        echo -e "${YELLOW}Enter domains one by one (e.g., example.com). Press [Enter] on an empty line to finish.${RESET}"
        
        DOMAIN_LIST=""
        while read -p "> "; do
            if [[ -z "$REPLY" ]]; then
                break
            fi
            DOMAIN_LIST+="`echo -e "$SNIPROXY_IP $REPLY\n"`"
        done
        
        if [[ -z "$DOMAIN_LIST" ]]; then
            echo -e "${RED}❌ No domains entered. Exiting.${RESET}"
            exit 1
        fi
        
        echo -e "$DOMAIN_LIST" > "$HOSTS_FILE"
        echo -e "${GREEN}✅ Created hosts file: ${HOSTS_FILE}${RESET}"

        # Create the CoreDNS configuration file
        cat <<EOL > "$CONF_FILE"
${SERVICE_NAME} {
    hosts ${HOSTS_FILE} {
        fallthrough
        ttl 300
    }
    log
    errors
}
EOL
        echo -e "${GREEN}✅ Created CoreDNS config file: ${CONF_FILE}${RESET}"
        echo -e "${YELLOW}---${RESET}"
        echo -e "${CYAN}Manual configuration for '$SERVICE_NAME' is complete.${RESET}"
        sudo systemctl restart coredns
		echo -e "${GREEN}[+] CoreDNS restarted successfully.${RESET}"
        ;;
    *)
        echo -e "${RED}❌ Invalid choice. Exiting.${RESET}"
        exit 1
        ;;
esac

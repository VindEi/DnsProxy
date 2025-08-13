#!/bin/bash

# --- Script Configuration ---
# Set the base directories based on your CoreDNS setup
CONF_DIR="/etc/coredns/conf.d"
HOSTS_DIR="/etc/unblocker"

# Ensure the required directories exist
mkdir -p "$CONF_DIR"
mkdir -p "$HOSTS_DIR"

# --- Main Script Logic ---

# 1. Ask for a service name to use for the files
read -p "Enter the name of the service (e.g., spotify, gemini): " SERVICE_NAME

if [[ -z "$SERVICE_NAME" ]]; then
    echo "Error: Service name cannot be empty. Exiting."
    exit 1
fi

# 2. Ask the user to choose between automatic and manual
echo "---"
echo "Select a configuration method:"
echo "1) Automatic"
echo "2) Manual"
read -p "Enter your choice (1 or 2): " CHOICE

case $CHOICE in
    1)
        # Handle the 'automatic' option by launching a separate Python script
        echo "---"
        read -p "Enter the full path to your Python automatic script (e.g., /path/to/script.py): " SCRIPT_PATH
        
        if [ ! -f "$SCRIPT_PATH" ]; then
            echo "Error: The specified script does not exist. Exiting."
            exit 1
        fi
        
        if [ ! -x "$SCRIPT_PATH" ]; then
            echo "Warning: The script is not executable. Attempting to run with 'python3'."
        fi
        
        read -p "Enter the IP address of your sniproxy server: " SNIPROXY_IP
        
        echo "---"
        echo "Launching automatic configuration for '$SERVICE_NAME'..."
        # Launch the Python script with the necessary arguments
        python3 "$SCRIPT_PATH" "$SERVICE_NAME" "$SNIPROXY_IP"
        
        echo "Automatic script finished."
        ;;
    2)
        # 3. Handle the 'manual' option
        echo "---"
        echo "Proceeding with manual configuration for '$SERVICE_NAME'."

        # Define file paths
        HOSTS_FILE="${HOSTS_DIR}/${SERVICE_NAME}.hosts"
        CONF_FILE="${CONF_DIR}/${SERVICE_NAME}.conf"

        # Create the hosts file and leave it empty
        touch "$HOSTS_FILE"
        echo "Created empty hosts file: $HOSTS_FILE"

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
        echo "Created CoreDNS config file: $CONF_FILE"
        echo "---"

        # 4. Tell the user what to do next
        echo "The hosts file is now ready for you to edit."
        echo "Please add your domains to the following file:"
        echo ""
        echo "    $HOSTS_FILE"
        echo ""
        echo "Each line in the file should be in the format:"
        echo "    193.56.135.102 <domain>"
        echo ""
        echo "After you have finished, restart your CoreDNS service to apply the changes."
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

#!/bin/bash
set -euo pipefail

# --- Script Configuration ---
CONF_DIR="/etc/coredns/conf.d"
HOSTS_DIR="/etc/unblocker"

# Dynamic VPS IP detection (Zero hardcoding)
SNIPROXY_IP=$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')

PYTHON_SCRIPT_PATH="$(dirname "$0")/AutoDomain.py"

# --- Colors for user experience ---
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

# Temporary files for automatic scraper tracking
DOMAINS_TEMP=$(mktemp)
VISITED_TEMP=$(mktemp)
ROOTS_TEMP=$(mktemp)

# Clean up temp files on exit
trap 'rm -f "$DOMAINS_TEMP" "$VISITED_TEMP" "$ROOTS_TEMP"' EXIT

# --- Recursive V2Fly Scraper in Pure Bash ---
fetch_v2fly_domains() {
    local mapped_name="$1"

    # Avoid infinite loops during circular include imports
    if grep -Fxq "$mapped_name" "$VISITED_TEMP" 2>/dev/null; then
        return
    fi
    echo "$mapped_name" >> "$VISITED_TEMP"

    # Try name permutations on GitHub dynamically (name, google-name, category-name)
    local permutations=("${mapped_name}" "google-${mapped_name}" "category-${mapped_name}")
    local response=""
    local success=0

    for perm in "${permutations[@]}"; do
        response=$(curl -s -f -L --connect-timeout 5 "https://raw.githubusercontent.com/v2fly/domain-list-community/master/data/${perm}" || true)
        if [ -n "$response" ]; then
            success=1
            break
        fi
    done

    # If the permutation didn't find any file, exit gracefully
    if [ "$success" -eq 0 ]; then
        return
    fi

    # Parse lines recursively
    while IFS= read -r line || [ -n "$line" ]; do
        # Strip inline comments first (e.g. "domain.com # comment" -> "domain.com")
        line=$(echo "$line" | cut -d'#' -f1 | xargs)
        
        # Skip empty lines
        [[ -z "$line" ]] && continue

        if [[ "$line" =~ ^include: ]]; then
            local inc_service
            inc_service=$(echo "$line" | sed 's/^include://' | cut -d'@' -f1 | xargs)
            fetch_v2fly_domains "$inc_service"
        elif [[ "$line" =~ ^full: ]]; then
            local domain
            domain=$(echo "$line" | sed 's/^full://' | cut -d'@' -f1 | xargs)
            echo "$domain" >> "$DOMAINS_TEMP"
        elif [[ "$line" =~ ^regexp: || "$line" =~ ^keyword: ]]; then
            continue
        else
            local domain
            domain=$(echo "$line" | cut -d'@' -f1 | xargs)
            echo "$domain" >> "$DOMAINS_TEMP"
        fi
    done <<< "$response"
}

# --- Main Script Logic ---

case "$CHOICE" in
    "auto")
        echo -e "${YELLOW}---${RESET}"
        echo -e "${CYAN}Launching automatic configuration for '$SERVICE_NAME'...${RESET}"

        CONF_FILE="${CONF_DIR}/${SERVICE_NAME}.conf"
        HOSTS_FILE="${HOSTS_DIR}/${SERVICE_NAME}.hosts"

        if [ -f "$CONF_FILE" ]; then
            echo -e "${RED}❌ Error: Configuration for '$SERVICE_NAME' already exists. Exiting.${RESET}"
            exit 1
        fi

        # Determine the primary domain name dynamically
        primary_domain="${SERVICE_NAME}.com"
        if [ "${SERVICE_NAME}" = "google-gemini" ]; then
            primary_domain="gemini.google.com"
        elif [ "${SERVICE_NAME}" = "youtube" ]; then
            primary_domain="youtube.com"
        fi

        # 1. Primary Source: Query the V2Fly database recursively
        fetch_v2fly_domains "$SERVICE_NAME"

        # 2. Secondary Fallback: Scrape crt.sh JSON via standard grep/sed if V2Fly failed
        if [ ! -s "$DOMAINS_TEMP" ]; then
            echo -e "${YELLOW}[+] V2Fly empty. Falling back to crt.sh for ${primary_domain}...${RESET}"
            json=$(curl -s --connect-timeout 6 "https://crt.sh/json?q=${primary_domain}" || true)
            if [ -n "$json" ]; then
                echo "$json" | grep -o -E '"common_name":"[^"]+"' | cut -d'"' -f4 | grep -v '\*' >> "$DOMAINS_TEMP" || true
                echo "$json" | grep -o -E '"name_value":"[^"]+"' | cut -d'"' -f4 | tr '\\n' '\n' | grep -v '\*' >> "$DOMAINS_TEMP" || true
            fi
        fi

        # 3. Final Fallback: Add baseline primary domain if both failed
        if [ ! -s "$DOMAINS_TEMP" ]; then
            echo "$primary_domain" >> "$DOMAINS_TEMP"
        fi

        # Sort, remove duplicate domains, and strip any leading dots
        sort -u "$DOMAINS_TEMP" | sed 's/^\.//' > "$DOMAINS_TEMP.sorted"

        # Extract unique parent root domains (supports 2-part and 3-part public suffixes)
        while IFS= read -r domain || [ -n "$domain" ]; do
            [[ -z "$domain" ]] && continue
            
            # Optimization: Filter out regional Google TLDs (e.g. google.fr, google.it)
            # We only keep Google domains ending in .com, .cn, .dev, .org, or .net
            if [[ "$domain" =~ google\.[a-z]{2,3}$ || "$domain" =~ google\.co\.[a-z]{2}$ || "$domain" =~ google\.com\.[a-z]{2}$ ]]; then
                if [[ ! "$domain" =~ \.com$ && ! "$domain" =~ \.cn$ && ! "$domain" =~ \.dev$ && ! "$domain" =~ \.org$ && ! "$domain" =~ \.net$ ]]; then
                    continue
                fi
            fi

            # Public Suffix Detector: If the domain ends with .co.xx, .com.xx, etc., take the last 3 parts
            if [[ "$domain" =~ \.co\.[a-z]{2}$ || "$domain" =~ \.com\.[a-z]{2}$ || "$domain" =~ \.org\.[a-z]{2}$ || "$domain" =~ \.net\.[a-z]{2}$ ]]; then
                root=$(echo "$domain" | awk -F. '{if (NF>=3) print $(NF-2)"."$(NF-1)"."$NF; else print $0}')
            else
                root=$(echo "$domain" | awk -F. '{if (NF>=2) print $(NF-1)"."$NF; else print $0}')
            fi
            echo "$root" >> "$ROOTS_TEMP"
        done < "$DOMAINS_TEMP.sorted"
        
        sort -u "$ROOTS_TEMP" > "$ROOTS_TEMP.unique"

        # Write clean hosts database file containing all discovered domains
        echo -e "${SNIPROXY_IP} ${primary_domain}\n${SNIPROXY_IP} *.${primary_domain}" > "$HOSTS_FILE"
        while IFS= read -r domain; do
            [[ -z "$domain" || "$domain" = "$primary_domain" ]] && continue
            
            # Apply same Google TLD filter to the hosts file
            if [[ "$domain" =~ google\.[a-z]{2,3}$ || "$domain" =~ google\.co\.[a-z]{2}$ || "$domain" =~ google\.com\.[a-z]{2}$ ]]; then
                if [[ ! "$domain" =~ \.com$ && ! "$domain" =~ \.cn$ && ! "$domain" =~ \.dev$ && ! "$domain" =~ \.org$ && ! "$domain" =~ \.net$ ]]; then
                    continue
                fi
            fi
            
            echo "${SNIPROXY_IP} ${domain}" >> "$HOSTS_FILE"
        done < "$DOMAINS_TEMP.sorted"

        # Dynamically count the written lines
        domain_count=0
        if [ -f "$HOSTS_FILE" ]; then
            domain_count=$(wc -l < "$HOSTS_FILE")
        fi

        # Write separate, clean, comma-free server blocks for each parent root domain
        # Checks for and skips any duplicate zones already claimed by other config files!
        true > "$CONF_FILE" # Clear any existing file
        while IFS= read -r root_zone || [ -n "$root_zone" ]; do
            [[ -z "$root_zone" ]] && continue
            
            # Skip any invalid TLD zones (must contain at least one dot to be a valid server block)
            if [[ ! "$root_zone" =~ \. ]]; then
                continue
            fi

            # Live Duplicate Scanner: Prevents duplicate zone crashes
            duplicate_found=0
            if ls "$CONF_DIR"/*.conf &>/dev/null; then
                if grep -rn "^${root_zone} {" "$CONF_DIR"/*.conf &>/dev/null; then
                    duplicate_found=1
                fi
            fi
            
            if [ "$duplicate_found" -eq 1 ]; then
                echo -e "${YELLOW}⚠️  Overlapping zone '${root_zone}' already defined in another service. Skipping block.${RESET}"
                continue
            fi

            # Escape dots for rewrite regex (e.g. githubcopilot.com -> githubcopilot\.com)
            escaped_zone=$(echo "$root_zone" | sed 's/\./\\./g')

            # Resolved: Added 'no_reverse' to the auto-generated hosts block
            cat <<EOL >> "$CONF_FILE"
${root_zone} {
    # Dynamically rewrite wildcard subdomains to the root domain internally
    rewrite stop {
        name regex (.*)\.${escaped_zone} ${root_zone}
        answer auto
    }
    hosts ${HOSTS_FILE} {
        no_reverse
        fallthrough
        ttl 300
    }
    forward . 1.1.1.1 8.8.8.8
    log
    errors
}
EOL
        done < "$ROOTS_TEMP.unique"

        echo -e "${GREEN}✅ Successfully parsed and added ${domain_count} domains to: ${HOSTS_FILE}${RESET}"
        echo -e "${GREEN}✅ Created CoreDNS config file: ${CONF_FILE}${RESET}"
        echo -e "${CYAN}Restarting CoreDNS...${RESET}"
        sudo systemctl restart coredns
        echo -e "${GREEN}[+] Setup completed successfully.${RESET}"
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

        # Write clean manual reference list
        echo -e "${SNIPROXY_IP} ${ROOT_DOMAIN}\n${SNIPROXY_IP} *.${ROOT_DOMAIN}" > "$HOSTS_FILE"
        echo -e "${GREEN}✅ Created hosts file: ${HOSTS_FILE}${RESET}"

        # Escape dots for rewrite regex (e.g. example.com -> example\.com)
        ESCAPED_DOMAIN=$(echo "$ROOT_DOMAIN" | sed 's/\./\\./g')

        # Clean, single-domain server block (no commas, no wildcards in header)
        cat <<EOL > "$CONF_FILE"
${ROOT_DOMAIN} {
    rewrite stop {
        name regex (.*)\.${ESCAPED_DOMAIN} ${ROOT_DOMAIN}
        answer auto
    }
    hosts ${HOSTS_FILE} {
        no_reverse
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
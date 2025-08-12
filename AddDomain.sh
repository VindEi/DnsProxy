#!/bin/bash
set -e

#===[ Constants ]===
VPS_IP="193.56.135.102"
CONF_DIR="/etc/coredns/conf.d"
HOSTS_DIR="/etc/unblocker"

#===[ Colors ]===
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

#===[ Usage Check ]===
if [ "$#" -ne 1 ]; then
    echo -e "${RED}Usage:${RESET} sudo $0 example.com"
    exit 1
fi

DOMAIN="$1"
BASENAME=$(basename "$DOMAIN")
CONF_FILE="$CONF_DIR/$BASENAME.conf"
HOSTS_FILE="$HOSTS_DIR/$BASENAME.hosts"

mkdir -p "$CONF_DIR" "$HOSTS_DIR"

#===[ Check python3/requests ]===
if ! command -v python3 &>/dev/null; then
    echo -e "${YELLOW}Installing python3 & requests...${RESET}"
    apt update && apt install -y python3 python3-pip
fi

python3 - <<EOF || echo -e "${YELLOW}requests module may already be installed${RESET}"
import requests
EOF

pip3 install requests --quiet >/dev/null 2>&1 || true

#===[ Subdomain Fetch ]===
echo -e "${CYAN}📡 Fetching subdomains for *.$DOMAIN from crt.sh...${RESET}"

python3 <<END > "$HOSTS_FILE" || true
import requests
import time
import sys

domain = "$DOMAIN"
ip = "$VPS_IP"
max_retries = 5
headers = {'User-Agent': 'Mozilla/5.0'}

def fetch_subdomains():
    url = f"https://crt.sh/json?q={domain}"
    for attempt in range(1, max_retries + 1):
        try:
            print(f"Attempt {attempt}...", file=sys.stderr)
            resp = requests.get(url, headers=headers, timeout=20)
            if resp.status_code == 200:
                return {entry['name_value'] for entry in resp.json()}
            else:
                print(f"Error: HTTP {resp.status_code}", file=sys.stderr)
        except Exception as e:
            print(f"Error: {e}", file=sys.stderr)
        time.sleep(2)
    return set()

def clean(d):
    return d.replace("*.", "").strip().lower()

raw = fetch_subdomains()
subs = set()
for entry in raw:
    for line in entry.splitlines():
        if line.endswith(domain):
            subs.add(clean(line))

subs.add(domain)

for sub in sorted(subs):
    print(f"{ip} {sub}")
END

#===[ Check for fallback ]===
if [ ! -s "$HOSTS_FILE" ]; then
    echo -e "${YELLOW}⚠️ Failed to auto-fetch. Switching to manual mode...${RESET}"
    echo -e "${CYAN}Enter comma-separated subdomains (or press Enter to use defaults):${RESET}"
    echo -e "Example: ${GREEN}www.$DOMAIN, open.$DOMAIN, api.$DOMAIN${RESET}"
    read -rp "> " MANUAL

    if [ -z "$MANUAL" ]; then
        SUBDOMAINS="www.$DOMAIN open.$DOMAIN api.$DOMAIN $DOMAIN"
    else
        SUBDOMAINS=$(echo "$MANUAL" | tr ',' ' ')
    fi

    echo -e "${YELLOW}📝 Writing fallback to ${HOSTS_FILE}...${RESET}"
    : > "$HOSTS_FILE"
    for sub in $SUBDOMAINS; do
        echo "$VPS_IP $sub" >> "$HOSTS_FILE"
    done
fi

#===[ Write CoreDNS Config ]===
echo -e "${YELLOW}🧩 Writing CoreDNS config to ${CONF_FILE}...${RESET}"
tee "$CONF_FILE" > /dev/null <<EOF
$DOMAIN {
    hosts $HOSTS_FILE {
        fallthrough
        ttl 300
    }
    log
    errors
}
EOF

#===[ Restart CoreDNS ]===
echo -e "${CYAN}🔄 Restarting CoreDNS...${RESET}"
systemctl restart coredns && echo -e "${GREEN}✅ $DOMAIN added/updated successfully!${RESET}"

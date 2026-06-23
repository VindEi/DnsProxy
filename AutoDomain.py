import requests
import time
import subprocess
import os
import sys

# --- Script Configuration ---
CONF_DIR = "/etc/coredns/conf.d"
HOSTS_DIR = "/etc/unblocker"

# Smart Service-Name Map for V2Fly
V2FLY_MAP = {
    "gemini": "google-gemini",
    "google-gemini": "google-gemini",
    "deepmind": "google-deepmind",
    "google-deepmind": "google-deepmind"
}

def fetch_domains_from_v2fly(service_name):
    """
    Queries the official V2Fly community database for standard, accurate,
    and complete CDN/domain mappings of the target service.
    """
    mapped_name = V2FLY_MAP.get(service_name.lower(), service_name.lower())
    url = f"https://raw.githubusercontent.com/v2fly/domain-list-community/master/data/{mapped_name}"
    domains = set()
    try:
        print(f"[+] Querying V2Fly database for '{mapped_name}' domains...")
        response = requests.get(url, timeout=8)
        if response.status_code == 200:
            lines = response.text.split("\n")
            for line in lines:
                line = line.strip()
                # Skip comments and empty lines
                if not line or line.startswith("#"):
                    continue
                # Handle full domain formats
                if line.startswith("full:"):
                    domain = line.replace("full:", "").split("@")[0].strip()
                    domains.add(domain)
                # Skip advanced regexp, keywords, and nested includes
                elif line.startswith("regexp:") or line.startswith("keyword:") or line.startswith("include:"):
                    continue
                else:
                    domain = line.split("@")[0].strip()
                    domains.add(domain)
            print(f"[+] Successfully fetched {len(domains)} domains from v2fly.")
            return domains
    except Exception as e:
        print(f"[!] V2Fly query failed: {e}")
    return set()

def fetch_subdomains_crtsh(domain, retries=2, delay=3):
    """
    Fallback method to query crt.sh if V2Fly does not contain the service.
    """
    url = f"https://crt.sh/json?q={domain}"
    subdomains = set()
    for attempt in range(retries):
        try:
            print(f"[+] Falling back to crt.sh query for {domain}...")
            response = requests.get(url, timeout=6)
            response.raise_for_status()
            data = response.json()
            for entry in data:
                for key in ['common_name', 'name_value']:
                    if key in entry:
                        names = entry[key].split('\n')
                        for name in names:
                            name = name.strip()
                            if name and '*' not in name:
                                subdomains.add(name)
            return subdomains
        except Exception as e:
            print(f"[!] crt.sh attempt {attempt+1} failed: {e}")
            if attempt < retries - 1:
                time.sleep(delay)
    return set()

def write_coredns_files(service_name, domains, sniproxy_ip):
    HOSTS_FILE = os.path.join(HOSTS_DIR, f"{service_name}.hosts")
    CONF_FILE = os.path.join(CONF_DIR, f"{service_name}.conf")

    # Re-write the clean hosts database file
    with open(HOSTS_FILE, "w") as f:
        for domain in sorted(list(domains)):
            f.write(f"{sniproxy_ip} {domain}\n")
    print(f"[+] Written {len(domains)} domains to {HOSTS_FILE}")

    # Build the CoreDNS zones line containing ONLY the specific active domains
    zones_string = " ".join(sorted(list(domains)))

    # Write unified CoreDNS config using the hosts file approach
    with open(CONF_FILE, "w") as f:
        f.write(f"""{zones_string} {{
    hosts {HOSTS_FILE} {{
        fallthrough
        ttl 300
    }}
    forward . 1.1.1.1 8.8.8.8
    log
    errors
}}
""")
    print(f"[+] Created CoreDNS config file: {CONF_FILE}")

def restart_coredns():
    print("[+] Restarting CoreDNS...")
    try:
        subprocess.run(["sudo", "systemctl", "restart", "coredns"], check=True)
        print("[+] CoreDNS restarted successfully.")
    except subprocess.CalledProcessError as e:
        print(f"[!] Failed to restart CoreDNS. Error: {e}")

def main():
    os.makedirs(CONF_DIR, exist_ok=True)
    os.makedirs(HOSTS_DIR, exist_ok=True)
    
    if len(sys.argv) != 3:
        print("Usage: python3 <script_name.py> <service_name> <sniproxy_ip>")
        sys.exit(1)

    service_name = sys.argv[1].strip()
    sniproxy_ip = sys.argv[2].strip()

    print(f"[+] Running in automatic hosts-based mode for service '{service_name}'")

    all_domains = set()
    
    # 1. Primary Source: Query the lightning-fast V2Fly database
    all_domains.update(fetch_domains_from_v2fly(service_name))
    
    # 2. Secondary Fallback: If V2Fly returned nothing, use crt.sh
    if not all_domains:
        primary_domain = f"{service_name}.com"
        if service_name.lower() == "gemini":
            primary_domain = "gemini.google.com"
        elif service_name.lower() == "youtube":
            primary_domain = "youtube.com"
            
        all_domains.update(fetch_subdomains_crtsh(primary_domain))
        
    # 3. Final Fallback: Use standard domain if both failed
    if not all_domains:
        all_domains.add(f"{service_name.lower()}.com")

    print(f"\n[+] Found a total of {len(all_domains)} unique domains.")

    # File Generation (Using Unified Hosts File)
    write_coredns_files(service_name, all_domains, sniproxy_ip)

    # Restart CoreDNS
    restart_coredns()
    print("\n[+] Setup is complete.")

if __name__ == "__main__":
    main()
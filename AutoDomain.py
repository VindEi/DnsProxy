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

def fetch_domains_from_v2fly(service_name, visited=None):
    if visited is None:
        visited = set()

    mapped_name = V2FLY_MAP.get(service_name.lower(), service_name.lower())
    if mapped_name in visited:
        return set()
    visited.add(mapped_name)

    url = f"https://raw.githubusercontent.com/v2fly/domain-list-community/master/data/{mapped_name}"
    domains = set()
    try:
        print(f"[+] Querying V2Fly database for '{mapped_name}' domains...")
        response = requests.get(url, timeout=8)
        if response.status_code == 200:
            lines = response.text.split("\n")
            for line in lines:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                
                # Recursive Include Resolution
                if line.startswith("include:"):
                    included_service = line.replace("include:", "").split("@")[0].strip()
                    domains.update(fetch_domains_from_v2fly(included_service, visited))
                elif line.startswith("full:"):
                    domain = line.replace("full:", "").split("@")[0].strip()
                    domains.add(domain)
                elif line.startswith("regexp:") or line.startswith("keyword:"):
                    continue
                else:
                    domain = line.split("@")[0].strip()
                    domains.add(domain)
            return domains
    except Exception as e:
        print(f"[!] V2Fly query failed for '{mapped_name}': {e}")
    return set()

def fetch_subdomains_crtsh(domain, retries=2, delay=3):
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

def write_coredns_files(service_name, domains, sniproxy_ip, primary_domain):
    HOSTS_FILE = os.path.join(HOSTS_DIR, f"{service_name}.hosts")
    CONF_FILE = os.path.join(CONF_DIR, f"{service_name}.conf")

    # 1. Write the clean hosts database file containing all discovered domains
    with open(HOSTS_FILE, "w") as f:
        # Include root and wildcard for the primary domain as well
        f.write(f"{sniproxy_ip} {primary_domain}\n")
        f.write(f"{sniproxy_ip} *.{primary_domain}\n")
        for domain in sorted(list(domains)):
            if domain != primary_domain:
                f.write(f"{sniproxy_ip} {domain}\n")
    print(f"[+] Written {len(domains)} domains to {HOSTS_FILE}")

    # 2. Restored: Your exact original single server block format (fixed whitespace typo)
    with open(CONF_FILE, "w") as f:
        f.write(f"""{primary_domain}, *.{primary_domain} {{
    hosts {HOSTS_FILE} {{
        fallthrough
        ttl 300
    }}
    log
    errors
}}
""")
    print(f"[+] Created CoreDNS configuration file: {CONF_FILE}")

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
    all_domains.update(fetch_domains_from_v2fly(service_name))
    
    # Restored: Map the correct primary domain
    primary_domain = f"{service_name}.com"
    if service_name.lower() == "gemini":
        primary_domain = "gemini.google.com"
    elif service_name.lower() == "youtube":
        primary_domain = "youtube.com"
    
    if not all_domains:
        all_domains.update(fetch_subdomains_crtsh(primary_domain))
        
    if not all_domains:
        all_domains.add(primary_domain)

    print(f"\n[+] Found a total of {len(all_domains)} unique domains.")

    write_coredns_files(service_name, all_domains, sniproxy_ip, primary_domain)
    restart_coredns()
    print("[+] Setup is complete.")

if __name__ == "__main__":
    main()
import requests
import time
import subprocess
import os
import sys

# --- Script Configuration ---
CONF_DIR = "/etc/coredns/conf.d"
HOSTS_DIR = "/etc/unblocker"

def fetch_domains_from_v2fly(service_name, visited=None):
    """
    Queries the official V2Fly database by dynamically trying common naming
    permutations to find the correct file without any hardcoded mappings.
    """
    if visited is None:
        visited = set()

    service_name_clean = service_name.lower().strip()
    if service_name_clean in visited:
        return set()
    visited.add(service_name_clean)

    # Programmatic permutations to locate the database entry dynamically
    permutations = [
        service_name_clean,
        f"google-{service_name_clean}",
        f"category-{service_name_clean}"
    ]

    for name in permutations:
        url = f"https://raw.githubusercontent.com/v2fly/domain-list-community/master/data/{name}"
        domains = set()
        try:
            response = requests.get(url, timeout=5)
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
        except Exception:
            pass
    return set()

def fetch_subdomains_crtsh(domain, retries=2, delay=3):
    """
    Fallback resolver to query public certificate logs if the service is not in V2Fly.
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

def determine_primary_domain(service_name, domains):
    """
    Programmatically elects the primary zone domain from the fetched domains list
    by matching string proximity, completely removing hardcoded domain checks.
    """
    service_name_lower = service_name.lower().strip()
    
    # 1. Search for exact or closest match in the discovered domains list
    for domain in sorted(list(domains), key=len):
        if domain == f"{service_name_lower}.com" or domain == f"www.{service_name_lower}.com":
            return domain
        if domain.startswith(service_name_lower) or service_name_lower in domain:
            return domain
            
    # 2. Fallback to standard domain naming
    return f"{service_name_lower}.com"

def write_coredns_files(service_name, domains, sniproxy_ip, primary_domain):
    HOSTS_FILE = os.path.join(HOSTS_DIR, f"{service_name}.hosts")
    CONF_FILE = os.path.join(CONF_DIR, f"{service_name}.conf")

    # Write the hosts file database
    with open(HOSTS_FILE, "w") as f:
        f.write(f"{sniproxy_ip} {primary_domain}\n")
        f.write(f"{sniproxy_ip} *.{primary_domain}\n")
        for domain in sorted(list(domains)):
            if domain != primary_domain:
                f.write(f"{sniproxy_ip} {domain}\n")
    print(f"[+] Written {len(domains)} domains to {HOSTS_FILE}")

    # Write the single server block configuration file
    with open(CONF_FILE, "w") as f:
        f.write(f"""{primary_domain}, *.{primary_domain} {{
    hosts {HOSTS_FILE} {{
        fallthrough
        ttl 300
    }}
    forward . 1.1.1.1 8.8.8.8
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
    
    # Dynamically determine the best primar
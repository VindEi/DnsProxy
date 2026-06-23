import requests
import time
import subprocess
import os
import sys

# --- Script Configuration ---
CONF_DIR = "/etc/coredns/conf.d"

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
            print(f"[+] Successfully fetched {len(domains)} domains from v2fly.")
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

def get_root_domains(domains):
    """
    Extracts the unique root domains (e.g. api.spotify.com -> spotify.com)
    to keep the Corefile server blocks minimized and extremely fast.
    """
    roots = set()
    for domain in domains:
        parts = domain.lower().split('.')
        if len(parts) >= 2:
            root = ".".join(parts[-2:])
            roots.add(root)
        else:
            roots.add(domain)
    return roots

def write_coredns_files(service_name, domains, sniproxy_ip):
    CONF_FILE = os.path.join(CONF_DIR, f"{service_name}.conf")

    # 1. Extract the parent root domains (keeps header small and clean)
    root_domains = get_root_domains(domains)
    root_zones_string = " ".join(sorted(list(root_domains)))

    # 2. Escape dots for regex matching (e.g. gemini.google.com -> gemini\.google\.com)
    escaped_domains = "|".join([d.replace(".", r"\.") for d in domains])

    # 3. Write self-contained config using Regex matching template
    with open(CONF_FILE, "w") as f:
        f.write(f"""{root_zones_string} {{
    # Intercept ONLY the specific unblocked subdomains
    template IN A {{
        match ^(.*)({escaped_domains})\\.\$
        answer "{{{{ .Name }}}} 300 IN A {sniproxy_ip}"
        fallthrough
    }}
    template IN AAAA {{
        match ^(.*)({escaped_domains})\\.\$
        rcode NOERROR
        fallthrough
    }}
    # Fallback to upstream for all other queries (e.g. regular google searches)
    forward . 1.1.1.1 8.8.8.8
    log
    errors
}}
""")
    print(f"[+] Created CoreDNS regex-filtered config file: {CONF_FILE}")

def restart_coredns():
    print("[+] Restarting CoreDNS...")
    try:
        subprocess.run(["sudo", "systemctl", "restart", "coredns"], check=True)
        print("[+] CoreDNS restarted successfully.")
    except subprocess.CalledProcessError as e:
        print(f"[!] Failed to restart CoreDNS. Error: {e}")

def main():
    os.makedirs(CONF_DIR, exist_ok=True)
    
    if len(sys.argv) != 3:
        print("Usage: python3 <script_name.py> <service_name> <sniproxy_ip>")
        sys.exit(1)

    service_name = sys.argv[1].strip()
    sniproxy_ip = sys.argv[2].strip()

    print(f"[+] Running in automatic hosts-based mode for service '{service_name}'")

    all_domains = set()
    all_domains.update(fetch_domains_from_v2fly(service_name))
    
    if not all_domains:
        primary_domain = f"{service_name}.com"
        if service_name.lower() == "gemini":
            primary_domain = "gemini.google.com"
        elif service_name.lower() == "youtube":
            primary_domain = "youtube.com"
            
        all_domains.update(fetch_subdomains_crtsh(primary_domain))
        
    if not all_domains:
        all_domains.add(f"{service_name.lower()}.com")

    print(f"\n[+] Found a total of {len(all_domains)} unique domains.")

    write_coredns_files(service_name, all_domains, sniproxy_ip)
    restart_coredns()
    print("\n[+] Setup is complete.")

if __name__ == "__main__":
    main()
import requests
import time
import subprocess
import os
import sys

# --- Script Configuration ---
# Set the base directories based on your CoreDNS setup
CONF_DIR = "/etc/coredns/conf.d"
HOSTS_DIR = "/etc/unblocker"

# --- Helper Functions for Domain Discovery ---

def fetch_subdomains_crtsh(domain, retries=3, delay=5):
    """
    Fetches subdomains from crt.sh by querying certificate transparency logs.
    This method is good for finding official subdomains that have SSL certs.
    """
    url = f"https://crt.sh/json?q={domain}"
    subdomains = set()
    for attempt in range(retries):
        try:
            print(f"[+] Attempting to fetch subdomains from crt.sh for {domain}...")
            response = requests.get(url, timeout=10)
            response.raise_for_status()
            data = response.json()
            for entry in data:
                # 'common_name' and 'name_value' contain the domains
                for key in ['common_name', 'name_value']:
                    if key in entry:
                        names = entry[key].split('\n')
                        for name in names:
                            name = name.strip()
                            if name and '*' not in name:
                                subdomains.add(name)
            return subdomains
        except requests.exceptions.RequestException as e:
            print(f"[!] Attempt {attempt+1} failed to reach crt.sh: {e}")
            if attempt < retries - 1:
                print(f"[+] Retrying in {delay} seconds...")
                time.sleep(delay)
            else:
                print("[!] Failed to fetch crt.sh data after retries.")
                return set()
        except Exception as e:
            print(f"[!] An error occurred while parsing crt.sh data: {e}")
            return set()
    return set()

def fetch_domains_from_curated_lists(service_name):
    """
    (Placeholder) Simulates fetching a domain list from curated online lists.
    This function demonstrates how a robust script would find domains from sources
    like GitHub repositories or network configuration forums. In a real implementation,
    this would involve web scraping or using a public API.
    """
    print(f"[+] Searching for public domain lists for {service_name}...")
    
    # This is mock data for demonstration purposes, showing a more comprehensive list
    # that combines various domains, not just direct subdomains.
    if service_name.lower() == "spotify":
        return {
            "spotify.com", "api.spotify.com", "spclient.wg.spotify.com",
            "audio-fa.scdn.co", "spotifycdn.com", "scdn.co", "to.spotify.com",
            "open.spotify.com", "i.scdn.co", "ap-http-lb.spotify.com",
            "audio-ak-spotify-com.akamaized.net", "guc-spclient.spotify.com"
        }
    elif service_name.lower() == "gemini":
        return {
            "gemini.google.com", "lti.gemini.google.com", "client.gemini.google.com",
            "generativelanguage.googleapis.com", "accounts.google.com",
            "gstatic.com"
        }
    else:
        return set()

def get_predefined_domains(service_name):
    """
    Returns a small, predefined list of domains to ensure essential ones are included.
    This acts as a solid fallback.
    """
    domains = {
        "spotify": {"spotify.com", "scdn.co", "spotifycdn.com"},
        "gemini": {"gemini.google.com", "gstatic.com"}
    }
    return domains.get(service_name.lower(), set())

def write_coredns_files(service_name, domains, sniproxy_ip, primary_domain):
    """
    Creates and populates the .conf and .hosts files for CoreDNS.
    The primary_domain is used to correctly configure the Corefile zone.
    """
    # Define file paths
    HOSTS_FILE = os.path.join(HOSTS_DIR, f"{service_name}.hosts")
    CONF_FILE = os.path.join(CONF_DIR, f"{service_name}.conf")

    # Create the hosts file
    with open(HOSTS_FILE, "w") as f:
        for domain in sorted(list(domains)):
            f.write(f"{sniproxy_ip} {domain}\n")
    print(f"[+] Written {len(domains)} domains to {HOSTS_FILE}")

    # Create the CoreDNS configuration file
    with open(CONF_FILE, "w") as f:
        f.write(f"""{primary_domain} {{
    hosts {HOSTS_FILE} {{
        fallthrough
        ttl 300
    }}
    log
    errors
}}
""")
    print(f"[+] Created CoreDNS config file: {CONF_FILE}")

def restart_coredns():
    """
    Restarts the CoreDNS service.
    """
    print("[+] Restarting CoreDNS...")
    try:
        # Using check=True will raise an exception if the command fails
        subprocess.run(["sudo", "systemctl", "restart", "coredns"], check=True)
        print("[+] CoreDNS restarted successfully.")
    except subprocess.CalledProcessError as e:
        print(f"[!] Failed to restart CoreDNS. Error: {e}")
        print("[!] Please try restarting it manually with 'sudo systemctl restart coredns'.")

def main():
    """
    Main function to run the automated setup process.
    Accepts arguments from the command line and exits if not provided.
    """
    # Ensure required directories exist
    os.makedirs(CONF_DIR, exist_ok=True)
    os.makedirs(HOSTS_DIR, exist_ok=True)
    
    # Handle command-line arguments from the bash script
    if len(sys.argv) != 3:
        print("Usage: python3 <script_name.py> <service_name> <sniproxy_ip>")
        sys.exit(1)

    service_name = sys.argv[1].strip()
    sniproxy_ip = sys.argv[2].strip()

    print(f"[+] Running in automatic mode with service '{service_name}' and sniproxy IP '{sniproxy_ip}'")

    if not service_name or not sniproxy_ip:
        print("Service name or sniproxy IP cannot be empty. Exiting.")
        sys.exit(1)

    # Determine the primary domain from the service name
    primary_domain = f"{service_name}.com"
    if service_name.lower() == "gemini":
        primary_domain = "gemini.google.com"
    elif service_name.lower() == "youtube":
        primary_domain = "youtube.com"

    print(f"\n[+] Starting automatic domain discovery for {service_name}...")
    all_domains = set()
    
    # Method 1: Fetch from crt.sh
    all_domains.update(fetch_subdomains_crtsh(primary_domain))
    
    # Method 2: Fetch from search results (using a placeholder for now)
    all_domains.update(fetch_domains_from_curated_lists(service_name))
    
    # Method 3: Add predefined, essential domains
    all_domains.update(get_predefined_domains(service_name))

    if not all_domains:
        print("[!] No domains were found for this service. Aborting.")
        sys.exit(1)

    print(f"\n[+] Found a total of {len(all_domains)} unique domains.")

    # File Generation
    write_coredns_files(service_name, all_domains, sniproxy_ip, primary_domain)

    # Restart CoreDNS to apply changes
    restart_coredns()
    
    print("\n[+] Setup is complete. You may need to flush your local DNS cache.")

if __name__ == "__main__":
    main()

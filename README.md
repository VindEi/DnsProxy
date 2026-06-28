# DnsProxy

A self-contained local DNS server and SNI reverse proxy written in Bash. It intercepts DNS queries for configured domains, resolves them to your server IP, and proxies the raw TLS traffic via Nginx [6.1, 6.2, 6.7].

---

## 🚀 Installation

Run this command on your VPS as root [6.5]:
```bash
curl -s https://raw.githubusercontent.com/VindEi/DnsProxy/main/auto_install.sh | bash
```
Once the installer completes, run the dashboard [6.5]:
```bash
dnsproxy
```
Choose `1` to run the core installation (deploys CoreDNS, Nginx, and UFW rules) [6.5, 6.6].

---

## 🛠️ CLI Commands & Automation

You can manage your unblocked services directly from your terminal shell without entering the interactive menu [6.5]:

```bash
# Add a service automatically (Queries the V2Fly database)
dnsproxy add spotify auto
dnsproxy add gemini auto

# Add a service manually
dnsproxy add mydomain manual

# Remove an active service cleanly
dnsproxy remove spotify
```

---

## ⚙️ Manual Configuration & Server Editing

If you need to manually edit, debug, or tweak configurations directly on the server, use these paths and commands [6.5]:

### 1. File Locations
* **Main CoreDNS Config**: `/etc/coredns/Corefile`
* **Service Config Blocks**: `/etc/coredns/conf.d/{service}.conf`
* **Service Domain Databases**: `/etc/unblocker/{service}.hosts`
* **Nginx Stream Proxy**: `/etc/nginx/stream.d/smartdns.conf`
* **Nginx HTTP Proxy**: `/etc/nginx/conf.d/http_proxy.conf`

### 2. Manually Rebuilding the Master Database
If you manually edit or add any files inside `/etc/unblocker/*.hosts`, you must compile them into the master unified database and restart CoreDNS [6.5]:
```bash
# Merge all individual hosts files (excluding wildcards) into the master database
sudo find /etc/unblocker/ -name "*.hosts" -exec cat {} + | sed '/\*/d' | sudo tee /etc/coredns/unified.hosts > /dev/null

# Restart CoreDNS to load the updates
sudo systemctl restart coredns
```

### 3. Debugging CoreDNS in the Foreground
If CoreDNS fails to start, you can run the binary directly in your terminal to see the exact syntax or zone errors [6.3, 6.6]:
```bash
/usr/local/bin/coredns -conf /etc/coredns/Corefile
```

---

## 💻 Client Setup

For client devices to use your proxy [6.1]:

1. Set their **Primary DNS** to your VPS IP [6.1].
2. Leave their **Alternate DNS** completely **blank / empty** (if a secondary DNS is left, modern OS clients will failover and bypass your proxy) [6.1].

---

## 🗑️ Uninstallation

To cleanly wipe all configurations, services, custom databases, and commands from your VPS [6.5]:
```bash
sudo /usr/local/bin/DnsProxy/Uninstall.sh
```
---


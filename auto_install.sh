#!/bin/bash

# Define variables
INSTALL_DIR="/usr/local/bin/DnsProxy"
REPO_URL="https://github.com/VindEi/DnsProxy.git"
FILES=("DnsProxy" "Install.sh" "Uninstall.sh" "AddDomain.sh")

echo "🌐 Starting DNSniproxy auto-install..."

# Make sure git is installed
if ! command -v git &> /dev/null; then
    echo "📦 Git not found, installing git..."
    apt update && apt install -y git
fi

# Clone or update repo to /tmp/DNSniproxy
TMP_DIR="/tmp/DNSniproxy"

if [ -d "$TMP_DIR" ]; then
    echo "♻️ Repo already cloned, pulling latest changes..."
    cd "$TMP_DIR" && git pull
else
    echo "📥 Cloning DNSniproxy repo..."
    git clone "$REPO_URL" "$TMP_DIR"
fi

# Create install directory if not exists
if [ ! -d "$INSTALL_DIR" ]; then
    echo "📁 Creating installation directory at $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
fi

# Copy files to install dir
echo "📂 Copying files to $INSTALL_DIR"
for file in "${FILES[@]}"; do
    if [ -f "$TMP_DIR/$file" ]; then
        cp "$TMP_DIR/$file" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/$file"
        echo "✅ $file copied and made executable."
    else
        echo "⚠️ Warning: $file not found in repo."
    fi
done

# Symlink main script to /usr/local/bin for easy access (optional)
ln -sf "$INSTALL_DIR/DnsProxy" /usr/local/bin/DnsProxy

echo "🚀 Running DNSniproxy main menu..."
"$INSTALL_DIR/DnsProxy"

exit 0

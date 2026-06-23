#!/bin/bash
set -euo pipefail

INSTALL_DIR="/usr/local/bin/DnsProxy"
REPO_URL="https://github.com/VindEi/DnsProxy.git"
FILES=("DnsProxy" "Install.sh" "Uninstall.sh" "AddDomain.sh")

echo "🌐 Starting DnsProxy auto-install..."

echo "🔄 Updating and upgrading system packages non-interactively..."
sudo apt update -y && sudo apt upgrade -y

if ! command -v git &> /dev/null; then
    echo "📦 Git not found, installing git..."
    sudo apt install -y git || { echo "❌ Failed to install git. Aborting."; exit 1; }
fi

TMP_DIR="/tmp/DnsProxy"

echo "📥 Fetching latest DnsProxy repo..."
sudo rm -rf "$TMP_DIR"
git clone --depth 1 "$REPO_URL" "$TMP_DIR"
cd "$TMP_DIR"

if [ ! -d "$INSTALL_DIR" ]; then
    echo "📁 Creating installation directory at $INSTALL_DIR"
    sudo mkdir -p "$INSTALL_DIR"
fi

echo "📂 Copying files to $INSTALL_DIR"
for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        sudo cp "$file" "$INSTALL_DIR/"
        sudo chmod +x "$INSTALL_DIR/$file"
        echo "✅ $file copied and made executable."
    else
        echo "⚠️ Warning: $file not found in repo."
    fi
done

echo "🔗 Creating symlink for dnsproxy in /usr/local/bin"
sudo ln -sf "$INSTALL_DIR/DnsProxy" /usr/local/bin/dnsproxy

echo "🚀 Installation complete. You can now run the main menu with the 'dnsproxy' command."

exit 0
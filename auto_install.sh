#!/bin/bash

# Define variables
INSTALL_DIR="/usr/local/bin/DnsProxy"
REPO_URL="https://github.com/VindEi/DnsProxy.git"
FILES=("DnsProxy" "Install.sh" "Uninstall.sh" "AddDomain.sh")

echo "🌐 Starting DnsProxy auto-install..."

# Update and upgrade system packages first
echo "🔄 Updating and upgrading system packages non-interactively..."
sudo apt update -y && sudo apt upgrade -y

# Make sure git is installed
if ! command -v git &> /dev/null; then
    echo "📦 Git not found, installing git..."
    sudo apt install -y git
fi

# Clone or update repo to /tmp/DnsProxy
TMP_DIR="/tmp/DnsProxy"

if [ -d "$TMP_DIR" ]; then
    echo "♻️ Repo already cloned, pulling latest changes..."
    cd "$TMP_DIR" && git pull
else
    echo "📥 Cloning DnsProxy repo..."
    git clone "$REPO_URL" "$TMP_DIR"
fi

# Create install directory if not exists
if [ ! -d "$INSTALL_DIR" ]; then
    echo "📁 Creating installation directory at $INSTALL_DIR"
    sudo mkdir -p "$INSTALL_DIR"
fi

# Copy files to install dir
echo "📂 Copying files to $INSTALL_DIR"
for file in "${FILES[@]}"; do
    if [ -f "$TMP_DIR/$file" ]; then
        sudo cp "$TMP_DIR/$file" "$INSTALL_DIR/"
        sudo chmod +x "$INSTALL_DIR/$file"
        echo "✅ $file copied and made executable."
    else
        echo "⚠️ Warning: $file not found in repo."
    fi
done

# Symlink main script to /usr/local/bin for easy access
sudo ln -sf "$INSTALL_DIR/DnsProxy" /usr/local/bin/DnsProxy

echo "🚀 Running DnsProxy main menu..."
"$INSTALL_DIR/DnsProxy"

exit 0

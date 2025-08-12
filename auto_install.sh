#!/bin/bash

# Define variables
INSTALL_DIR="/usr/local/bin/DnsProxy"
REPO_URL="https://github.com/VindEi/DnsProxy.git"
FILES=("DnsProxy" "Install.sh" "Uninstall.sh" "AddDomain.sh")

echo "🌐 Starting DnsProxy auto-install..."

# --- Update and upgrade system packages ---
echo "🔄 Updating and upgrading system packages non-interactively..."
sudo apt update -y && sudo apt upgrade -y

# --- Check and install git if necessary ---
if ! command -v git &> /dev/null; then
    echo "📦 Git not found, installing git..."
    sudo apt install -y git || { echo "❌ Failed to install git. Aborting."; exit 1; }
fi

# --- Clone or update the repository ---
TMP_DIR="/tmp/DnsProxy"

if [ -d "$TMP_DIR" ]; then
    echo "♻️ Repo already cloned, pulling latest changes..."
    cd "$TMP_DIR" && git pull || { echo "❌ Failed to pull from repo. Aborting."; exit 1; }
else
    echo "📥 Cloning DnsProxy repo..."
    git clone "$REPO_URL" "$TMP_DIR" || { echo "❌ Failed to clone repo. Aborting."; exit 1; }
    cd "$TMP_DIR"
fi

# --- Create install directory if not exists ---
if [ ! -d "$INSTALL_DIR" ]; then
    echo "📁 Creating installation directory at $INSTALL_DIR"
    sudo mkdir -p "$INSTALL_DIR"
fi

# --- Copy files and make them executable ---
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

# --- Symlink main script for easy access ---
echo "🔗 Creating symlink for dnsproxy in /usr/local/bin"
sudo ln -sf "$INSTALL_DIR/DnsProxy" /usr/local/bin/dnsproxy

echo "🚀 Installation complete. You can now run the main menu with the 'dnsproxy' command."

exit 0

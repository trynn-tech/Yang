#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -euo pipefail

echo "===================================================="
echo " Installing On-Demand SSH with 24h Auto-Teardown"
echo "===================================================="

# 1. Detect Environment & Install Packages
if command -v pkg &> /dev/null && [ -d "/data/data/com.termux" ]; then
    echo "[+] Termux environment detected."
    pkg update -y
    pkg install -y tmux keychain openssh at
elif command -v apt-get &> /dev/null; then
    echo "[+] Debian/Ubuntu environment detected."
    sudo apt-get update -y
    sudo apt-get install -y tmux keychain openssh-client at
else
    echo "[!] Non-standard environment. Ensure tmux, keychain, and at are installed manually."
fi

# Ensure the 'atd' daemon is enabled if running natively on standard Linux
if command -v systemctl &> /dev/null && ! systemctl is-active --quiet atd; then
    sudo systemctl enable --now atd 2>/dev/null || true
fi

# 2. Establish Config Directories
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
mkdir -p "$HOME/.tmux"

# 3. Inject On-Demand Init, Teardown, and Timer into .bashrc
SHELL_RC="$HOME/.bashrc"
TEARDOWN_SCRIPT="$HOME/.ssh/ssh-teardown.sh"
echo "[+] Target shell configuration: $SHELL_RC"

# Create a dedicated, self-contained teardown script to bypass non-interactive .bashrc limits
cat << 'EOF' > "$TEARDOWN_SCRIPT"
#!/usr/bin/env bash
echo "[*] Triggering full secure teardown..."

# 1. Wipe keys from memory
if command -v ssh-add &>/dev/null; then
    ssh-add -D &>/dev/null || true
fi

# 2. Kill Keychain/ssh-agent daemons
if command -v keychain &>/dev/null; then
    keychain -k all &>/dev/null || true
fi

# 3. Gracefully kill all active tmux sessions
if command -v tmux &>/dev/null; then
    tmux kill-server 2>/dev/null || true
fi

# 4. Clean up the background sleep fallback process if it exists
# We target the specific script name to avoid killing other sleep tasks
pkill -f "ssh-teardown.sh" 2>/dev/null || true

echo "[+] Environment secure. Sockets wiped and multiplexers terminated."
EOF
chmod +x "$TEARDOWN_SCRIPT"

KEYCHAIN_BLOCK=$(cat << EOF
# === BEGIN AUTOMATIC SSH KEYCHAIN CONFIGURATION ===

ssh-teardown() {
    "$TEARDOWN_SCRIPT"
}

# Protocol: Initialize (Spins up agent, prompts for passphrase, schedules 24h wipe)
ssh-init() {
    if ! command -v keychain &> /dev/null; then
        echo "[!] Error: keychain is not installed."
        return 1
    fi

    echo "[*] Checking for existing SSH agent..."
    eval \$(keychain --eval --agents ssh --noask id_ed25519)

    # Prompt for passphrase if key isn't decrypted yet
    if ! ssh-add -l &>/dev/null; then
        echo "[!] Key not loaded. Prompting for passphrase..."
        keychain id_ed25519
        eval \$(keychain --eval --agents ssh id_ed25519)
    else
        echo "[+] Active SSH agent found and key is already loaded!"
    fi

    # Schedule the 24-hour Auto-Teardown
    echo "[*] Scheduling secure environment teardown in 24 hours..."

    if command -v at &>/dev/null && { command -v sv &>/dev/null || [ ! -d "/data/data/com.termux" ]; }; then
        # Native Linux: Execute the absolute path script directly instead of sourcing .bashrc
        echo "$TEARDOWN_SCRIPT" | at now + 24 hours 2>/dev/null
        echo "[+] Scheduled via system 'at' queue."
    else
        # Termux/Android fallback: Kill old loops and spawn a uniquely identifiable process string
        pkill -f "$TEARDOWN_SCRIPT" 2>/dev/null || true
        (
            sleep 86400
            "$TEARDOWN_SCRIPT"
        ) >/dev/null 2>&1 &
        echo "[+] Background sleep daemon spawned (PID: \$!)."
    fi
}
# === END AUTOMATIC SSH KEYCHAIN CONFIGURATION ===
EOF
)

if ! grep -q "BEGIN AUTOMATIC SSH KEYCHAIN CONFIGURATION" "$SHELL_RC"; then
    echo "$KEYCHAIN_BLOCK" >> "$SHELL_RC"
    echo "[+] Added SSH Keychain configuration to $SHELL_RC"
else
    echo "[-] Configuration already exists in $SHELL_RC"
fi


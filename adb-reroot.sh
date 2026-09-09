#!/usr/bin/env bash
# ==============================================================================
# Samsung Galaxy A54 (A546E) - Automated Root & Chroot Launcher (PC / ADB)
# ==============================================================================

set -u

echo "[*] Waiting for ADB device..."
adb wait-for-device

echo "[*] Stage 1: Setting file permissions..."
adb shell "chmod +x /data/local/tmp/cve-2026-43499-root /data/local/tmp/libcve43499root.so /data/local/tmp/ksud-* 2>/dev/null || true"

ACTIVE_HELPER=""

try_exploit() {
    local helper="$1"
    local so_name="$2"
    echo ""
    echo "[*] ----------------------------------------------------"
    echo "[*] Trying exploit variant: $helper + $so_name"
    echo "[*] ----------------------------------------------------"

    # Remove any stale socket before attempting
    adb shell "rm -f /data/local/tmp/temp_su.sock"

    # Run the exploit and allow output to be visible
    adb shell "CVE43499_ROOT_HELPER=/data/local/tmp/$helper LD_PRELOAD=/data/local/tmp/$so_name /system/bin/true"
    local ret=$?

    # Check if the root daemon socket was created
    for i in 1 2 3; do
        if adb shell "[ -e /data/local/tmp/temp_su.sock ]" 2>/dev/null; then
            echo "[+] Exploit succeeded! Daemon socket (/data/local/tmp/temp_su.sock) is active."
            ACTIVE_HELPER="$helper"
            return 0
        fi
        sleep 1
    done

    echo "[-] Variant $helper + $so_name did not establish daemon socket (exit code: $ret)."
    return 1
}

# Check if root is already available from a previous run
if adb shell "su -c id" 2>/dev/null | grep -q "uid=0"; then
    echo "[+] Root is already active! Skipping exploit execution."
else
    # 1. Primary: cve-2026-43499-root + cve-2026-43499.so
    if ! try_exploit "cve-2026-43499-root" "cve-2026-43499.so"; then
        # 2. Secondary: cve-2026-43499-root + cve-2026-43499-app.so
        if ! try_exploit "cve-2026-43499-root" "cve-2026-43499-app.so"; then
            # 3. Fallback: libcve43499root.so + cve-2026-43499.so
            if ! try_exploit "libcve43499root.so" "cve-2026-43499.so"; then
                # 4. Fallback: libcve43499root.so + cve-2026-43499-app.so
                if ! try_exploit "libcve43499root.so" "cve-2026-43499-app.so"; then
                    echo ""
                    echo "[-] All exploit variants failed. Please reboot the device to reset KASLR."
                    exit 1
                fi
            fi
        fi
    fi

    echo ""
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

    echo "[*] Stage 3: Triggering KernelSU late-load..."
    adb shell "/data/local/tmp/$ACTIVE_HELPER --late-load"
    sleep 2
fi

# Verify root status
echo ""
echo "[*] Verifying root status (su -c id)..."
if adb shell "su -c id" 2>/dev/null | grep -q "uid=0"; then
    echo "[+] ROOT ELEVATION SUCCESSFUL! (KernelSU active)"
    
    echo "[*] Stage 4: Starting Alpine Chroot and Tailscale..."
    adb shell "su -c 'if [ -f /data/local/tmp/start-chroot.sh ]; then sh /data/local/tmp/start-chroot.sh daemon; elif [ -f /data/local/chroot/start-chroot.sh ]; then sh /data/local/chroot/start-chroot.sh daemon; fi'"
    
    echo "[+] Device connected to Tailscale network and ready!"
else
    echo "[-] Late-load completed but su binary did not grant root. A reboot may be required."
    exit 1
fi

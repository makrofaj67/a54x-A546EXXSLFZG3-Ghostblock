#!/usr/bin/env bash
# ==============================================================================
# Complete Purge & Reset Launcher (Host / PC via ADB)
# ==============================================================================
# This script sends purge-all.sh to the phone, runs it as root, and optionally
# reboots the phone to guarantee a 100% clean factory stock state.
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================================"
echo "    ANDROID CHROOT & KERNELSU - COMPLETE PURGE TOOL"
echo "============================================================"
echo "[!] WARNING: This will completely delete:"
echo "    - /data/local/chroot (Alpine, Tailscale state, OpenSSH keys)"
echo "    - /data/local/tmp exploit binaries and scripts"
echo "    - KernelSU runtime module and configurations"
echo "    - Restore SELinux to Enforcing"
echo "============================================================"
read -p "Are you sure you want to proceed with full cleanup? (y/N): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "[-] Aborted by user."
    exit 0
fi

echo ""
echo "[*] Waiting for ADB device..."
adb wait-for-device

echo "[*] Pushing purge-all.sh to device..."
adb push "$SCRIPT_DIR/purge-all.sh" /data/local/tmp/purge-all.sh
adb shell "chmod 755 /data/local/tmp/purge-all.sh"

echo "[*] Executing purge-all.sh as root..."
if adb shell "su -c id" 2>/dev/null | grep -q "uid=0"; then
    adb shell "su -c 'sh /data/local/tmp/purge-all.sh; rm -f /data/local/tmp/purge-all.sh'"
elif [ -f "$SCRIPT_DIR/tmp/cve-2026-43499-root" ]; then
    adb shell "/data/local/tmp/cve-2026-43499-root -c 'sh /data/local/tmp/purge-all.sh; rm -f /data/local/tmp/purge-all.sh'"
else
    echo "[!] Error: Root access could not be acquired to run the purge."
    echo "[!] Please run 'sh /data/local/tmp/purge-all.sh' manually as root inside Termux."
    exit 1
fi

echo ""
read -p "Do you want to reboot the phone now to guarantee 100% stock state? (y/N): " reboot_choice
if [ "$reboot_choice" = "y" ] || [ "$reboot_choice" = "Y" ]; then
    echo "[*] Rebooting device..."
    adb reboot
    echo "[+] Device is rebooting into 100% stock Samsung Knox state."
fi

echo "[+] Cleanup process completed!"

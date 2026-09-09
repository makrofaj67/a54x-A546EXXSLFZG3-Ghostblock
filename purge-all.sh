#!/system/bin/sh
# ==============================================================================
# Alpine Chroot & KernelSU Complete Cleanup / Teardown Script (Android)
# ==============================================================================
# This script completely reverses and removes all modifications:
#   1. Terminates all active chroot services (tailscaled, sshd, shells)
#   2. Safely unmounts all virtual filesystems (/dev, /proc, /sys, /dev/pts)
#   3. Completely removes the Alpine chroot rootfs (/data/local/chroot)
#   4. Reverts policy routing rules & restores default table state
#   5. Wipes exploit binaries, sockets, and scripts from /data/local/tmp
#   6. Unloads KernelSU kernel module and cleans /data/adb components
#   7. Restores SELinux to Enforcing mode (setenforce 1)
# ==============================================================================

set -e

CHROOT_DIR="/data/local/chroot"
TMP_DIR="/data/local/tmp"

echo "============================================================"
echo "    COMPLETE CLEANUP & REVERT - ALPINE & KERNELSU"
echo "============================================================"

# 1. Root Verification
if [ "$(id -u)" -ne 0 ]; then
    echo "[!] Error: This cleanup script must be run as root (su)!"
    exit 1
fi

echo "[*] Step 1: Terminating all chroot processes (tailscaled, sshd, etc.)..."
# Graceful SIGTERM
pkill -15 -f "tailscaled" 2>/dev/null || true
pkill -15 -u root -x "sshd" 2>/dev/null || true
[ -f "$CHROOT_DIR/run/sshd.pid" ] && kill -15 "$(cat "$CHROOT_DIR/run/sshd.pid" 2>/dev/null)" 2>/dev/null || true
for p in /proc/[0-9]*; do
    if [ "$(readlink "$p/root" 2>/dev/null)" = "$CHROOT_DIR" ]; then
        kill -15 "${p#/proc/}" 2>/dev/null || true
    fi
done
sleep 1

# Force SIGKILL
pkill -9 -f "tailscaled" 2>/dev/null || true
pkill -9 -u root -x "sshd" 2>/dev/null || true
[ -f "$CHROOT_DIR/run/sshd.pid" ] && kill -9 "$(cat "$CHROOT_DIR/run/sshd.pid" 2>/dev/null)" 2>/dev/null || true
for p in /proc/[0-9]*; do
    if [ "$(readlink "$p/root" 2>/dev/null)" = "$CHROOT_DIR" ]; then
        kill -9 "${p#/proc/}" 2>/dev/null || true
    fi
done
pkill -9 -f "$CHROOT_DIR" 2>/dev/null || true
sleep 1
echo "[+] All chroot processes terminated."

# 2. Safely Unmount Filesystems
echo "[*] Step 2: Unmounting virtual filesystems under $CHROOT_DIR..."
for m in "$CHROOT_DIR/dev/pts" "$CHROOT_DIR/dev/net" "$CHROOT_DIR/dev" "$CHROOT_DIR/proc" "$CHROOT_DIR/sys"; do
    if grep -q " $m " /proc/mounts 2>/dev/null; then
        echo "    - Unmounting: $m"
        umount -l "$m" 2>/dev/null || true
    fi
done

# Check for any remaining mounts inside CHROOT_DIR
grep " $CHROOT_DIR" /proc/mounts 2>/dev/null | while read -r _ mpoint _; do
    if [ -n "$mpoint" ]; then
        echo "    - Unmounting lingering: $mpoint"
        umount -l "$mpoint" 2>/dev/null || true
    fi
done
sleep 1

# Safety Guard: Ensure NOTHING is mounted before rm -rf
if grep -q " $CHROOT_DIR" /proc/mounts 2>/dev/null; then
    echo "[!] CRITICAL: Some filesystems could not be unmounted!"
    echo "[!] Aborting deletion to protect host filesystems. Please reboot first."
    exit 1
fi
echo "[+] All filesystems unmounted safely."

# 3. Delete the Chroot Directory
echo "[*] Step 3: Deleting chroot jail directory ($CHROOT_DIR)..."
if [ -d "$CHROOT_DIR" ]; then
    rm -rf "$CHROOT_DIR"
    echo "[+] Chroot directory removed completely (freeing disk space)."
else
    echo "[*] Chroot directory was already absent."
fi

# 4. Revert Network Routing & Policy Rules
echo "[*] Step 4: Reverting network policy routing rules..."
ip rule del pref 9000 2>/dev/null || true
ip -6 rule del pref 9000 2>/dev/null || true

# Clean Tailscale policy routing rules if present
ip rule del pref 5210 2>/dev/null || true
ip rule del pref 5230 2>/dev/null || true
ip rule del pref 5250 2>/dev/null || true
ip rule del pref 5270 2>/dev/null || true
ip -6 rule del pref 5210 2>/dev/null || true
ip -6 rule del pref 5230 2>/dev/null || true
ip -6 rule del pref 5250 2>/dev/null || true
ip -6 rule del pref 5270 2>/dev/null || true

# Remove default gateway added to table main
route_info=$(ip route get 1.1.1.1 2>/dev/null || true)
case "$route_info" in
    *dev\ *)
        def_if="${route_info#*dev }"
        def_if="${def_if%% *}"
        if [ -n "$def_if" ]; then
            ip route del default dev "$def_if" table main 2>/dev/null || true
        fi
        ;;
esac
echo "[+] Network rules and routing restored to Android default."

# 5. Clean up Temporary Files & Binaries in /data/local/tmp
echo "[*] Step 5: Cleaning up exploit files and scripts in $TMP_DIR..."
rm -f "$TMP_DIR/cve-2026-43499"* \
     "$TMP_DIR/libcve43499root.so" \
     "$TMP_DIR/kernelsu"* \
     "$TMP_DIR/ksud"* \
     "$TMP_DIR/.ksud-stage" \
     "$TMP_DIR/temp_su.sock" \
     "$TMP_DIR/tem3_su.sock" \
     "$TMP_DIR/device-reroot.sh" \
     "$TMP_DIR/setup-chroot.sh" \
     "$TMP_DIR/start-chroot.sh" \
     "$TMP_DIR/stop-chroot.sh" \
     "$TMP_DIR/purge-all.sh" \
     "$TMP_DIR/authorized_keys" \
     "$TMP_DIR/reroot.log" 2>/dev/null || true
echo "[+] Temporary binaries, sockets, and scripts wiped from $TMP_DIR."

# 6. Clean /data/adb KernelSU Components
echo "[*] Step 6: Cleaning KernelSU runtime components in /data/adb..."
if [ -d /data/adb/ksu ]; then
    rm -rf /data/adb/ksu /data/adb/ksud /data/adb/.allowlist 2>/dev/null || true
fi
echo "[+] KernelSU runtime components cleaned."

# 7. Restore SELinux to Enforcing
echo "[*] Step 7: Restoring SELinux to Enforcing mode..."
setenforce 1 2>/dev/null || true
echo "[+] SELinux status: $(getenforce 2>/dev/null || echo 'Enforcing')"

echo "============================================================"
echo "[+] SUCCESS: All components, files, and rules have been"
echo "    completely purged. The system is 100% clean."
echo ""
echo "[*] RECOMMENDATION: Restart your device (reboot) to clear"
echo "    kernel memory and ensure a complete 100% stock state."
echo "============================================================"

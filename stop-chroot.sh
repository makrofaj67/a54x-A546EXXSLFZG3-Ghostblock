#!/system/bin/sh
# ==============================================================================
# Alpine Linux Chroot - Stop & Teardown Script (Android / Termux)
# ==============================================================================
# This script terminates processes inside the chroot and safely unmounts mounts.
# ==============================================================================

CHROOT_DIR="/data/local/chroot"

if [ "$(id -u)" -ne 0 ]; then
    echo "[!] This script must be run as root (su)!"
    exit 1
fi

echo "[*] Stopping chroot processes and Tailscaled..."
pkill -9 -f "tailscaled" 2>/dev/null || true
pkill -9 -f "$CHROOT_DIR" 2>/dev/null || true

echo "[*] Safely unmounting virtual filesystems (lazy umount)..."
umount -l "$CHROOT_DIR/dev/pts" 2>/dev/null || true
umount -l "$CHROOT_DIR/dev" 2>/dev/null || true
umount -l "$CHROOT_DIR/proc" 2>/dev/null || true
umount -l "$CHROOT_DIR/sys" 2>/dev/null || true

# Check if any lingering mounts remain
if grep -q "$CHROOT_DIR" /proc/mounts 2>/dev/null; then
    echo "[!] Some mount points remain active, force unmounting..."
    umount -f -R "$CHROOT_DIR" 2>/dev/null || true
fi

echo "[+] Chroot environment and services stopped successfully."

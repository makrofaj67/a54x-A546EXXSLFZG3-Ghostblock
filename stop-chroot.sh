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

echo "[*] Terminating processes running inside chroot..."
# Terminate any process jailed inside CHROOT_DIR (matches via /proc/*/root)
for p in /proc/[0-9]*; do
    if [ "$(readlink "$p/root" 2>/dev/null)" = "$CHROOT_DIR" ]; then
        pid="${p#/proc/}"
        kill -15 "$pid" 2>/dev/null || true
    fi
done

# Also send SIGTERM to tailscaled and sshd
pkill -15 -f "tailscaled" 2>/dev/null || true
pkill -15 -f "sshd" 2>/dev/null || true
sleep 1

# Force kill any lingering processes
for p in /proc/[0-9]*; do
    if [ "$(readlink "$p/root" 2>/dev/null)" = "$CHROOT_DIR" ]; then
        pid="${p#/proc/}"
        kill -9 "$pid" 2>/dev/null || true
    fi
done
pkill -9 -f "tailscaled" 2>/dev/null || true
pkill -9 -f "sshd" 2>/dev/null || true
pkill -9 -f "$CHROOT_DIR" 2>/dev/null || true

# Brief pause to allow kernel to reclaim file descriptors
sleep 1

echo "[*] Safely unmounting virtual filesystems (lazy umount)..."
# Unmount standard submounts first
for m in "$CHROOT_DIR/dev/pts" "$CHROOT_DIR/dev/net" "$CHROOT_DIR/dev" "$CHROOT_DIR/proc" "$CHROOT_DIR/sys"; do
    if grep -q " $m " /proc/mounts 2>/dev/null; then
        umount -l "$m" 2>/dev/null || true
    fi
done

# Unmount any remaining submounts under CHROOT_DIR in /proc/mounts
grep " $CHROOT_DIR" /proc/mounts 2>/dev/null | while read -r _ mpoint _; do
    [ -n "$mpoint" ] && umount -l "$mpoint" 2>/dev/null || true
done

sleep 1

# Final check
if grep -q " $CHROOT_DIR" /proc/mounts 2>/dev/null; then
    echo "[!] Some mount points remain active, retrying lazy unmount..."
    grep " $CHROOT_DIR" /proc/mounts 2>/dev/null | while read -r _ mpoint _; do
        [ -n "$mpoint" ] && umount -f -l "$mpoint" 2>/dev/null || true
    done
fi

echo "[+] Chroot environment and services stopped successfully."

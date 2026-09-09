#!/system/bin/sh
# ==============================================================================
# Alpine Linux Chroot - Startup Script (Android / Termux)
# ==============================================================================
# Usage:
#   ./start-chroot.sh          -> Mounts filesystems, starts tailscaled, drops into shell
#   ./start-chroot.sh daemon   -> Mounts filesystems and runs tailscaled in background
#   ./start-chroot.sh up       -> Runs 'tailscale up' to generate the auth/login URL
# ==============================================================================

CHROOT_DIR="/data/local/chroot"

# 1. Root Check
if [ "$(id -u)" -ne 0 ]; then
    echo "[!] This script must be run as root (su)!"
    exit 1
fi

if [ ! -d "$CHROOT_DIR/bin" ]; then
    echo "[!] Chroot directory not found ($CHROOT_DIR)."
    echo "[!] Please run setup-chroot.sh first."
    exit 1
fi

echo "[*] Setting SELinux to Permissive mode..."
setenforce 0 2>/dev/null || true

# 2. Check /dev/net/tun Device
if [ ! -c /dev/net/tun ]; then
    mkdir -p /dev/net
    mknod /dev/net/tun c 10 200 2>/dev/null || true
    chmod 666 /dev/net/tun 2>/dev/null || true
fi

# 3. Mount Checks (Prevents layered/duplicate mount errors)
mount_if_needed() {
    target="$1"
    shift
    if ! grep -q " $target " /proc/mounts 2>/dev/null; then
        echo "[*] Mounting: $target"
        mount "$@" "$target"
    fi
}

mount_if_needed "$CHROOT_DIR/proc" -t proc proc
mount_if_needed "$CHROOT_DIR/sys" -t sysfs sys
mount_if_needed "$CHROOT_DIR/dev" --bind /dev
mkdir -p "$CHROOT_DIR/dev/pts"
mount_if_needed "$CHROOT_DIR/dev/pts" -t devpts devpts

# 4. Ensure Valid DNS
cat << 'EOF' > "$CHROOT_DIR/etc/resolv.conf"
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

# 5. Start tailscaled (if not already running)
mkdir -p "$CHROOT_DIR/var/lib/tailscale" "$CHROOT_DIR/run/tailscale" "$CHROOT_DIR/var/run/tailscale"
if ! pgrep -f "tailscaled" > /dev/null 2>&1; then
    echo "[*] Starting tailscaled daemon..."
    chroot "$CHROOT_DIR" /usr/bin/env \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock > "$CHROOT_DIR/var/log/tailscaled.log" 2>&1 &
    sleep 1
else
    echo "[*] tailscaled is already running."
fi

# 6. Dispatch Action Based on Argument
case "$1" in
    daemon)
        echo "[+] Chroot and Tailscale are active in background!"
        ;;
    up)
        echo "[*] Triggering Tailscale connection..."
        chroot "$CHROOT_DIR" /usr/bin/env \
            PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
            tailscale --socket=/run/tailscale/tailscaled.sock up
        ;;
    *)
        echo "[+] Entering chroot environment (/bin/bash)..."
        export TERM=xterm-256color
        chroot "$CHROOT_DIR" /bin/bash -l || chroot "$CHROOT_DIR" /bin/sh -l
        ;;
esac

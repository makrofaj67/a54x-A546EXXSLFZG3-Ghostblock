#!/system/bin/sh
# ==============================================================================
# Alpine Linux Chroot - Startup Script (Android / Termux)
# ==============================================================================
# Usage:
#   ./start-chroot.sh             -> Mounts filesystems, starts tailscaled, drops into shell
#   ./start-chroot.sh daemon      -> Mounts filesystems and runs tailscaled in background
#   ./start-chroot.sh up [flags]  -> Runs 'tailscale up' (passes extra flags like --ssh)
#   ./start-chroot.sh exec <cmd>  -> Executes a command inside the chroot environment
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
    if [ -c /dev/tun ]; then
        ln -sf /dev/tun /dev/net/tun 2>/dev/null || true
    else
        mknod /dev/net/tun c 10 200 2>/dev/null || true
    fi
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

# Prevent mounts from leaking back to Android host namespaces
mount --make-rslave "$CHROOT_DIR" 2>/dev/null || true

# 4. Ensure Valid DNS and Android Routing
cat << 'EOF' > "$CHROOT_DIR/etc/resolv.conf"
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

# Android multi-table routing fix: route chroot traffic through active interface
route_info=$(ip route get 1.1.1.1 2>/dev/null || true)
case "$route_info" in
    *dev\ *)
        def_if="${route_info#*dev }"
        def_if="${def_if%% *}"
        if [ -n "$def_if" ]; then
            gw=$(ip route show table "$def_if" 2>/dev/null | grep default | awk '{print $3}')
            if [ -n "$gw" ]; then
                ip route replace default via "$gw" dev "$def_if" 2>/dev/null || true
            else
                ip route replace default dev "$def_if" 2>/dev/null || true
            fi
            ip rule del pref 9000 2>/dev/null || true
            ip rule add from all lookup "$def_if" pref 9000 2>/dev/null || true
        fi
        ;;
esac

# 5. Start tailscaled (restart if running 'up' to ensure fresh network routes)
mkdir -p "$CHROOT_DIR/var/lib/tailscale" \
         "$CHROOT_DIR/run/tailscale" \
         "$CHROOT_DIR/var/log"

case "$1" in
    up|restart)
        pkill -9 -f "tailscaled" 2>/dev/null || true
        sleep 1
        ;;
esac

is_tailscaled_running() {
    pidof tailscaled >/dev/null 2>&1 || pgrep -x tailscaled >/dev/null 2>&1
}

if ! is_tailscaled_running; then
    echo "[*] Starting tailscaled daemon..."
    rm -f "$CHROOT_DIR/run/tailscale/tailscaled.sock" 2>/dev/null || true
    chroot "$CHROOT_DIR" /usr/bin/env \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        HOME=/root \
        TS_NETFILTER_MODE=off \
        tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock >> "$CHROOT_DIR/var/log/tailscaled.log" 2>&1 &
    sleep 2
else
    echo "[*] tailscaled is already running."
fi

# 6. Dispatch Action Based on Argument
case "$1" in
    daemon)
        echo "[+] Chroot and Tailscale are active in background!"
        ;;
    status)
        echo "[*] Tailscale Status:"
        chroot "$CHROOT_DIR" /usr/bin/env \
            PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
            HOME=/root \
            tailscale --socket=/run/tailscale/tailscaled.sock status
        ;;
    up)
        shift
        echo "[*] Triggering Tailscale connection..."
        chroot "$CHROOT_DIR" /usr/bin/env \
            PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
            HOME=/root \
            tailscale --socket=/run/tailscale/tailscaled.sock up "$@"
        ;;
    exec)
        shift
        export TERM=xterm-256color
        export HOME=/root
        chroot "$CHROOT_DIR" /usr/bin/env \
            PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
            TERM=xterm-256color \
            HOME=/root \
            "$@"
        ;;
    *)
        echo "[+] Entering chroot environment (/bin/bash)..."
        export TERM=xterm-256color
        export HOME=/root
        chroot "$CHROOT_DIR" /usr/bin/env \
            PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
            TERM=xterm-256color \
            HOME=/root \
            /bin/bash -l || chroot "$CHROOT_DIR" /bin/sh -l
        ;;
esac

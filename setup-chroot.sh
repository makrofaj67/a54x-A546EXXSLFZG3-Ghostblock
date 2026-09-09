#!/system/bin/sh
# ==============================================================================
# Alpine Linux Chroot - Setup Script (Android / Termux)
# ==============================================================================
# This script installs a minimal Alpine Linux rootfs under /data/local/chroot,
# configures repositories, DNS, Android networking groups, and installs
# Tailscale + OpenSSH.
# ==============================================================================

set -e

CHROOT_DIR="/data/local/chroot"
TMP_DIR="/data/local/tmp"
ALPINE_VER="v3.20"
ALPINE_SUBVER="3.20.3"
ALPINE_TAR="alpine-minirootfs-${ALPINE_SUBVER}-aarch64.tar.gz"
ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/${ALPINE_VER}/releases/aarch64/${ALPINE_TAR}"

# 1. Root Check
if [ "$(id -u)" -ne 0 ]; then
    echo "[!] This script must be run as root (su)!"
    exit 1
fi

echo "[*] Setting SELinux to Permissive mode..."
setenforce 0 2>/dev/null || true

# 2. Clean up previous installation if present
if [ -d "$CHROOT_DIR" ]; then
    echo "[*] Existing $CHROOT_DIR directory found. Safely cleaning up..."
    for m in "$CHROOT_DIR/dev/pts" "$CHROOT_DIR/dev/net" "$CHROOT_DIR/dev" "$CHROOT_DIR/proc" "$CHROOT_DIR/sys"; do
        umount -l "$m" 2>/dev/null || true
    done
    grep " $CHROOT_DIR" /proc/mounts 2>/dev/null | while read -r _ mpoint _; do
        [ -n "$mpoint" ] && umount -l "$mpoint" 2>/dev/null || true
    done
    sleep 1
    rm -rf "$CHROOT_DIR" 2>/dev/null || true
fi

mkdir -p "$CHROOT_DIR"
mkdir -p "$TMP_DIR"
cd "$TMP_DIR"

# 3. Detect Downloader (curl or wget on Android / Termux)
if command -v curl >/dev/null 2>&1; then
    FETCH="curl -L -o"
elif [ -x /data/data/com.termux/files/usr/bin/curl ]; then
    FETCH="/data/data/com.termux/files/usr/bin/curl -L -o"
elif command -v wget >/dev/null 2>&1; then
    FETCH="wget -O"
elif [ -x /data/data/com.termux/files/usr/bin/wget ]; then
    FETCH="/data/data/com.termux/files/usr/bin/wget -O"
else
    echo "[!] Neither curl nor wget found! Please install curl in Termux (pkg install curl)."
    exit 1
fi

# 4. Check for Corrupted / Incomplete Archive
if [ -f "$ALPINE_TAR" ]; then
    if ! tar -tzf "$ALPINE_TAR" >/dev/null 2>&1; then
        echo "[!] Corrupted or truncated archive detected. Removing..."
        rm -f "$ALPINE_TAR"
    fi
fi

# 5. Download Alpine RootFS
if [ ! -f "$ALPINE_TAR" ]; then
    echo "[*] Downloading Alpine Linux (${ALPINE_TAR})..."
    $FETCH "$ALPINE_TAR" "$ALPINE_URL"
else
    echo "[*] Verified valid archive exists: $TMP_DIR/$ALPINE_TAR"
fi

# 6. Extract Archive
echo "[*] Extracting rootfs to $CHROOT_DIR..."
tar -xpf "$ALPINE_TAR" -C "$CHROOT_DIR"

# 7. Configure DNS and Networking
echo "[*] Configuring DNS..."
mkdir -p "$CHROOT_DIR/etc"
cat << 'EOF' > "$CHROOT_DIR/etc/resolv.conf"
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 1.0.0.1
EOF

# Android Paranoid Network (AID_INET) group mapping
# Android kernels only permit raw/inet socket creation to specific GIDs
echo "[*] Setting up Android Paranoid Network groups..."
grep -q "aid_inet" "$CHROOT_DIR/etc/group" 2>/dev/null || cat << 'EOF' >> "$CHROOT_DIR/etc/group"
aid_inet:x:3003:root
aid_net_raw:x:3004:root
aid_net_admin:x:3005:root
EOF

# 8. Check and create /dev/net/tun if missing
if [ ! -c /dev/net/tun ]; then
    echo "[*] Setting up /dev/net/tun..."
    mkdir -p /dev/net
    if [ -c /dev/tun ]; then
        ln -sf /dev/tun /dev/net/tun 2>/dev/null || true
    else
        mknod /dev/net/tun c 10 200 2>/dev/null || true
    fi
    chmod 666 /dev/net/tun 2>/dev/null || true
fi

# 9. Mount Virtual Filesystems (with duplication check)
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

# 10. Update Repositories and Install Packages
echo "[*] Updating Alpine repositories and installing packages..."
cat << EOF > "$CHROOT_DIR/etc/apk/repositories"
https://dl-cdn.alpinelinux.org/alpine/${ALPINE_VER}/main
https://dl-cdn.alpinelinux.org/alpine/${ALPINE_VER}/community
EOF

# Note: In Alpine, the 'iptables' package includes both iptables and ip6tables.
# We set standard Linux PATH and HOME so apk post-install scripts execute correctly.
chroot "$CHROOT_DIR" /usr/bin/env -i \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    TERM=xterm-256color \
    HOME=/root \
    /bin/sh -c "apk update && apk add --no-cache tailscale openssh iptables ca-certificates curl bash neovim tmux"

# Runtime directories for Tailscale and logs
mkdir -p "$CHROOT_DIR/var/lib/tailscale" \
         "$CHROOT_DIR/run/tailscale" \
         "$CHROOT_DIR/var/log"

echo "========================================================"
echo "[+] SETUP COMPLETED SUCCESSFULLY!"
echo "To start the chroot: ./start-chroot.sh"
echo "========================================================"

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
    echo "[*] Existing $CHROOT_DIR directory found. Cleaning up..."
    umount -l "$CHROOT_DIR/dev/pts" 2>/dev/null || true
    umount -l "$CHROOT_DIR/dev" 2>/dev/null || true
    umount -l "$CHROOT_DIR/proc" 2>/dev/null || true
    umount -l "$CHROOT_DIR/sys" 2>/dev/null || true
    rm -rf "$CHROOT_DIR"
fi

mkdir -p "$CHROOT_DIR"
mkdir -p "$TMP_DIR"
cd "$TMP_DIR"

# 3. Download Alpine RootFS
if [ ! -f "$ALPINE_TAR" ]; then
    echo "[*] Downloading Alpine Linux (${ALPINE_TAR})..."
    curl -L -o "$ALPINE_TAR" "$ALPINE_URL"
else
    echo "[*] Archive already downloaded: $TMP_DIR/$ALPINE_TAR"
fi

# 4. Extract Archive
echo "[*] Extracting rootfs to $CHROOT_DIR..."
tar -xpf "$ALPINE_TAR" -C "$CHROOT_DIR"

# 5. Configure DNS and Networking
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

# 6. Check and create /dev/net/tun if missing
if [ ! -c /dev/net/tun ]; then
    echo "[*] Creating /dev/net/tun character device..."
    mkdir -p /dev/net
    mknod /dev/net/tun c 10 200 2>/dev/null || true
    chmod 666 /dev/net/tun 2>/dev/null || true
fi

# 7. Mount Virtual Filesystems for Package Setup
echo "[*] Mounting virtual filesystems..."
mount -t proc proc "$CHROOT_DIR/proc"
mount -t sysfs sys "$CHROOT_DIR/sys"
mount --bind /dev "$CHROOT_DIR/dev"
mkdir -p "$CHROOT_DIR/dev/pts"
mount -t devpts devpts "$CHROOT_DIR/dev/pts"

# 8. Update Repositories and Install Packages
echo "[*] Updating Alpine repositories and installing packages..."
cat << EOF > "$CHROOT_DIR/etc/apk/repositories"
https://dl-cdn.alpinelinux.org/alpine/${ALPINE_VER}/main
https://dl-cdn.alpinelinux.org/alpine/${ALPINE_VER}/community
EOF

chroot "$CHROOT_DIR" /bin/sh -c "apk update && apk add --no-cache tailscale openssh iptables ip6tables ca-certificates curl bash neovim tmux"

# Tailscale runtime directories
mkdir -p "$CHROOT_DIR/var/lib/tailscale" "$CHROOT_DIR/run/tailscale"

echo "========================================================"
echo "[+] SETUP COMPLETED SUCCESSFULLY!"
echo "To start the chroot: ./start-chroot.sh"
echo "========================================================"

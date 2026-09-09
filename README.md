

S

# Android Alpine Chroot & Tailscale Management

This toolkit provides an automated environment to bootstrap a minimal Alpine Linux chroot jail and run `tailscaled` on an Android device (Samsung Galaxy A54 / Exynos / ARM64) with temporary root (e.g., via GhostLock / CVE-2026-43499 + KernelSU late-load).

---

### Automation Scripts

| Script                                                                                    | Execution Target | Purpose                                                                                                                                                                                                                         |
| :---------------------------------------------------------------------------------------- | :--------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **[setup-chroot.sh](file:///home/rakman/Projects/chrootundercve/setup-chroot.sh)**   | Android (Root)   | One-time bootstrap. Downloads Alpine ARM64 rootfs, sets up`/etc/resolv.conf`, configures Android `AID_INET` (3003) paranoid network GIDs, creates `/dev/net/tun`, and installs `tailscale`, `openssh`, and utilities. |
| **[start-chroot.sh](file:///home/rakman/Projects/chrootundercve/start-chroot.sh)**   | Android (Root)   | Mounts filesystems (safe`/proc/mounts` checks), launches `tailscaled` daemon in background, and drops into a shell. Supports `daemon`, `up [flags]`, and `exec <cmd...>`.                                             |
| **[stop-chroot.sh](file:///home/rakman/Projects/chrootundercve/stop-chroot.sh)**     | Android (Root)   | Clean teardown. Terminates chroot processes and safely unmounts filesystems using lazy unmount (`umount -l`).                                                                                                                 |
| **[device-reroot.sh](file:///home/rakman/Projects/chrootundercve/device-reroot.sh)** | Android (Termux) | On-device root automation. Sequentially tries exploit variants (`-app.so`, `cve-...so`, and `libcve43499root.so`), stages `ksud`, triggers `--late-load`, and starts the chroot.                                      |
| **[adb-reroot.sh](file:///home/rakman/Projects/chrootundercve/adb-reroot.sh)**       | PC (ADB)         | One-click host launcher. Automates the full root elevation and chroot startup sequence over ADB.                                                                                                                                |
| **[sync-to-phone.sh](file:///home/rakman/Projects/chrootundercve/sync-to-phone.sh)** | PC (ADB)         | Pushes all cleaned binaries, helpers, and management scripts from`tmp/` to `/data/local/tmp/` on the device and sets permissions.                                                                                           |

### Binary Components (`tmp/`)

* **`cve-2026-43499-root`**: Primary root helper executable.
* **`libcve43499root.so`**: Fallback/alternate root helper executable.
* **`cve-2026-43499-app.so`**: Exploit shared library tailored for Android app contexts (Termux `u0_a...`).
* **`cve-2026-43499.so`**: Exploit shared library tailored for ADB shell contexts (`shell` UID 2000).
* **`ksud-next-a54x-A546EXXSKFZF4-kdp`**: KernelSU daemon binary for Samsung Galaxy A54.
* **`ksud-s25u-kdp`**: Identical KernelSU binary matching the path expected by the root helper.

*(Note: All socket references across binaries have been aligned to `/data/local/tmp/temp_su.sock`).*

---

## Usage Guide

### 1. Initial Synchronization (From PC via ADB)

Push the cleaned binaries and scripts to your phone:

```bash
./sync-to-phone.sh
```

### 2. Bootstrap the Chroot (One-Time Setup)

From Termux on your phone after acquiring root, or via ADB:

```bash
su
sh /data/local/tmp/setup-chroot.sh
```

### 3. Authenticate Tailscale

Generate your node authentication link and authenticate in a browser:

```bash
su
sh /data/local/tmp/start-chroot.sh up
```

### 4. Daily Startup (After Device Reboot)

#### Option A: From PC via ADB

Connect your phone (cable or Wi-Fi debugging) and run:

```bash
./adb-reroot.sh
```

#### Option B: Standalone on Phone (Termux)

Run the automated launcher:

```bash
sh /data/local/tmp/device-reroot.sh
```

*(Tip: You can copy `device-reroot.sh` to `~/.termux/boot/` with the **Termux:Boot** addon to trigger root and chroot launch automatically on system boot).*

### 5. Running One-off Commands

You can run any Linux command inside the chroot directly:

```bash
su
sh /data/local/tmp/start-chroot.sh exec htop
```

### 6. Stopping the Chroot

To terminate background daemons and cleanly release all mounts:

```bash
su
sh /data/local/tmp/stop-chroot.sh
```

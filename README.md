# ArchPKB-Protected-Kernel-Backup
PKB (Protected Kernel Backup) is a tiny, robust helper for Arch Linux users on systemd‑boot that always keeps the latest kernel plus the previous known‑good kernel bootable on the ESP — with version‑aware cleanup and zero GRUB/mkinitcpio dependencies.

PKB — Arch Backup Kernel Script (systemd‑boot)

PKB (Protected Kernel Backup) is a tiny, robust helper for Arch Linux users on systemd‑boot that always keeps the latest kernel plus the previous known‑good kernel bootable on the ESP — with version‑aware cleanup and zero GRUB/mkinitcpio dependencies.

Search‑friendly keywords: Arch Linux backup kernel, systemd‑boot fallback, kernel‑install dracut, keep previous kernel, ESP cleanup, protected kernel entry.

Why PKB?

Arch is minimal by design and won’t automatically keep the prior kernel. If a brand‑new kernel fails to boot, you either need an LTS kernel or a manual fallback. PKB solves this by:

Backing up linux + initrd for the newest kernel into /efi/backup-kernels/<ver>_<timestamp>/.

Generating a clear protected boot entry (e.g. protected-<ver>_<stamp>.conf).

Always keeping one backup per version, retaining only the newest two different versions overall.

Never deleting the currently running kernel’s backup if it exists.

Skipping initrd-fallback by default (saves ~150MB per backup). Optional via COPY_FALLBACK=1.

Performing pre‑clean before copy, space checks, and a post‑clean.

Works with: systemd‑boot, kernel‑install, dracut. ESP expected at /efi (auto‑detected from bootctl if not set).

Features

✅ Version‑aware cleanup: keeps the newest two versions (configurable) and removes older duplicates/timestamps.

✅ Never removes the backup for your currently booted kernel.

✅ Pre‑clean + free‑space check before copying; safe exit if ESP is too small.

✅ Minimal footprint: by default backs up only linux + initrd.

✅ Friendly boot entries with a consistent protected‑latest.conf pointer.

✅ No daemons or timers — triggered by a pacman hook after kernel updates.

Installation (Quick Start)
# Clone
git clone https://github.com/yourname/pkb.git
cd pkb


# Install script places files in standard locations
sudo ./scripts/install.sh

This installs:

bin/protected-kernel-backup.sh → /usr/local/bin/protected-kernel-backup.sh

hooks/kernel-backup.hook → /etc/pacman.d/hooks/kernel-backup.hook

The hook triggers PKB after Install/Upgrade/Remove of kernel images.

Note: PKB expects systemd‑boot + kernel‑install layout: /efi/<machine-id>/<kernel-ver>/ containing linux, initrd (and optionally initrd-fallback).

Configuration

Environment variables (set globally in the hook, or export before running):

ESP_DIR — path to your ESP mount. Default: auto from bootctl --print-boot-path, fallback /efi.

BACKUP_DIR — destination for backups on ESP. Default: $ESP_DIR/backup-kernels.

KEEP_VERSIONS — how many different kernel versions to keep (newest first). Default: 2.

COPY_FALLBACK — copy initrd-fallback too (0/1). Default: 0.

PKB_DRY_RUN — don’t modify anything; just print actions (0/1). Default: 0.

PKB_VERBOSE — more logging (0/1). Default: 1.

Example: set COPY_FALLBACK=1 inside the hook’s Exec line if you really want fallback images.

Usage

Normally you don’t run PKB manually — the pacman hook does that after kernel changes. To run on‑demand:

sudo protected-kernel-backup.sh

Common outputs:

🧹 Pre-clean … — pruning old backups/entries before copying.

📦 Backing up … — copying linux + initrd into a timestamped folder.

🧹 Post-clean … — final pruning to keep exactly KEEP_VERSIONS versions.

📄 … protected-latest.conf — pointer to the most recent protected entry.

Disaster Recovery (TL;DR)

If the newest kernel doesn’t boot, in the systemd‑boot menu pick the entry named like:

🛡 Protected Kernel <previous-version>

That boots your last known‑good kernel stored on the ESP. From there you can downgrade or wait for a fixed update.

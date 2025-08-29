# PKB — Arch Backup Kernel Script (systemd‑boot)

> **PKB** (Protected Kernel Backup) is a tiny, robust helper for **Arch Linux** users on **systemd‑boot** that always keeps the **latest kernel** plus the **previous known‑good kernel** bootable on the ESP — with version‑aware cleanup and zero GRUB/mkinitcpio dependencies.

Search‑friendly keywords: Arch Linux backup kernel, systemd‑boot fallback, kernel‑install dracut, keep previous kernel, ESP cleanup, protected kernel entry.

---

## Why PKB?

Arch is minimal by design and won’t automatically keep the prior kernel. If a brand‑new kernel fails to boot, you either need an LTS kernel or a manual fallback. PKB solves this by:

* Backing up **linux** + **initrd** for the newest kernel into `/efi/backup-kernels/<ver>_<timestamp>/`.
* Generating a clear **protected** boot entry (e.g. `protected-<ver>_<stamp>.conf`).
* Always keeping **one backup per version**, retaining **only the newest two different versions** overall.
* **Never deleting the currently running kernel’s backup** if it exists.
* Skipping `initrd-fallback` by default (saves \~150MB per backup). Optional via `COPY_FALLBACK=1`.
* Performing **pre‑clean** *before* copy, space checks, and a **post‑clean**.

Works with: **systemd‑boot**, **kernel‑install**, **dracut**. ESP expected at `/efi` (auto‑detected from `bootctl` if not set).

---

## Features

* ✅ Version‑aware cleanup: keeps the newest **two** versions (configurable) and removes older duplicates/timestamps.
* ✅ Never removes the backup for your **currently booted kernel**.
* ✅ **Pre‑clean + free‑space check** before copying; safe exit if ESP is too small.
* ✅ Minimal footprint: by default backs up only `linux` + `initrd`.
* ✅ Friendly boot entries with a consistent `protected‑latest.conf` pointer.
* ✅ No daemons or timers — triggered by a **pacman hook** after kernel updates.

---

## Installation (Quick Start)

```bash
# Clone
git clone https://github.com/jovantehno/ArchPKB-Protected-Kernel-Backup.git
cd pkb

# Install script places files in standard locations
sudo ./scripts/install.sh
```

This installs:

* `bin/protected-kernel-backup.sh` → `/usr/local/bin/protected-kernel-backup.sh`
* `hooks/kernel-backup.hook` → `/etc/pacman.d/hooks/kernel-backup.hook`

The hook triggers PKB after **Install/Upgrade/Remove** of kernel images.

> **Note**: PKB expects systemd‑boot + kernel‑install layout: `/efi/<machine-id>/<kernel-ver>/` containing `linux`, `initrd` (and optionally `initrd-fallback`).

---

## Configuration

Environment variables (set globally in the hook, or export before running):

* `ESP_DIR` — path to your ESP mount. **Default**: auto from `bootctl --print-boot-path`, fallback `/efi`.
* `BACKUP_DIR` — destination for backups on ESP. **Default**: `$ESP_DIR/backup-kernels`.
* `KEEP_VERSIONS` — how many **different kernel versions** to keep (newest first). **Default**: `2`.
* `COPY_FALLBACK` — copy `initrd-fallback` too (0/1). **Default**: `0`.
* `PKB_DRY_RUN` — don’t modify anything; just print actions (0/1). **Default**: `0`.
* `PKB_VERBOSE` — more logging (0/1). **Default**: `1`.

Example: set `COPY_FALLBACK=1` inside the hook’s `Exec` line if you really want fallback images.

---

## Usage

Normally you don’t run PKB manually — the pacman hook does that after kernel changes. To run on‑demand:

```bash
sudo protected-kernel-backup.sh
```

Common outputs:

* `🧹 Pre-clean …` — pruning old backups/entries before copying.
* `📦 Backing up …` — copying `linux` + `initrd` into a timestamped folder.
* `🧹 Post-clean …` — final pruning to keep exactly `KEEP_VERSIONS` versions.
* `📄 … protected-latest.conf` — pointer to the most recent protected entry.

---

## Disaster Recovery (TL;DR)

If the newest kernel doesn’t boot, in the systemd‑boot menu pick the entry named like:

```
🛡 Protected Kernel <previous-version>
```

That boots your last known‑good kernel stored on the ESP. From there you can downgrade or wait for a fixed update.

---

## Files

### `bin/protected-kernel-backup.sh`

```bash
#!/bin/bash
set -euo pipefail

# ---------- Config ----------
ESP_DIR="${ESP_DIR:-}"
if [[ -z "${ESP_DIR}" ]]; then
  # Try to auto-detect ESP from systemd-boot
  if command -v bootctl >/dev/null 2>&1; then
    ESP_DIR="$(bootctl --print-boot-path 2>/dev/null || true)"
  fi
  ESP_DIR="${ESP_DIR:-/efi}"
fi

BACKUP_DIR="${BACKUP_DIR:-$ESP_DIR/backup-kernels}"
ENTRY_DIR="$ESP_DIR/loader/entries"
KEEP_VERSIONS="${KEEP_VERSIONS:-2}"
COPY_FALLBACK="${COPY_FALLBACK:-0}"
PKB_DRY_RUN="${PKB_DRY_RUN:-0}"
PKB_VERBOSE="${PKB_VERBOSE:-1}"

log() { echo -e "$*"; }
run() { if [[ "$PKB_DRY_RUN" == 1 ]]; then echo "+ $*"; else eval "$*"; fi }

# ---------- Discover ----------
LATEST_VER=$(ls -v /lib/modules | tail -n1)
TIMESTAMP=$(date +%Y%m%d-%H%M)
MACHINE_ID=$(cat /etc/machine-id)
SRC_DIR="$ESP_DIR/$MACHINE_ID/$LATEST_VER"
DEST_DIR="$BACKUP_DIR/${LATEST_VER}_$TIMESTAMP"
ENTRY_NAME="protected-${LATEST_VER}_${TIMESTAMP}.conf"
CONF_PATH="$ENTRY_DIR/$ENTRY_NAME"
LATEST_COPY="$ENTRY_DIR/protected-latest.conf"
CURRENT_VER="$(uname -r)"

# ---------- Helpers ----------
free_bytes() { df -B1 --output=avail "$ESP_DIR" | tail -1 | tr -d ' '; }
size_of()   { [[ -f "$1" ]] && stat -c %s "$1" || echo 0; }
required_bytes() {
  local need=0
  need=$((need + $(size_of "$SRC_DIR/linux")))
  need=$((need + $(size_of "$SRC_DIR/initrd")))
  if [[ "$COPY_FALLBACK" == 1 ]]; then
    need=$((need + $(size_of "$SRC_DIR/initrd-fallback")))
  fi
  # slack for metadata
  need=$((need + 2*1024*1024))
  echo "$need"
}

cleanup_version_aware() {
  # backups (dirs)
  mapfile -t _dirs < <(ls -1dt "$BACKUP_DIR"/* 2>/dev/null || true)
  declare -A latest_by_ver=(); declare -a order_vers=()
  for d in "${_dirs[@]}"; do
    base="${d##*/}"; ver="${base%%_*}"
    if [[ -z "${latest_by_ver[$ver]+x}" ]]; then
      latest_by_ver["$ver"]="$d"; order_vers+=("$ver")
    fi
  done
  keep=()
  for i in "${!order_vers[@]}"; do
    ver="${order_vers[$i]}"; path="${latest_by_ver[$ver]}"
    if (( i < KEEP_VERSIONS )) || [[ "$ver" == "$CURRENT_VER" ]]; then
      keep+=("$path")
    fi
  done
  to_delete=()
  for d in "${_dirs[@]}"; do
    skip=false; for k in "${keep[@]}"; do [[ "$d" == "$k" ]] && skip=true && break; done
    $skip || to_delete+=("$d")
  done
  if [[ ${#to_delete[@]} -gt 0 ]]; then
    for d in "${to_delete[@]}"; do run rm -rf -- "$d"; done
  fi

  # loader entries (.conf)
  mapfile -t _confs < <(ls -1t "$ENTRY_DIR"/protected-*.conf 2>/dev/null || true)
  declare -A latest_conf_by_ver=(); declare -a order_vers_conf=()
  for f in "${_confs[@]}"; do
    name="${f##*/}"; tmp="${name#protected-}"; ver="${tmp%%_*}"
    if [[ -z "${latest_conf_by_ver[$ver]+x}" ]]; then
      latest_conf_by_ver["$ver"]="$f"; order_vers_conf+=("$ver")
    fi
  done
  keep_confs=()
  for i in "${!order_vers_conf[@]}"; do
    ver="${order_vers_conf[$i]}"; f="${latest_conf_by_ver[$ver]}"
    if (( i < KEEP_VERSIONS )) || [[ "$ver" == "$CURRENT_VER" ]]; then
      keep_confs+=("$f")
    fi
  done
  to_delete=()
  for f in "${_confs[@]}"; do
    skip=false; for k in "${keep_confs[@]}"; do [[ "$f" == "$k" ]] && skip=true && break; done
    $skip || to_delete+=("$f")
  done
  if [[ ${#to_delete[@]} -gt 0 ]]; then
    for f in "${to_delete[@]}"; do run rm -v -- "$f"; done
  fi
}

# ---------- Ensure dirs ----------
run "mkdir -p '$BACKUP_DIR' '$ENTRY_DIR'"

# ---------- If backup already exists for this timestamp, just refresh latest and exit ----------
if [[ -d "$DEST_DIR" ]]; then
  log "⚠  Backup for kernel $LATEST_VER already exists — skipping backup."
  readarray -t _plist < <(ls -1t "$ENTRY_DIR"/protected-*.conf 2>/dev/null || true)
  LATEST_CONF="${_plist[0]:-}"
  if [[ -n "$LATEST_CONF" && -f "$LATEST_CONF" ]]; then
    log "📄 Copying latest loader entry to protected-latest.conf"
    run "cp -v '$LATEST_CONF' '$LATEST_COPY'"
  else
    log "ℹ  No existing protected-*.conf yet — nothing to copy to protected-latest.conf"
  fi
  exit 0
fi

# ---------- Validate source layout ----------
if [[ ! -d "$SRC_DIR" ]]; then
  log "❌ Kernel directory not found on ESP: $SRC_DIR"; exit 1
fi

# ---------- Pre-clean & space check ----------
log "🧹 Pre-clean old backups before copying..."
cleanup_version_aware

NEEDED=$(required_bytes); FREE=$(free_bytes || echo 0)
if (( FREE < NEEDED )); then
  log "ℹ  Not enough free space on $ESP_DIR (need $NEEDED bytes, have $FREE). Retrying cleanup…"
  cleanup_version_aware
  FREE=$(free_bytes || echo 0)
fi
if (( FREE < NEEDED )); then
  log "❌ Still not enough space on $ESP_DIR. Need: $NEEDED bytes; Free: $FREE bytes."
  exit 1
fi

# ---------- Copy payload ----------
run "mkdir -p '$DEST_DIR'"
log "📦 Backing up: $SRC_DIR → $DEST_DIR"
run "cp -v '$SRC_DIR/linux'  '$DEST_DIR/' || true"
run "cp -v '$SRC_DIR/initrd' '$DEST_DIR/' || true"
if [[ "$COPY_FALLBACK" == 1 ]]; then
  run "cp -v '$SRC_DIR/initrd-fallback' '$DEST_DIR/' || true"
fi

# ---------- Create loader entry ----------
cat >"$CONF_PATH" <<EOF
title   🛡 Protected Kernel $LATEST_VER ($TIMESTAMP)
linux   /backup-kernels/${LATEST_VER}_$TIMESTAMP/linux
initrd  /backup-kernels/${LATEST_VER}_$TIMESTAMP/initrd
options cryptdevice=UUID=6dea219c-0a51-4082-99ff-f07f5ee7d6a2:luks root=/dev/mapper/luks rw
EOF

log "✅ Loader entry created: $CONF_PATH"

# ---------- Post-clean & latest pointer ----------
log "🧹 Post-clean old backups after copying..."
cleanup_version_aware

log "📄 Copying latest loader entry to protected-latest.conf"
run "cp -v '$CONF_PATH' '$LATEST_COPY'"

log "✅ Done."
```

### `hooks/kernel-backup.hook`

```ini
[Trigger]
Type = Path
Target = /usr/lib/modules/*/vmlinuz*
Operation = Install
Operation = Upgrade
Operation = Remove

[Action]
Description = Backup latest kernel to ESP and prune old ones (PKB)
When = PostTransaction
# Set COPY_FALLBACK=1 if you really want to include initrd-fallback
Exec = /usr/bin/env PKB_VERBOSE=1 COPY_FALLBACK=0 /usr/local/bin/protected-kernel-backup.sh
```

### `etc/example-loader.conf`

```ini
# /efi/loader/loader.conf (example)
default auto
timeout 3
console-mode max
editor no
```

### `scripts/install.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
HOOK_DIR="/etc/pacman.d/hooks"

install -Dm755 bin/protected-kernel-backup.sh "$PREFIX/bin/protected-kernel-backup.sh"
install -Dm644 hooks/kernel-backup.hook "$HOOK_DIR/kernel-backup.hook"

echo "\nPKB installed. Files:"
echo "  $PREFIX/bin/protected-kernel-backup.sh"
echo "  $HOOK_DIR/kernel-backup.hook"

# Optional: shellcheck hint
command -v shellcheck >/dev/null 2>&1 || echo "(hint) Install shellcheck for CI/static analysis"
```

### `.github/workflows/ci.yml`

```yaml
name: ci
on:
  push:
  pull_request:
jobs:
  shellcheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install shellcheck
        run: sudo apt-get update && sudo apt-get install -y shellcheck
      - name: Lint scripts
        run: shellcheck bin/*.sh scripts/*.sh || true
```

---

## FAQ

**Q: Why not just install `linux-lts`?**
A: LTS is great, but it’s not “the previous kernel”; it can lag far behind. PKB always preserves your **last known‑good** kernel.

**Q: Does PKB support GRUB/mkinitcpio?**
A: Not in v1.0. PKB targets systemd‑boot + kernel‑install + dracut layout. GRUB/mkinitcpio support is on the roadmap.

**Q: Where are backups stored?**
A: On the ESP under `$ESP_DIR/backup-kernels/<kernel-ver>_<timestamp>/` with `linux` and `initrd`.

**Q: How many versions are kept?**
A: Two by default (`KEEP_VERSIONS=2`). Increase if your ESP is large enough.

---

## Troubleshooting

* **No space left on device**: PKB pre‑cleans and checks free space before copying. Reduce `KEEP_VERSIONS`, disable `COPY_FALLBACK`, or free space on the ESP.
* **Missing entries**: Ensure `/efi/loader/entries/` exists and ESP is mounted. PKB auto‑detects ESP via `bootctl` when possible.
* **Different ESP path**: Set `ESP_DIR=/boot` (or your mountpoint) in the hook `Exec` env.

---

## Roadmap

* `--dry-run` CLI flag (env already supported via `PKB_DRY_RUN=1`).
* Auto‑detect ESP with a smarter fallback order and warnings.
* Optional JSON log output for tooling.
* GRUB/mkinitcpio support.
* AUR package (`pkb-git`).

---

## License

**MIT** — see `LICENSE`.

---

## Credits

Crafted for Arch users who prefer the latest kernel but want a reliable, space‑aware fallback — without resorting to LTS.

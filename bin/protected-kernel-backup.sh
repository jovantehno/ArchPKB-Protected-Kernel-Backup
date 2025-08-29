#!/bin/bash
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
log "⚠ Backup for kernel $LATEST_VER already exists — skipping backup."
readarray -t _plist < <(ls -1t "$ENTRY_DIR"/protected-*.conf 2>/dev/null || true)
LATEST_CONF="${_plist[0]:-}"
if [[ -n "$LATEST_CONF" && -f "$LATEST_CONF" ]]; then
log "📄 Copying latest loader entry to protected-latest.conf"
run "cp -v '$LATEST_CONF' '$LATEST_COPY'"
else
log "ℹ No existing protected-*.conf yet — nothing to copy to protected-latest.conf"
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
log "ℹ Not enough free space on $ESP_DIR (need $NEEDED bytes, have $FREE). Retrying cleanup…"
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
run "cp -v '$SRC_DIR/linux' '$DEST_DIR/' || true"
run "cp -v '$SRC_DIR/initrd' '$DEST_DIR/' || true"
if [[ "$COPY_FALLBACK" == 1 ]]; then
run "cp -v '$SRC_DIR/initrd-fallback' '$DEST_DIR/' || true"
fi


# ---------- Create loader entry ----------
cat >"$CONF_PATH" <<EOF
title 🛡 Protected Kernel $LATEST_VER ($TIMESTAMP)
linux /backup-kernels/${LATEST_VER}_$TIMESTAMP/linux
initrd /backup-kernels/${LATEST_VER}_$TIMESTAMP/initrd
options cryptdevice=UUID=6dea219c-0a51-4082-99ff-f07f5ee7d6a2:luks root=/dev/mapper/luks rw
EOF


log "✅ Loader entry created: $CONF_PATH"


# ---------- Post-clean & latest pointer ----------
log "🧹 Post-clean old backups after copying..."
cleanup_version_aware


log "📄 Copying latest loader entry to protected-latest.conf"
run "cp -v '$CONF_PATH' '$LATEST_COPY'"


log "✅ Done."

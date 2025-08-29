#!/usr/bin/env bash
set -euo pipefail


PREFIX="${PREFIX:-/usr/local}"
HOOK_DIR="/etc/pacman.d/hooks"


install -Dm755 bin/protected-kernel-backup.sh "$PREFIX/bin/protected-kernel-backup.sh"
install -Dm644 hooks/kernel-backup.hook "$HOOK_DIR/kernel-backup.hook"


echo "\nPKB installed. Files:"
echo " $PREFIX/bin/protected-kernel-backup.sh"
echo " $HOOK_DIR/kernel-backup.hook"


# Optional: shellcheck hint
command -v shellcheck >/dev/null 2>&1 || echo "(hint) Install shellcheck for CI/static analysis"

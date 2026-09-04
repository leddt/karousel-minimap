#!/usr/bin/env bash
# Upgrade the plasmoid and reload Plasma Shell without a full logout.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

"$ROOT/install.sh"

rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/plasmashell/qmlcache"

echo "Restarting plasma-plasmashell (apps stay open; panel/desktop redraw)…"
systemctl --user reset-failed plasma-plasmashell.service 2>/dev/null || true
if ! systemctl --user restart plasma-plasmashell.service; then
  systemctl --user reset-failed plasma-plasmashell.service 2>/dev/null || true
  systemctl --user start plasma-plasmashell.service
fi
systemctl --user is-active plasma-plasmashell.service
echo "Done."

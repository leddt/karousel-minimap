#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
PKG="$ROOT/package"
ID="org.leddt.karousel.minimap"
UNIT_SRC="$ROOT/karousel-layout-bus.service"
UNIT_DST="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/karousel-layout-bus.service"

chmod +x "$PKG/contents/code/layout_bus.py"

if kpackagetool6 --type=Plasma/Applet --list | grep -qx "$ID"; then
  kpackagetool6 --type=Plasma/Applet --upgrade="$PKG"
else
  kpackagetool6 --type=Plasma/Applet --install="$PKG"
fi

mkdir -p "$(dirname "$UNIT_DST")"
# Point ExecStart at the installed plasmoid copy of the bus script.
INSTALLED_BUS="$HOME/.local/share/plasma/plasmoids/$ID/contents/code/layout_bus.py"
sed "s|ExecStart=.*|ExecStart=/usr/bin/python3 $INSTALLED_BUS|" "$UNIT_SRC" > "$UNIT_DST"

systemctl --user daemon-reload
systemctl --user enable --now karousel-layout-bus.service || true

# If an old ad-hoc bus is lingering from the previous plasmoid design, leave it;
# the unit uses Type=dbus and will bind when the name is free.
if ! qdbus6 org.kde.karousel >/dev/null 2>&1; then
  systemctl --user restart karousel-layout-bus.service || \
    systemd-run --user --unit=karousel-layout-bus --collect python3 "$INSTALLED_BUS" || true
fi

echo "Installed $ID"
echo "Layout bus unit: karousel-layout-bus.service"
echo "Add via: right-click panel → Add Widgets → Karousel Mini-map"
echo "Or: plasmawindowed $ID"

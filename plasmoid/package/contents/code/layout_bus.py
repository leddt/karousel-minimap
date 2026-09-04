#!/usr/bin/env python3
"""Session-bus service for Karousel layout export.

Owns org.kde.karousel and stores the latest layout JSON. Karousel (KWin script)
pushes updates via DBusCall; any number of clients can call GetLayout or watch
LayoutChanged.

Usage:
  ./layout_bus.py              # foreground
  systemd-run --user --unit=karousel-layout-bus ./layout_bus.py
"""

from __future__ import annotations

import json
import sys

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

BUS_NAME = "org.kde.karousel"
OBJECT_PATH = "/Layout"
INTERFACE = "org.kde.karousel.Layout"


class LayoutService(dbus.service.Object):
    def __init__(self, bus: dbus.SessionBus) -> None:
        self.last_layout: str = ""
        self._bus_name = dbus.service.BusName(BUS_NAME, bus)
        super().__init__(bus, OBJECT_PATH)

    @dbus.service.method(INTERFACE, in_signature="s", out_signature="")
    def update(self, layout_json: str) -> None:
        self.last_layout = layout_json
        self.LayoutChanged(layout_json)

    @dbus.service.method(INTERFACE, in_signature="", out_signature="s")
    def GetLayout(self) -> str:
        return self.last_layout

    @dbus.service.signal(INTERFACE, signature="s")
    def LayoutChanged(self, layout_json: str) -> None:
        pass


def main() -> int:
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    if bus.name_has_owner(BUS_NAME):
        print(f"{BUS_NAME} already owned — exiting", file=sys.stderr)
        return 0
    service = LayoutService(bus)
    print(f"Listening on {BUS_NAME} {OBJECT_PATH}", file=sys.stderr, flush=True)
    loop = GLib.MainLoop()
    try:
        loop.run()
    except KeyboardInterrupt:
        print(file=sys.stderr)
    finally:
        del service
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

"""D-Bus layout bus: own org.kde.karousel and forward JSON to Qt."""

from __future__ import annotations

import json
import threading
from typing import Any, Callable

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

BUS_NAME = "org.kde.karousel"
OBJECT_PATH = "/Layout"
INTERFACE = "org.kde.karousel.Layout"

LayoutCallback = Callable[[dict[str, Any]], None]


class LayoutService(dbus.service.Object):
    def __init__(
        self,
        bus: dbus.SessionBus,
        on_layout: LayoutCallback,
        loop: GLib.MainLoop,
    ) -> None:
        self._on_layout = on_layout
        self._loop = loop
        self.last_layout: str = ""
        self._bus_name = dbus.service.BusName(BUS_NAME, bus)
        super().__init__(bus, OBJECT_PATH)

    @dbus.service.method(INTERFACE, in_signature="s", out_signature="")
    def update(self, layout_json: str) -> None:
        self.last_layout = layout_json
        try:
            parsed = json.loads(layout_json)
        except json.JSONDecodeError:
            return
        if isinstance(parsed, dict):
            self._on_layout(parsed)
        self.LayoutChanged(layout_json)

    @dbus.service.method(INTERFACE, in_signature="", out_signature="s")
    def GetLayout(self) -> str:
        return self.last_layout

    @dbus.service.signal(INTERFACE, signature="s")
    def LayoutChanged(self, layout_json: str) -> None:
        pass


class LayoutBusThread(threading.Thread):
    """Run the session-bus service on a GLib loop in a background thread."""

    def __init__(self, on_layout: LayoutCallback) -> None:
        super().__init__(name="karousel-layout-bus", daemon=True)
        self._on_layout = on_layout
        self._loop: GLib.MainLoop | None = None
        self._error: str | None = None
        self._ready = threading.Event()

    @property
    def error(self) -> str | None:
        return self._error

    def wait_ready(self, timeout: float = 2.0) -> bool:
        return self._ready.wait(timeout)

    def stop(self) -> None:
        if self._loop is not None:
            self._loop.quit()

    def run(self) -> None:
        try:
            dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
            bus = dbus.SessionBus()
            if bus.name_has_owner(BUS_NAME):
                self._error = (
                    f"{BUS_NAME} is already owned. "
                    "Stop karousel-layout-bus.py (or another owner) and retry."
                )
                self._ready.set()
                return
            loop = GLib.MainLoop()
            self._loop = loop
            service = LayoutService(bus, self._on_layout, loop)
            self._ready.set()
            try:
                loop.run()
            finally:
                del service
        except Exception as exc:  # noqa: BLE001 — surface to UI thread
            self._error = str(exc)
            self._ready.set()

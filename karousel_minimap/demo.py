"""Synthetic layout snapshots for offline / no-Karousel demos."""

from __future__ import annotations

import math
from typing import Any


def demo_snapshot(tick: float) -> dict[str, Any]:
    """Build a fake ultrawide Karousel layout that scrolls over time."""
    viewport_w = 5120
    tiling_h = 1400
    scroll = (math.sin(tick / 3.0) * 0.5 + 0.5) * 1800

    columns = [
        _column(0, 1280, False, False, [
            _win("firefox", "Inbox — Thunderbird", False, 700),
            _win("org.kde.dolphin", "Projects", False, 680),
        ]),
        _column(1288, 1706, False, True, [
            _win("code-oss", "karousel — main.ts", True, 1400),
        ]),
        _column(3002, 1280, True, False, [
            _win("org.kde.konsole", "zsh", False, 1400),
            _win("org.kde.konsole", "journalctl", False, 1400),
            _win("org.kde.konsole", "htop", False, 1400),
        ]),
        _column(4290, 2560, False, False, [
            _win("spotify", "Spotify", False, 900),
            _win("org.kde.gwenview", "Photos", False, 480),
        ]),
        _column(6858, 1280, False, False, [
            _win("slack", "Slack", False, 1400),
        ]),
    ]

    return {
        "version": 1,
        "desktop": {"id": "demo-1", "name": "Demo Desktop"},
        "scrollX": round(scroll),
        "viewport": {"x": round(scroll), "width": viewport_w},
        "tilingArea": {"x": 16, "y": 16, "width": viewport_w - 32, "height": tiling_h},
        "columns": columns,
    }


def _column(
    x: int,
    width: int,
    stacked: bool,
    focused: bool,
    windows: list[dict[str, Any]],
) -> dict[str, Any]:
    return {
        "x": x,
        "width": width,
        "stacked": stacked,
        "focused": focused,
        "windows": windows,
    }


def _win(resource_class: str, caption: str, focused: bool, height: int) -> dict[str, Any]:
    return {
        "resourceClass": resource_class,
        "caption": caption,
        "pid": 0,
        "focused": focused,
        "height": height,
    }

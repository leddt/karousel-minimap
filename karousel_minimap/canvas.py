"""Paint a logical Karousel layout mini-map."""

from __future__ import annotations

from typing import Any

from PyQt6.QtCore import QRectF, Qt
from PyQt6.QtGui import QColor, QFont, QPainter, QPen
from PyQt6.QtWidgets import QWidget


class MiniMapCanvas(QWidget):
    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._layout: dict[str, Any] | None = None
        self._status = "Waiting for Karousel layout…"
        self.setMinimumSize(420, 160)
        self.setMouseTracking(True)

    def set_status(self, text: str) -> None:
        self._status = text
        self.update()

    def set_layout(self, layout: dict[str, Any]) -> None:
        self._layout = layout
        desktop = layout.get("desktop") or {}
        name = desktop.get("name") or desktop.get("id") or "?"
        cols = layout.get("columns") or []
        wins = sum(len(c.get("windows") or []) for c in cols)
        self._status = f"{name} · {len(cols)} cols · {wins} wins"
        self.update()

    def paintEvent(self, _event) -> None:  # noqa: N802
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        painter.fillRect(self.rect(), QColor("#1a1d23"))

        margin = 14.0
        map_rect = QRectF(
            margin,
            margin,
            max(self.width() - 2 * margin, 1.0),
            max(self.height() - 2 * margin - 22, 1.0),
        )

        if not self._layout:
            self._paint_empty(painter, map_rect)
        else:
            self._paint_layout(painter, map_rect)

        painter.setPen(QPen(QColor("#8b93a7")))
        font = QFont("Sans Serif", 10)
        painter.setFont(font)
        status_rect = QRectF(margin, self.height() - 28, self.width() - 2 * margin, 20)
        painter.drawText(
            status_rect,
            Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter,
            self._status,
        )
        painter.end()

    def _paint_empty(self, painter: QPainter, map_rect: QRectF) -> None:
        painter.setPen(QPen(QColor("#3a4150"), 1.5, Qt.PenStyle.DashLine))
        painter.setBrush(QColor("#22262e"))
        painter.drawRoundedRect(map_rect, 6, 6)
        painter.setPen(QPen(QColor("#6b7385")))
        painter.drawText(map_rect, Qt.AlignmentFlag.AlignCenter, "No layout yet")

    def _paint_layout(self, painter: QPainter, map_rect: QRectF) -> None:
        layout = self._layout or {}
        columns: list[dict[str, Any]] = list(layout.get("columns") or [])
        viewport = layout.get("viewport") or {}
        tiling = layout.get("tilingArea") or {}

        if not columns:
            self._paint_empty(painter, map_rect)
            return

        min_x = min(float(c.get("x", 0)) for c in columns)
        max_x = max(float(c.get("x", 0)) + float(c.get("width", 0)) for c in columns)
        content_w = max(max_x - min_x, float(viewport.get("width") or 1), 1.0)
        content_h = max(float(tiling.get("height") or 1), 1.0)

        pad = content_w * 0.04
        world_left = min_x - pad
        world_w = content_w + 2 * pad
        scale = min(map_rect.width() / world_w, map_rect.height() / content_h)
        if scale <= 0:
            return

        def sx(x: float) -> float:
            return map_rect.x() + (x - world_left) * scale

        def sw(w: float) -> float:
            return max(w * scale, 1.0)

        painter.setPen(QPen(Qt.PenStyle.NoPen))
        painter.setBrush(QColor("#22262e"))
        painter.drawRoundedRect(map_rect, 6, 6)

        vp_x = float(viewport.get("x", 0))
        vp_w = float(viewport.get("width", content_w))
        vp_rect = QRectF(sx(vp_x), map_rect.y(), sw(vp_w), map_rect.height())
        clipped = vp_rect.intersected(map_rect)
        if clipped.isValid() and clipped.width() > 0 and clipped.height() > 0:
            painter.setBrush(QColor(90, 160, 200, 40))
            painter.setPen(QPen(QColor(90, 160, 200, 160), 1.5))
            painter.drawRoundedRect(clipped, 4, 4)

        gap = max(2.0, sw(8))
        label_font = QFont("Sans Serif", 8)

        for col in columns:
            cx = float(col.get("x", 0))
            cw = float(col.get("width", 0))
            stacked = bool(col.get("stacked"))
            col_focused = bool(col.get("focused"))
            windows: list[dict[str, Any]] = list(col.get("windows") or [])

            col_rect = QRectF(
                sx(cx),
                map_rect.y() + 4,
                sw(cw),
                max(map_rect.height() - 8, 1.0),
            )
            if not col_rect.isValid():
                continue

            border = QColor("#d4a017") if col_focused else QColor("#4a5363")
            painter.setPen(QPen(border, 2 if col_focused else 1))
            painter.setBrush(QColor("#2a303a"))
            painter.drawRoundedRect(col_rect, 4, 4)

            if not windows:
                continue

            if stacked and len(windows) > 1:
                for i, win in enumerate(windows):
                    inset = 5 + i * 3
                    peek = QRectF(
                        col_rect.x() + inset,
                        col_rect.y() + 6 + i * 4,
                        max(col_rect.width() - inset - 5, 1.0),
                        max(col_rect.height() - 12 - i * 4, 1.0),
                    )
                    self._paint_window(
                        painter,
                        peek,
                        win,
                        bool(win.get("focused")),
                        label_font,
                        compact=True,
                    )
            else:
                total_h = sum(max(float(w.get("height") or 1), 1.0) for w in windows)
                inner = col_rect.adjusted(3, 3, -3, -3)
                if inner.width() <= 0 or inner.height() <= 0:
                    continue
                cursor = inner.y()
                for i, win in enumerate(windows):
                    frac = max(float(win.get("height") or 1), 1.0) / total_h
                    wh = inner.height() * frac
                    if i < len(windows) - 1:
                        wh = max(wh - gap / 2, 4.0)
                    win_rect = QRectF(inner.x(), cursor, inner.width(), max(wh, 1.0))
                    self._paint_window(
                        painter,
                        win_rect,
                        win,
                        bool(win.get("focused")),
                        label_font,
                        compact=wh < 28,
                    )
                    cursor += wh + gap

    def _paint_window(
        self,
        painter: QPainter,
        rect: QRectF,
        win: dict[str, Any],
        focused: bool,
        font: QFont,
        *,
        compact: bool,
    ) -> None:
        if not rect.isValid() or rect.width() <= 0 or rect.height() <= 0:
            return

        if focused:
            fill = QColor("#3d6b8a")
            pen = QColor("#7ec4e8")
        else:
            fill = QColor("#343b48")
            pen = QColor("#5a6475")
        painter.setPen(QPen(pen, 1))
        painter.setBrush(fill)
        painter.drawRoundedRect(rect, 3, 3)

        if compact or rect.height() < 16 or rect.width() < 24:
            return

        label = str(win.get("resourceClass") or win.get("caption") or "?")
        if "." in label:
            label = label.rsplit(".", 1)[-1]
        painter.setFont(font)
        painter.setPen(QPen(QColor("#e8ecf4") if focused else QColor("#a8b0c0")))
        text_rect = rect.adjusted(5, 2, -5, -2)
        if text_rect.width() > 0 and text_rect.height() > 0:
            painter.drawText(
                text_rect,
                Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter,
                label,
            )

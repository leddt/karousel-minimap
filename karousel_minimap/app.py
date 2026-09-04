"""Main window and CLI entrypoint."""

from __future__ import annotations

import argparse
import sys
from typing import Any

from PyQt6.QtCore import Qt, QTimer, pyqtSignal
from PyQt6.QtGui import QColor, QFont, QPalette
from PyQt6.QtWidgets import (
    QApplication,
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from .bus import LayoutBusThread
from .canvas import MiniMapCanvas
from .demo import demo_snapshot


class MainWindow(QMainWindow):
    layout_received = pyqtSignal(dict)

    def __init__(self, *, demo: bool, always_on_top: bool) -> None:
        super().__init__()
        self.setWindowTitle("Karousel Mini-map PoC")
        self.resize(720, 220)
        if always_on_top:
            self.setWindowFlag(Qt.WindowType.WindowStaysOnTopHint, True)

        self._bus: LayoutBusThread | None = None
        self._demo = demo
        self._demo_tick = 0.0

        root = QWidget()
        self.setCentralWidget(root)
        layout = QVBoxLayout(root)
        layout.setContentsMargins(12, 12, 12, 10)
        layout.setSpacing(8)

        header = QHBoxLayout()
        title = QLabel("Karousel")
        title_font = QFont("Sans Serif", 16, QFont.Weight.Bold)
        title.setFont(title_font)
        title.setStyleSheet("color: #e8ecf4;")
        header.addWidget(title)

        self._mode = QLabel()
        self._mode.setStyleSheet("color: #8b93a7;")
        header.addWidget(self._mode)
        header.addStretch(1)

        self._demo_btn = QPushButton("Demo")
        self._demo_btn.setCheckable(True)
        self._demo_btn.setChecked(demo)
        self._demo_btn.toggled.connect(self._on_demo_toggled)
        header.addWidget(self._demo_btn)
        layout.addLayout(header)

        self._canvas = MiniMapCanvas()
        layout.addWidget(self._canvas, stretch=1)

        self.layout_received.connect(self._canvas.set_layout)

        self._demo_timer = QTimer(self)
        self._demo_timer.setInterval(50)
        self._demo_timer.timeout.connect(self._tick_demo)

        if demo:
            self._mode.setText("demo feed")
            self._demo_timer.start()
            self._tick_demo()
        else:
            self._start_bus()

    def _on_demo_toggled(self, checked: bool) -> None:
        self._demo = checked
        if checked:
            self._stop_bus()
            self._mode.setText("demo feed")
            self._canvas.set_status("Demo layout")
            self._demo_timer.start()
            self._tick_demo()
        else:
            self._demo_timer.stop()
            self._start_bus()

    def _tick_demo(self) -> None:
        self._demo_tick += 0.05
        self.layout_received.emit(demo_snapshot(self._demo_tick))

    def _start_bus(self) -> None:
        self._mode.setText("D-Bus · org.kde.karousel")
        self._canvas.set_status("Waiting for Karousel layout…")

        def on_layout(snapshot: dict[str, Any]) -> None:
            # Marshal onto the Qt thread.
            self.layout_received.emit(snapshot)

        self._bus = LayoutBusThread(on_layout)
        self._bus.start()
        QTimer.singleShot(100, self._check_bus_ready)

    def _check_bus_ready(self) -> None:
        if self._bus is None:
            return
        if not self._bus.wait_ready(0.01):
            QTimer.singleShot(50, self._check_bus_ready)
            return
        if self._bus.error:
            self._canvas.set_status(self._bus.error)
            self._mode.setText("D-Bus error")

    def _stop_bus(self) -> None:
        if self._bus is not None:
            self._bus.stop()
            self._bus.join(timeout=1.5)
            self._bus = None

    def closeEvent(self, event) -> None:  # noqa: N802
        self._demo_timer.stop()
        self._stop_bus()
        super().closeEvent(event)


def _apply_theme(app: QApplication) -> None:
    app.setStyle("Fusion")
    palette = QPalette()
    palette.setColor(QPalette.ColorRole.Window, QColor("#12151a"))
    palette.setColor(QPalette.ColorRole.WindowText, QColor("#e8ecf4"))
    palette.setColor(QPalette.ColorRole.Base, QColor("#1a1d23"))
    palette.setColor(QPalette.ColorRole.Text, QColor("#e8ecf4"))
    palette.setColor(QPalette.ColorRole.Button, QColor("#2a303a"))
    palette.setColor(QPalette.ColorRole.ButtonText, QColor("#e8ecf4"))
    palette.setColor(QPalette.ColorRole.Highlight, QColor("#3d6b8a"))
    palette.setColor(QPalette.ColorRole.HighlightedText, QColor("#ffffff"))
    app.setPalette(palette)
    app.setStyleSheet(
        """
        QPushButton {
            background: #2a303a;
            border: 1px solid #4a5363;
            border-radius: 4px;
            padding: 4px 12px;
            color: #e8ecf4;
        }
        QPushButton:checked {
            background: #3d6b8a;
            border-color: #7ec4e8;
        }
        QPushButton:hover { border-color: #7ec4e8; }
        """
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--demo",
        action="store_true",
        help="animate a synthetic layout (no Karousel / D-Bus required)",
    )
    parser.add_argument(
        "--no-top",
        action="store_true",
        help="do not keep the window always on top",
    )
    args = parser.parse_args(argv)

    app = QApplication(sys.argv)
    app.setApplicationName("karousel-minimap")
    _apply_theme(app)

    window = MainWindow(demo=args.demo, always_on_top=not args.no_top)
    window.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())

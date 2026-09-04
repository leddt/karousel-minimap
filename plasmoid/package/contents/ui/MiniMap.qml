import QtQuick

Canvas {
    id: canvas

    property var layoutData: null
    property var hitRegions: []
    /** Width the map wants at the current height (column-tight). */
    property real contentWidthHint: 120
    /** Caption (or class) of the window under the pointer; empty if none. */
    property string hoveredWindowTitle: ""
    property string hoveredWindowClass: ""

    signal windowClicked(var win)
    signal scrollLeft()
    signal scrollRight()

    onLayoutDataChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    implicitWidth: Math.max(contentWidthHint, 48)
    implicitHeight: 24

    function windowLabel(win) {
        if (!win)
            return { title: "", cls: "" }
        const caption = String(win.caption || "").trim()
        let cls = String(win.resourceClass || "").trim()
        const dot = cls.lastIndexOf(".")
        if (dot >= 0)
            cls = cls.substring(dot + 1)
        return {
            title: caption || cls || "Window",
            cls: cls
        }
    }

    function updateHover(x, y) {
        const win = hitTest(x, y)
        if (!win) {
            if (hoveredWindowTitle !== "" || hoveredWindowClass !== "") {
                hoveredWindowTitle = ""
                hoveredWindowClass = ""
            }
            return
        }
        const label = windowLabel(win)
        if (hoveredWindowTitle !== label.title)
            hoveredWindowTitle = label.title
        if (hoveredWindowClass !== label.cls)
            hoveredWindowClass = label.cls
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: function (mouse) {
            const win = canvas.hitTest(mouse.x, mouse.y)
            if (win)
                canvas.windowClicked(win)
        }
        onPositionChanged: function (mouse) {
            canvas.updateHover(mouse.x, mouse.y)
        }
        onExited: {
            canvas.hoveredWindowTitle = ""
            canvas.hoveredWindowClass = ""
        }
        onWheel: function (wheel) {
            // Prefer horizontal tilt when present; otherwise vertical wheel.
            const dx = wheel.angleDelta.x
            const dy = wheel.angleDelta.y
            const delta = Math.abs(dx) > Math.abs(dy) ? dx : dy
            if (delta === 0)
                return
            // Wheel up / tilt left → Karousel "Scroll left"
            // Wheel down / tilt right → Karousel "Scroll right"
            if (delta > 0)
                canvas.scrollLeft()
            else
                canvas.scrollRight()
            wheel.accepted = true
        }
    }

    function hitTest(x, y) {
        const regions = hitRegions || []
        for (let i = regions.length - 1; i >= 0; --i) {
            const r = regions[i]
            if (x >= r.x && x <= r.x + r.w && y >= r.y && y <= r.y + r.h)
                return r.win
        }
        return null
    }

    onPaint: {
        const ctx = getContext("2d")
        const w = width
        const h = height
        hitRegions = []

        ctx.reset()
        // Transparent / match panel — minimal chrome
        ctx.clearRect(0, 0, w, h)

        const layout = layoutData
        if (!layout || !layout.columns || layout.columns.length === 0) {
            contentWidthHint = 120
            ctx.fillStyle = "#6b7385"
            ctx.font = "11px sans-serif"
            ctx.textAlign = "center"
            ctx.textBaseline = "middle"
            ctx.fillText("…", w / 2, h / 2)
            return
        }

        const columns = layout.columns
        const viewport = layout.viewport || {}
        const tiling = layout.tilingArea || {}

        let minX = columns[0].x
        let maxX = columns[0].x + columns[0].width
        for (let i = 1; i < columns.length; ++i) {
            minX = Math.min(minX, columns[i].x)
            maxX = Math.max(maxX, columns[i].x + columns[i].width)
        }

        // Fit to columns only — do NOT expand to full viewport width (that caused
        // the huge empty region on the right).
        const colsW = Math.max(maxX - minX, 1)
        const colsH = Math.max(tiling.height || 1, 1)
        const margin = 1
        const mapW = Math.max(w - 2 * margin, 1)
        const mapH = Math.max(h - 2 * margin, 1)

        // Prefer filling panel height; keep aspect ratio.
        let scale = mapH / colsH
        if (colsW * scale > mapW)
            scale = mapW / colsW

        const drawnW = colsW * scale
        const drawnH = colsH * scale
        // Center in the widget (usually flush vertically after height-fit).
        const originX = margin + (mapW - drawnW) / 2
        const originY = margin + (mapH - drawnH) / 2

        // Hint the plasmoid how wide we want to be at this height.
        contentWidthHint = Math.ceil(colsW * (h / colsH) + 2 * margin)

        function sx(x) { return originX + (x - minX) * scale }
        function sw(ww) { return Math.max(ww * scale, 1) }

        // Subtle track only behind columns
        roundRect(ctx, originX, originY, drawnW, drawnH, 2, "rgba(34,38,46,0.55)", null)

        // Viewport indicator clipped to column strip
        const vpX = sx(viewport.x || 0)
        const vpW = sw(viewport.width || colsW)
        const vLeft = Math.max(vpX, originX)
        const vRight = Math.min(vpX + vpW, originX + drawnW)
        if (vRight > vLeft + 1) {
            roundRect(ctx, vLeft, originY, vRight - vLeft, drawnH, 2, "rgba(90,160,200,0.16)", "rgba(90,160,200,0.55)")
        }

        const gap = Math.max(1, Math.min(2, sw(6)))

        for (let ci = 0; ci < columns.length; ++ci) {
            const col = columns[ci]
            const colX = sx(col.x)
            const colW = Math.max(sw(col.width) - (ci < columns.length - 1 ? 0 : 0), 1)
            const colY = originY
            const colH = drawnH
            const border = col.focused ? "#d4a017" : "#5a6475"
            roundRect(ctx, colX, colY, colW, colH, 2, "#2a303a", border)

            const windows = col.windows || []
            if (windows.length === 0)
                continue

            if (col.stacked && windows.length > 1) {
                for (let wi = 0; wi < windows.length; ++wi) {
                    const inset = 2 + wi * 2
                    const rx = colX + inset
                    const ry = colY + 2 + wi * 2
                    const rw = Math.max(colW - inset - 2, 1)
                    const rh = Math.max(colH - 4 - wi * 2, 1)
                    paintWindow(ctx, rx, ry, rw, rh, windows[wi], rh < 14)
                }
            } else {
                let totalH = 0
                for (let wi = 0; wi < windows.length; ++wi)
                    totalH += Math.max(windows[wi].height || 1, 1)
                const inset = 1.5
                const innerX = colX + inset
                const innerY = colY + inset
                const innerW = Math.max(colW - 2 * inset, 1)
                const innerH = Math.max(colH - 2 * inset, 1)
                let cursor = innerY
                for (let wi = 0; wi < windows.length; ++wi) {
                    const frac = Math.max(windows[wi].height || 1, 1) / totalH
                    let wh = innerH * frac
                    if (wi < windows.length - 1)
                        wh = Math.max(wh - gap / 2, 2)
                    paintWindow(ctx, innerX, cursor, innerW, wh, windows[wi], wh < 12)
                    cursor += wh + gap
                }
            }
        }
    }

    function paintWindow(ctx, x, y, w, h, win, compact) {
        const focused = !!win.focused
        roundRect(ctx, x, y, w, h, 1.5, focused ? "#3d6b8a" : "#343b48", focused ? "#7ec4e8" : "#5a6475")
        hitRegions.push({ x: x, y: y, w: w, h: h, win: win })

        if (compact || h < 11 || w < 18)
            return

        let label = String(win.resourceClass || win.caption || "?")
        const dot = label.lastIndexOf(".")
        if (dot >= 0)
            label = label.substring(dot + 1)

        ctx.fillStyle = focused ? "#e8ecf4" : "#a8b0c0"
        ctx.font = "9px sans-serif"
        ctx.textAlign = "left"
        ctx.textBaseline = "middle"
        ctx.save()
        ctx.beginPath()
        ctx.rect(x + 2, y, Math.max(w - 4, 0), h)
        ctx.clip()
        ctx.fillText(label, x + 3, y + h / 2)
        ctx.restore()
    }

    function roundRect(ctx, x, y, w, h, r, fill, stroke) {
        if (w <= 0 || h <= 0)
            return
        const rr = Math.min(r, w / 2, h / 2)
        ctx.beginPath()
        ctx.moveTo(x + rr, y)
        ctx.arcTo(x + w, y, x + w, y + h, rr)
        ctx.arcTo(x + w, y + h, x, y + h, rr)
        ctx.arcTo(x, y + h, x, y, rr)
        ctx.arcTo(x, y, x + w, y, rr)
        ctx.closePath()
        if (fill) {
            ctx.fillStyle = fill
            ctx.fill()
        }
        if (stroke) {
            ctx.strokeStyle = stroke
            ctx.lineWidth = 1
            ctx.stroke()
        }
    }
}

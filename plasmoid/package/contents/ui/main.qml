import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.taskmanager as TaskManager

PlasmoidItem {
    id: root

    // Panel: always show the map inline (compact rep), never icon→popup.
    preferredRepresentation: compactRepresentation
    // Huge switch thresholds so Plasma does not flip to the popup full rep.
    switchWidth: Kirigami.Units.gridUnit * 1000
    switchHeight: Kirigami.Units.gridUnit * 1000

    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground

    property var layoutData: null
    property string statusText: "Connecting…"
    property string lastLayoutJson: ""
    property bool ensureBusPending: false
    // Limit wheel → Karousel scroll rate to avoid edge glitches with animations.
    readonly property int scrollThrottleMs: 30
    property int pendingScrollDir: 0

    property string hoverTitle: ""
    property string hoverClass: ""

    toolTipMainText: hoverTitle !== "" ? hoverTitle : "Karousel Mini-map"
    toolTipSubText: hoverTitle !== ""
        ? (hoverClass !== "" && hoverClass !== hoverTitle ? hoverClass : "")
        : statusText

    TaskManager.TasksModel {
        id: tasksModel
        sortMode: TaskManager.TasksModel.SortVirtualDesktop
        groupMode: TaskManager.TasksModel.GroupDisabled
        separateLaunchers: false
        filterByVirtualDesktop: false
        filterByActivity: false
        filterByScreen: false
    }

    Plasma5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []

        onNewData: function (source, data) {
            const stdout = String(data["stdout"] || "").trim()
            const stderr = String(data["stderr"] || "").trim()
            const exitCode = data["exit code"]
            exec.disconnectSource(source)

            if (source.indexOf("GetLayout") !== -1) {
                root.onPollResult(stdout, stderr, exitCode)
                return
            }
            // invokeShortcut / ensure-bus: nothing else to parse
            if (root.ensureBusPending) {
                root.ensureBusPending = false
                pollTimer.start()
                root.pollOnce()
            }
        }
    }

    Timer {
        id: pollTimer
        interval: 250
        repeat: true
        running: false
        onTriggered: root.pollOnce()
    }

    Timer {
        id: scrollThrottleTimer
        interval: root.scrollThrottleMs
        repeat: false
        onTriggered: {
            if (root.pendingScrollDir !== 0) {
                const dir = root.pendingScrollDir
                root.pendingScrollDir = 0
                root.fireKarouselScroll(dir)
                scrollThrottleTimer.start()
            }
        }
    }

    function busScriptPath() {
        let url = Qt.resolvedUrl("../code/layout_bus.py").toString()
        if (url.startsWith("file://"))
            url = url.substring(7)
        return url
    }

    function ensureBus() {
        const path = busScriptPath()
        ensureBusPending = true
        statusText = "Starting layout bus…"
        const cmd = "bash -c " + shellQuote([
            "if qdbus6 org.kde.karousel >/dev/null 2>&1; then exit 0; fi",
            "if systemctl --user start karousel-layout-bus.service 2>/dev/null; then exit 0; fi",
            "systemd-run --user --unit=karousel-layout-bus --collect python3 " + shellQuote(path) + " >/dev/null 2>&1 && exit 0",
            "nohup python3 " + shellQuote(path) + " >/dev/null 2>&1 &",
            "exit 0"
        ].join("; "))
        exec.connectSource(cmd)
    }

    function shellQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    function pollOnce() {
        const src = "qdbus6 org.kde.karousel /Layout org.kde.karousel.Layout.GetLayout"
        if (exec.connectedSources.indexOf(src) !== -1)
            return
        exec.connectSource(src)
    }

    function onPollResult(stdout, stderr, exitCode) {
        if (!stdout) {
            if (String(exitCode) === "2" || stderr.indexOf("does not exist") !== -1
                    || stderr.indexOf("Service ") !== -1) {
                statusText = "Waiting for layout bus…"
                if (!ensureBusPending)
                    ensureBus()
            } else if (stderr) {
                statusText = stderr.split("\n")[0]
            }
            return
        }
        if (stdout === lastLayoutJson)
            return
        lastLayoutJson = stdout
        try {
            const parsed = JSON.parse(stdout)
            layoutData = parsed
            const desktop = parsed.desktop || {}
            const cols = parsed.columns || []
            let wins = 0
            for (let c = 0; c < cols.length; ++c)
                wins += (cols[c].windows || []).length
            statusText = (desktop.name || desktop.id || "?")
                + " · " + cols.length + " cols · " + wins + " wins"
        } catch (e) {
            statusText = "Bad layout JSON"
        }
    }

    function invokeKarouselScroll(direction) {
        // Leading fire, then throttle; coalesce extras to one trailing step.
        if (!scrollThrottleTimer.running) {
            fireKarouselScroll(direction)
            scrollThrottleTimer.start()
            return
        }
        pendingScrollDir = direction
    }

    function fireKarouselScroll(direction) {
        invokeKarouselShortcut(direction < 0
            ? "karousel-grid-scroll-left"
            : "karousel-grid-scroll-right")
    }

    function invokeKarouselShortcut(shortcut) {
        const src = "qdbus6 org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "
            + shellQuote(shortcut)
        if (exec.connectedSources.indexOf(src) !== -1)
            return
        exec.connectSource(src)
    }

    function activateWindow(win) {
        if (!win)
            return
        // Already focused → same as Meta+Alt+Return: center in the viewport.
        if (win.focused) {
            invokeKarouselShortcut("karousel-grid-scroll-focused")
            return
        }
        const pid = Number(win.pid || 0)
        const resourceClass = String(win.resourceClass || "")
        const caption = String(win.caption || "")

        // Title first: multi-window apps (Steam library + Friends, etc.) share a PID.
        if (caption && activateByWindowTitle(caption, pid))
            return
        if (pid > 0 && activateByPid(pid))
            return
        if (resourceClass && activateByAppId(resourceClass))
            return
        if (caption && activateByAppName(caption))
            return
        statusText = "Could not activate " + (resourceClass || caption || "window")
    }

    function titlesMatch(taskTitle, caption) {
        if (!taskTitle || !caption)
            return false
        if (taskTitle === caption)
            return true
        const a = taskTitle.toLowerCase()
        const b = caption.toLowerCase()
        return a === b || a.indexOf(b) !== -1 || b.indexOf(a) !== -1
    }

    function activateByWindowTitle(caption, pid) {
        let exactPid = null
        let exactAny = null
        let fuzzyPid = null
        let fuzzyAny = null

        for (let i = 0; i < tasksModel.count; ++i) {
            const idx = tasksModel.index(i, 0)
            if (!tasksModel.data(idx, TaskManager.AbstractTasksModel.IsWindow))
                continue
            const title = String(tasksModel.data(idx, Qt.DisplayRole) || "")
            if (!title)
                continue
            const taskPid = Number(tasksModel.data(idx, TaskManager.AbstractTasksModel.AppPid) || 0)
            const samePid = pid > 0 && taskPid === pid
            if (title === caption) {
                if (samePid)
                    exactPid = idx
                else if (!exactAny)
                    exactAny = idx
                continue
            }
            if (!titlesMatch(title, caption))
                continue
            if (samePid) {
                if (!fuzzyPid)
                    fuzzyPid = idx
            } else if (!fuzzyAny) {
                fuzzyAny = idx
            }
        }

        const best = exactPid || exactAny || fuzzyPid || fuzzyAny
        if (!best)
            return false
        tasksModel.requestActivate(best)
        return true
    }

    function activateByPid(pid) {
        for (let i = 0; i < tasksModel.count; ++i) {
            const idx = tasksModel.index(i, 0)
            const taskPid = tasksModel.data(idx, TaskManager.AbstractTasksModel.AppPid)
            if (Number(taskPid) === pid) {
                tasksModel.requestActivate(idx)
                return true
            }
        }
        return false
    }

    function activateByAppId(appId) {
        const needle = appId.toLowerCase()
        for (let i = 0; i < tasksModel.count; ++i) {
            const idx = tasksModel.index(i, 0)
            const id = String(tasksModel.data(idx, TaskManager.AbstractTasksModel.AppId) || "").toLowerCase()
            if (id === needle || id.endsWith("." + needle) || id.split(".").pop() === needle) {
                tasksModel.requestActivate(idx)
                return true
            }
        }
        return false
    }

    function activateByAppName(caption) {
        for (let i = 0; i < tasksModel.count; ++i) {
            const idx = tasksModel.index(i, 0)
            const name = String(tasksModel.data(idx, TaskManager.AbstractTasksModel.AppName) || "")
            const generic = String(tasksModel.data(idx, TaskManager.AbstractTasksModel.GenericName) || "")
            if (name === caption || caption.indexOf(name) === 0 || generic === caption) {
                tasksModel.requestActivate(idx)
                return true
            }
        }
        return false
    }

    Component.onCompleted: ensureBus()

    // Inline panel representation — size to content, don't stretch empty width
    compactRepresentation: Item {
        id: compactRoot

        readonly property bool horizontal: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
        readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

        Layout.fillWidth: false
        Layout.fillHeight: true
        Layout.minimumWidth: horizontal ? Kirigami.Units.gridUnit * 6 : 0
        Layout.preferredWidth: horizontal
            ? Math.max(miniMap.contentWidthHint, Kirigami.Units.gridUnit * 8)
            : Kirigami.Units.iconSizes.medium
        Layout.maximumWidth: horizontal ? Kirigami.Units.gridUnit * 40 : Infinity
        Layout.minimumHeight: vertical ? Kirigami.Units.gridUnit * 6 : 0
        Layout.preferredHeight: vertical
            ? Math.max(miniMap.contentWidthHint, Kirigami.Units.gridUnit * 8)
            : Kirigami.Units.iconSizes.medium

        MiniMap {
            id: miniMap
            anchors.fill: parent
            layoutData: root.layoutData
            onHoveredWindowTitleChanged: root.hoverTitle = hoveredWindowTitle
            onHoveredWindowClassChanged: root.hoverClass = hoveredWindowClass
            onWindowClicked: function (win) {
                root.activateWindow(win)
            }
            onScrollLeft: root.invokeKarouselScroll(-1)
            onScrollRight: root.invokeKarouselScroll(1)
        }
    }

    // Desktop / larger view still available if needed
    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.preferredWidth: Kirigami.Units.gridUnit * 28
        Layout.minimumHeight: Kirigami.Units.gridUnit * 3
        Layout.preferredHeight: Kirigami.Units.gridUnit * 5

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: 2

            MiniMap {
                Layout.fillWidth: true
                Layout.fillHeight: true
                layoutData: root.layoutData
                onHoveredWindowTitleChanged: root.hoverTitle = hoveredWindowTitle
                onHoveredWindowClassChanged: root.hoverClass = hoveredWindowClass
                onWindowClicked: function (win) {
                    root.activateWindow(win)
                }
                onScrollLeft: root.invokeKarouselScroll(-1)
                onScrollRight: root.invokeKarouselScroll(1)
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: root.statusText
                opacity: 0.7
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                elide: Text.ElideRight
            }
        }
    }
}

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.components.icons
import qs.components.controls
import qs.modules.desktopwidgets

Item {
    id: root

    property var widgetData: ({})
    property var now: new Date()
    property int claudeProcessCount: -1
    readonly property var player: Players.active
    readonly property bool hasPlayer: player !== null && player !== undefined
    property alias musicTransportInput: musicControls
    property var musicSeekInput: widgetId === "musicPulse" ? pulseSeekArea : musicSeekArea
    property alias timerInput: timerToggle

    readonly property real s: Math.max(0.7, Math.min(1.7, Math.min(width / 240, height / 156)))
    readonly property real inset: 16 * root.s
    readonly property string widgetId: widgetData.id || ""
    readonly property string title: widgetData.label || "Widget"
    readonly property string category: widgetData.category || ""
    readonly property string photoSource: {
        var path = Flags.desktopWidgetPhoto.trim();
        return path.indexOf("~/") === 0 ? Quickshell.env("HOME") + path.slice(1) : path;
    }
    readonly property bool isTimer: widgetId === "pomodoro" || widgetId === "countdowns"
    readonly property bool isMusic: category === "Music"
    readonly property real cpu: Math.max(0, Math.min(100, Sysmon.cpu))
    readonly property real memory: Math.max(0, Math.min(100, Sysmon.memPct))
    readonly property real gpu: Sysmon.hasGpu ? Math.max(0, Math.min(100, Sysmon.gpu)) : 0
    readonly property var systemMetrics: {
        var metrics = [
            { label: "CPU", value: root.cpu },
            { label: "RAM", value: root.memory }
        ];
        if (Sysmon.hasGpu)
            metrics.push({ label: "GPU", value: root.gpu });
        return metrics;
    }
    readonly property var quadMetrics: {
        var metrics = root.systemMetrics.slice(0);
        metrics.push({ label: "DSK", value: Math.max(0, Math.min(100, Sysmon.diskPct)) });
        return metrics;
    }
    readonly property var ringMetrics: [
        { label: "CPU", value: root.cpu },
        { label: "RAM", value: root.memory },
        { label: "DISK", value: Math.max(0, Math.min(100, Sysmon.diskPct)) }
    ]
    readonly property real trackProgress: root.hasPlayer && Players.lengthSec > 0
        ? Math.max(0, Math.min(1, root.player.position / Players.lengthSec)) : 0
    readonly property real yearProgress: {
        var elapsedDay = (root.now.getHours() * 3600 + root.now.getMinutes() * 60
            + root.now.getSeconds()) / 86400;
        return (root.dayOfYear - 1 + elapsedDay) / root.daysInYear;
    }
    readonly property real progress: {
        switch (widgetId) {
        case "sysMemory": return memory / 100;
        case "sysBattery": return root.batteryLevel >= 0 ? root.batteryLevel / 100 : 0;
        case "sysThermals": return Math.max(0, Math.min(1,
            (Sysmon.hasGpu && Sysmon.gpuTemp >= 0 ? Sysmon.gpuTemp : Sysmon.cpuTemp) / 100));
        case "sunArc": return root.dayProgress;
        case "pomodoro": return DesktopWidgetState.focusTimerSeconds / 1500;
        case "countdowns":
        case "calendarYear": return root.yearProgress;
        case "musicRail": return trackProgress;
        default: return cpu / 100;
        }
    }
    readonly property bool progressVisible: {
        switch (widgetId) {
        case "sysMemory": return Sysmon.memTotalGb > 0;
        case "sysBattery": return Battery.present;
        case "sysThermals": return Sysmon.cpuTemp >= 0
            || (Sysmon.hasGpu && Sysmon.gpuTemp >= 0);
        case "musicRail":
            return root.hasPlayer && Players.lengthSec > 0 && !Players.live;
        case "calendarYear":
        case "pomodoro":
        case "countdowns":
            return true;
        default:
            return false;
        }
    }
    readonly property real batteryLevel: {
        return Battery.present ? Battery.pct : -1;
    }
    readonly property var connectedPhone: {
        var devices = Peripherals.connected;
        for (var i = 0; i < devices.length; i++)
            if (devices[i].kind === "smartphone")
                return devices[i];
        return null;
    }
    readonly property real dayProgress: {
        if (!Weather.ready || Weather.sunrise.length < 5 || Weather.sunset.length < 5)
            return 0;
        var sunrise = Weather.sunrise.split(":");
        var sunset = Weather.sunset.split(":");
        var start = Number(sunrise[0]) * 60 + Number(sunrise[1]);
        var end = Number(sunset[0]) * 60 + Number(sunset[1]);
        var weatherNow = new Date(root.now.getTime() + Weather.utcOffsetSeconds * 1000);
        var current = weatherNow.getUTCHours() * 60 + weatherNow.getUTCMinutes();
        return Math.max(0, Math.min(1, (current - start) / Math.max(1, end - start)));
    }
    readonly property bool calendarMonthWidget: ["calendarMini", "calendarYarn",
        "calendarAlmanac", "calendarWindows"].indexOf(widgetId) >= 0
    readonly property var calendarDays: {
        var firstDay = new Date(root.now.getFullYear(), root.now.getMonth(), 1);
        var daysInMonth = new Date(root.now.getFullYear(), root.now.getMonth() + 1, 0).getDate();
        var mondayOffset = (firstDay.getDay() + 6) % 7;
        var cells = [];
        for (var i = 0; i < 42; i++) {
            var day = i - mondayOffset + 1;
            cells.push(day > 0 && day <= daysInMonth ? day : 0);
        }
        return cells;
    }
    readonly property var upcomingHours: {
        var rows = Weather.hourly;
        var currentHour = Weather.ready
            ? new Date(root.now.getTime() + Weather.utcOffsetSeconds * 1000).getUTCHours()
            : root.now.getHours();
        var first = 0;
        while (first < rows.length && Number(rows[first].hour) < currentHour)
            first++;
        if (first >= rows.length)
            first = 0;
        return rows.slice(first, first + 5);
    }
    readonly property real daysInYear: (new Date(root.now.getFullYear() + 1, 0, 1)
        - new Date(root.now.getFullYear(), 0, 1)) / 86400000

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height) * 0.78
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 1.5 * root.s
        border.color: Qt.alpha(Theme.primary, 0.45)
        visible: root.widgetId === "digitalClock"
            && DesktopWidgetState.digitalClockStyle === "orbit"
        z: 1
    }

    Rectangle {
        anchors.right: parent.right
        anchors.rightMargin: root.inset
        anchors.top: header.bottom
        anchors.topMargin: 5 * root.s
        width: 52 * root.s
        height: width
        radius: width / 2
        color: Qt.alpha(Theme.primary, 0.15)
        border.width: 1 * root.s
        border.color: Qt.alpha(Theme.primary, 0.5)
        visible: root.widgetId === "musicDisc"
        z: 2
        RotationAnimation {
            target: parent
            from: 0
            to: 360
            duration: 9000
            loops: Animation.Infinite
            running: root.widgetId === "musicDisc" && Players.playing
        }
        GlyphIcon {
            anchors.centerIn: parent
            width: 23 * root.s
            height: width
            name: "music"
            color: Theme.primary
        }
    }

    function formattedTime(date, utc) {
        var hour = utc ? date.getUTCHours() : date.getHours();
        var minute = utc ? date.getUTCMinutes() : date.getMinutes();
        var suffix = hour >= 12 ? "PM" : "AM";
        var displayHour = hour % 12 || 12;
        var mm = minute < 10 ? "0" + minute : "" + minute;
        return Flags.time12h ? displayHour + ":" + mm + " " + suffix
            : (hour < 10 ? "0" + hour : hour) + ":" + mm;
    }

    function compass(degrees) {
        return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][
            Math.round((degrees % 360) / 45) % 8];
    }

    function refreshClaudeStatus() {
        if (root.widgetId === "claudeCode" && !claudeProc.running)
            claudeProc.running = true;
    }

    function mainValue() {
        switch (widgetId) {
        case "digitalClock":
            var clockText = root.formattedTime(root.now, false);
            if (DesktopWidgetState.digitalClockStyle === "condensed")
                return clockText.replace(":", "").replace(" ", "");
            if (DesktopWidgetState.digitalClockStyle === "stack") {
                var hour = Flags.time12h ? (root.now.getHours() % 12 || 12)
                    : root.now.getHours();
                var minute = root.now.getMinutes();
                return hour + "\n" + (minute < 10 ? "0" : "") + minute
                    + (Flags.time12h ? (root.now.getHours() >= 12 ? " PM" : " AM") : "");
            }
            if (DesktopWidgetState.digitalClockStyle === "display")
                return clockText + " " + (root.now.getSeconds() < 10 ? "0" : "")
                    + root.now.getSeconds();
            return clockText;
        case "profileBadge":
            var user = String(Quickshell.env("USER") || "");
            return user.length ? user.toUpperCase() : "LOCAL USER";
        case "profileDay":
        case "calendarMini":
        case "calendarYarn":
        case "calendarAlmanac":
        case "calendarWindows":
        case "moon":
            return root.now.getDate();
        case "profileStatus":
            return Sysmon.uptime.length ? "READY" : "STARTING";
        case "profileMachine":
        case "sysChrono":
            return Sysmon.uptime.replace("UP ", "");
        case "profileShape":
            return "✦";
        case "profileRings":
            return cpu + "%";
        case "photoFrame":
            return Qt.formatDate(root.now, "ddd, MMM d");
        case "yearAgo":
            var previousYearMonth = root.now.getMonth();
            var previousYearDay = Math.min(root.now.getDate(),
                new Date(root.now.getFullYear() - 1, previousYearMonth + 1, 0).getDate());
            return Qt.formatDate(new Date(root.now.getFullYear() - 1,
                previousYearMonth, previousYearDay), "MMM d");
        case "phone":
            return root.connectedPhone ? root.connectedPhone.name : "No phone connected";
        case "countdowns":
            return Math.floor((Date.UTC(root.now.getFullYear() + 1, 0, 1)
                - Date.UTC(root.now.getFullYear(), root.now.getMonth(), root.now.getDate()))
                / 86400000) + " days";
        case "music":
        case "musicExpressive":
        case "musicDisc":
        case "musicDeck":
        case "musicRail":
        case "musicPulse":
            return Players.has ? Players.title : "Nothing playing";
        case "sunArc":
            return Weather.ready ? Weather.sunrise + "  →  " + Weather.sunset : "Daylight";
        case "weather":
        case "weatherPoster":
        case "weatherHours":
            return Weather.ready ? Weather.tempNow + "°" : "--°";
        case "weatherDayClock":
            return root.formattedTime(root.now, false);
        case "weatherWind":
            return Weather.ready ? Weather.windSpeed + " km/h" : "Weather unavailable";
        case "calendarYear":
            return Math.floor(root.dayOfYear / root.daysInYear * 100) + "%";
        case "claudeCode":
            return root.claudeProcessCount < 0 ? "CHECKING SESSION"
                : root.claudeProcessCount > 0 ? root.claudeProcessCount + " CLI PROCESS"
                : "NO ACTIVE CLI";
        case "stickyNote":
            return "";
        case "pomodoro":
            return DesktopWidgetState.formatFocusTimer();
        case "worldClock":
            return root.formattedTime(root.now, false);
        case "headlines":
            return Notifs.groups.length > 0
                ? Notifs.groups[0].preview.summary : "No recent notifications";
        case "system":
        case "sysCores":
        case "sysOrbit":
            return cpu + "%";
        case "sysQuad":
            return "SYSTEM";
        case "sysMemory":
            return Sysmon.memUsedGb.toFixed(1) + " GB";
        case "sysBattery":
            return Battery.present ? root.batteryLevel + "%" : "No system battery";
        case "sysThermals":
            return Sysmon.cpuTemp >= 0 ? Sysmon.cpuTemp + "°C"
                : Sysmon.gpuTemp >= 0 ? Sysmon.gpuTemp + "°C" : "—";
        case "sysNet":
            return (Sysmon.netDown + Sysmon.netUp).toFixed(1) + " MB/s";
        case "sysSilhouette":
            return "CPU " + cpu + "%";
        default:
            return title;
        }
    }

    function detailValue() {
        switch (widgetId) {
        case "profileDay":
            return Qt.formatDate(root.now, "dddd, MMMM d");
        case "profileBadge":
            return "Local system account";
        case "profileStatus":
            return Sysmon.uptime.length ? Sysmon.uptime : "System monitor starting";
        case "profileMachine":
            return Sysmon.hasGpu ? "CPU " + cpu + "% · GPU " + gpu + "%"
                : "CPU " + cpu + "% · Memory " + memory + "%";
        case "profileRings":
            return "Live CPU · memory · disk activity";
        case "photoFrame":
            if (root.photoSource.length === 0)
                return "Set an image path in widget settings";
            if (photoImage.status === Image.Loading)
                return "Loading image";
            if (photoImage.status === Image.Error)
                return "Unable to load this image";
            return Qt.formatDate(root.now, "dddd, MMMM d");
        case "yearAgo":
            return "One year before today";
        case "phone":
            return root.connectedPhone
                ? (root.connectedPhone.level >= 0
                    ? "Bluetooth · battery " + root.connectedPhone.level + "%"
                    : "Bluetooth · battery unavailable")
                : "No connected Bluetooth phone";
        case "music":
        case "musicExpressive":
        case "musicDisc":
        case "musicDeck":
        case "musicRail":
        case "musicPulse":
            return Players.has ? Players.artist : "Connect a media player";
        case "sunArc":
            return Weather.ready && Weather.sunrise.length > 0 && Weather.sunset.length > 0
                ? "Sunrise and sunset" : "Daylight data unavailable";
        case "weather":
        case "weatherPoster":
        case "weatherHours":
            return Weather.ready ? Weather.labelFor(Weather.codeNow)
                + (Weather.city.length ? " · " + Weather.city : "") : "Waiting for forecast";
        case "weatherDayClock":
            return Weather.ready ? Weather.tempNow + "° · "
                + Weather.labelFor(Weather.codeNow) : "Waiting for forecast";
        case "weatherWind":
            return Weather.ready
                ? root.compass(Weather.windDirection) + " wind · " + Weather.humidity + "% humidity"
                : "Waiting for forecast";
        case "calendarMini":
        case "calendarWindows":
            return Qt.formatDate(root.now, "MMMM yyyy");
        case "calendarYarn":
            return "Week " + Qt.formatDate(root.now, "ww") + " · "
                + Qt.formatDate(root.now, "MMMM yyyy");
        case "calendarAlmanac":
            return Weather.moonPhaseFor(root.now) + " · "
                + Qt.formatDate(root.now, "MMMM yyyy");
        case "calendarYear":
            return Qt.formatDate(root.now, "yyyy") + " · year progress";
        case "moon":
            return Weather.moonPhaseFor(root.now) + " · "
                + Math.round((1 - Math.cos(2 * Math.PI * Weather.moonAgeFor(root.now))) * 50) + "% lit";
        case "claudeCode":
            return root.claudeProcessCount < 0 ? "Checking local processes"
                : root.claudeProcessCount > 0 ? "Claude Code process detected"
                : "No Claude Code process detected";
        case "stickyNote":
            return "Saved locally in shell settings";
        case "pomodoro":
            return DesktopWidgetState.focusTimerRunning ? "FOCUS IN PROGRESS" : "25 minute focus timer";
        case "countdowns":
            return "Until the new year";
        case "worldClock":
            return "UTC " + root.formattedTime(root.now, true);
        case "headlines":
            return Notifs.groups.length > 0
                ? Notifs.groups[0].app + " · " + Notifs.groups.length + " apps"
                : "Notifications will appear here";
        case "sysOrbit":
            return "RAM " + memory + "%"
                + (Sysmon.hasGpu ? " · GPU " + gpu + "%" : "");
        case "sysCores":
            return Sysmon.hasGpu ? "GPU " + gpu + "% · Memory " + memory + "%" : "Memory " + memory + "%";
        case "sysQuad":
            return root.quadMetrics.map(function(metric) {
                return metric.label + " " + metric.value + "%";
            }).join(" · ");
        case "sysMemory":
            return Sysmon.memTotalGb.toFixed(1) + " GB total";
        case "sysBattery":
            return Battery.present ? Battery.stateLabel : "Battery not detected";
        case "sysThermals":
            return Sysmon.hasGpu && Sysmon.gpuTemp >= 0
                ? (Sysmon.cpuTemp >= 0 ? "CPU " + Sysmon.cpuTemp + "°C · " : "")
                    + "GPU " + Sysmon.gpuTemp + "°C"
                : Sysmon.cpuTemp >= 0 ? "CPU temperature" : "Temperature unavailable";
        case "sysNet":
            return "↓ " + Sysmon.netDown.toFixed(1) + " · ↑ " + Sysmon.netUp.toFixed(1) + " MB/s";
        case "sysChrono":
            return Sysmon.uptime;
        case "sysSilhouette":
            return "MEM " + memory + "% · DISK " + Sysmon.diskPct + "%";
        default:
            return category;
        }
    }

    readonly property int dayOfYear: Math.floor((Date.UTC(root.now.getFullYear(),
        root.now.getMonth(), root.now.getDate()) - Date.UTC(root.now.getFullYear(), 0, 1))
        / 86400000) + 1
    readonly property string glyph: {
        switch (widgetId) {
        case "profileBadge": return "user";
        case "profileDay":
        case "yearAgo": return "calendar";
        case "profileStatus": return "check";
        case "profileMachine":
        case "sysQuad":
        case "sysSilhouette": return "monitor";
        case "profileShape": return "sparkles";
        case "profileRings":
        case "sysCores":
        case "sysOrbit": return "activity";
        case "photoFrame": return "camera";
        case "phone": return "smartphone";
        case "countdowns":
        case "pomodoro": return "stopwatch";
        case "music":
        case "musicExpressive":
        case "musicDisc":
        case "musicDeck":
        case "musicRail":
        case "musicPulse": return "music";
        case "digitalClock":
        case "worldClock":
        case "sysChrono":
        case "weatherDayClock": return "clock";
        case "weather":
        case "weatherPoster":
        case "weatherHours":
        case "weatherWind":
        case "sunArc":
            return Weather.ready ? Weather.glyphFor(Weather.codeNow, Weather.isDay) : "cloud";
        case "calendarMini":
        case "calendarYarn":
        case "calendarAlmanac":
        case "calendarWindows":
        case "calendarYear":
        case "moon": return "calendar";
        case "claudeCode": return "terminal";
        case "stickyNote": return "note";
        case "headlines": return "notifications";
        case "sysMemory": return "memory";
        case "sysBattery": return "battery-full";
        case "sysThermals": return "thermometer";
        case "sysNet": return "wifi";
        case "system": return "monitor";
        default: return "app-window";
        }
    }

    AlignedTimer {
        period: ["digitalClock", "worldClock", "weatherDayClock"].indexOf(root.widgetId) >= 0
            ? 1000 : 60000
        active: ["digitalClock", "worldClock", "weatherDayClock", "sunArc", "weather",
            "weatherHours", "profileDay", "calendarMini", "calendarYarn",
            "calendarAlmanac", "calendarWindows", "calendarYear", "yearAgo", "countdowns"].indexOf(root.widgetId) >= 0
        onTick: (date) => {
            root.now = date;
            if (root.widgetId === "sunArc")
                solarArc.requestPaint();
        }
    }

    Timer {
        interval: 5000
        repeat: true
        running: root.widgetId === "claudeCode"
        triggeredOnStart: true
        onTriggered: root.refreshClaudeStatus()
    }

    Timer {
        interval: 500
        repeat: true
        running: (root.widgetId === "musicRail" || root.widgetId === "musicPulse")
            && root.hasPlayer && root.player.positionSupported
        onTriggered: if (root.hasPlayer) root.player.positionChanged()
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.widgetId === "profileRings" || root.widgetId === "sysOrbit"
        onTriggered: {
            activityRings.requestPaint();
            orbitCanvas.requestPaint();
        }
    }

    Process {
        id: claudeProc
        command: ["pgrep", "-af", "claude"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n");
                var count = 0;
                for (var i = 0; i < lines.length; i++) {
                            if (/(^|\s|\/)claude(-code)?(\s|\/|$)/i.test(lines[i]))
                        count++;
                }
                root.claudeProcessCount = count;
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 22 * root.s
        color: Theme.surfaceContainerLowest
        border.width: 1
        border.color: Qt.alpha(Theme.outlineVariant, 0.3)
    }

    Image {
        id: photoImage
        anchors.fill: parent
        anchors.margins: 5 * root.s
        source: root.photoSource
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        visible: root.widgetId === "photoFrame" && root.photoSource.length > 0
        opacity: 0.82
    }

    Rectangle {
        anchors.fill: parent
        radius: 22 * root.s
        color: Qt.alpha(Theme.surfaceContainerLowest, 0.36)
        visible: root.widgetId === "photoFrame" && root.photoSource.length > 0
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 3 * root.s
        radius: height / 2
        color: Theme.primary
        visible: root.widgetId === "musicRail"
    }

    Canvas {
        id: solarArc
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: detail.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.inset
        anchors.rightMargin: root.inset
        anchors.topMargin: 4 * root.s
        anchors.bottomMargin: 12 * root.s
        visible: root.widgetId === "sunArc" && Weather.ready
            && Weather.sunrise.length > 0 && Weather.sunset.length > 0
        antialiasing: true

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            var cx = width / 2;
            var cy = height * 0.88;
            var radius = Math.max(8, Math.min(width * 0.4, height * 0.76));
            ctx.beginPath();
            ctx.arc(cx, cy, radius, Math.PI, Math.PI * 2);
            ctx.lineWidth = 4 * root.s;
            ctx.lineCap = "round";
            ctx.strokeStyle = Qt.alpha(Theme.primary, 0.2);
            ctx.stroke();
            ctx.beginPath();
            ctx.arc(cx, cy, radius, Math.PI, Math.PI + Math.PI * root.dayProgress);
            ctx.strokeStyle = Theme.primary;
            ctx.stroke();
            var angle = Math.PI + Math.PI * root.dayProgress;
            ctx.beginPath();
            ctx.arc(cx + Math.cos(angle) * radius, cy + Math.sin(angle) * radius,
                4 * root.s, 0, Math.PI * 2);
            ctx.fillStyle = Theme.primary;
            ctx.fill();
        }
    }

    Row {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: root.inset
        anchors.rightMargin: root.inset
        anchors.topMargin: 14 * root.s
        spacing: 7 * root.s
        z: 2

        GlyphIcon {
            anchors.verticalCenter: parent.verticalCenter
            width: 15 * root.s
            height: width
            name: root.glyph
            color: Theme.primary
            visible: root.category !== "Weather" || Weather.ready
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.widgetId === "digitalClock"
                ? DesktopWidgetState.digitalClockStyle.toUpperCase() : root.title.toUpperCase()
            color: Theme.primary
            font.family: Theme.font
            font.pixelSize: 10 * root.s
            font.weight: Font.Bold
            font.letterSpacing: 0.8 * root.s
            elide: Text.ElideRight
        }

        Item { width: Math.max(0, header.width - 110 * root.s); height: 1 }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.category === "System" && Sysmon.cpuTemp >= 0
            text: Sysmon.cpuTemp + "°C"
            color: Theme.onSurfaceVariant
            font.family: Theme.font
            font.pixelSize: 9 * root.s
        }
    }

    Text {
        id: hero
        anchors.left: parent.left
        width: root.widgetId === "musicDisc" || root.widgetId === "weatherDayClock"
            ? parent.width - 86 * root.s
            : root.isMusic ? parent.width - 106 * root.s : parent.width - 32 * root.s
        anchors.leftMargin: root.inset
        anchors.rightMargin: root.inset
        anchors.top: header.bottom
        anchors.topMargin: 7 * root.s
        height: root.calendarMonthWidget ? 0
            : root.widgetId === "digitalClock"
                && DesktopWidgetState.digitalClockStyle === "stack"
                ? parent.height * 0.56 : Math.max(25 * root.s, parent.height * 0.32)
        visible: !root.calendarMonthWidget && root.widgetId !== "headlines"
        verticalAlignment: Text.AlignVCenter
        text: root.mainValue()
        color: root.widgetId === "digitalClock"
                && DesktopWidgetState.digitalClockStyle === "bloom"
            ? Theme.primary : Theme.onSurface
        font.family: Theme.font
        font.pixelSize: root.widgetId === "digitalClock"
                && DesktopWidgetState.digitalClockStyle === "stack" ? 23 * root.s
            : root.widgetId === "digitalClock" ? 35 * root.s
            : root.widgetId === "musicExpressive" ? 22 * root.s
            : root.category === "Music" ? 18 * root.s : 27 * root.s
        font.weight: root.widgetId === "digitalClock"
                && DesktopWidgetState.digitalClockStyle === "condensed"
            ? Font.Black : Font.Bold
        font.italic: root.widgetId === "digitalClock"
            && DesktopWidgetState.digitalClockStyle === "script"
        font.features: ({ "tnum": 1 })
        elide: Text.ElideRight
        maximumLineCount: root.widgetId === "digitalClock"
                && DesktopWidgetState.digitalClockStyle === "stack" ? 2 : 1
        horizontalAlignment: root.widgetId === "digitalClock"
                && DesktopWidgetState.digitalClockStyle === "stack" ? Text.AlignHCenter : Text.AlignLeft
        z: 2
    }

    Text {
        id: detail
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.inset
        anchors.rightMargin: root.inset
        anchors.top: hero.bottom
        anchors.topMargin: 3 * root.s
        text: root.detailValue()
        color: Theme.onSurfaceVariant
        font.family: Theme.font
        font.pixelSize: 10 * root.s
        elide: Text.ElideRight
        maximumLineCount: 1
        visible: root.widgetId !== "stickyNote" && root.widgetId !== "headlines"
        z: 2
    }

    Rectangle {
        id: weatherClockFace
        anchors.right: parent.right
        anchors.rightMargin: root.inset
        anchors.top: header.bottom
        anchors.topMargin: 9 * root.s
        width: 48 * root.s
        height: width
        radius: width / 2
        color: Qt.alpha(Theme.primary, 0.08)
        border.width: 1 * root.s
        border.color: Qt.alpha(Theme.primary, 0.45)
        visible: root.widgetId === "weatherDayClock"
        z: 2

        Rectangle {
            anchors.centerIn: parent
            width: 2 * root.s
            height: parent.height * 0.28
            radius: width / 2
            color: Theme.primary
            y: -parent.height * 0.14
            transformOrigin: Item.Bottom
            rotation: (root.now.getHours() % 12 + root.now.getMinutes() / 60) * 30
        }

        Rectangle {
            anchors.centerIn: parent
            width: 1.5 * root.s
            height: parent.height * 0.38
            radius: width / 2
            color: Theme.onSurface
            y: -parent.height * 0.19
            transformOrigin: Item.Bottom
            rotation: root.now.getMinutes() * 6
        }

        Rectangle {
            anchors.centerIn: parent
            width: 4 * root.s
            height: width
            radius: width / 2
            color: Theme.primary
        }
    }

    Column {
        id: headlinesList
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.leftMargin: root.inset
        anchors.rightMargin: root.inset
        anchors.topMargin: 7 * root.s
        spacing: 5 * root.s
        visible: root.widgetId === "headlines"

        Repeater {
            model: Notifs.groups.slice(0, 3)
            delegate: Column {
                id: headlineEntry
                required property var modelData
                width: headlinesList.width
                spacing: 1 * root.s
                Text {
                    width: parent.width
                    text: headlineEntry.modelData.preview.summary
                    color: Theme.onSurface
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: headlineEntry.modelData.app
                    color: Theme.onSurfaceVariant
                    font.family: Theme.font
                    font.pixelSize: 8 * root.s
                    elide: Text.ElideRight
                }
            }

            Text {
                width: parent.width
                text: "No recent notifications"
                color: Theme.onSurfaceVariant
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                visible: Notifs.groups.length === 0
            }
        }
    }

    Row {
        id: weekdayHeader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.inset
        anchors.rightMargin: root.inset
        anchors.top: detail.bottom
        anchors.topMargin: 5 * root.s
        visible: root.calendarMonthWidget

        Repeater {
            model: ["M", "T", "W", "T", "F", "S", "S"]
            delegate: Text {
                required property string modelData
                width: weekdayHeader.width / 7
                height: 11 * root.s
                text: modelData
                color: Theme.primary
                font.family: Theme.font
                font.pixelSize: 8 * root.s
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    Grid {
        id: monthGrid
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.inset
        anchors.rightMargin: root.inset
        anchors.top: weekdayHeader.bottom
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12 * root.s
        columns: 7
        rows: 6
        visible: root.calendarMonthWidget

        Repeater {
            model: root.calendarDays
            delegate: Rectangle {
                id: dateCell
                required property int modelData
                width: monthGrid.width / 7
                height: monthGrid.height / 6
                radius: 5 * root.s
                color: dateCell.modelData === root.now.getDate()
                    ? Qt.alpha(Theme.primary, 0.24) : "transparent"
                visible: dateCell.modelData > 0

                Text {
                    anchors.centerIn: parent
                    text: dateCell.modelData > 0 ? dateCell.modelData : ""
                    color: dateCell.modelData === root.now.getDate()
                        ? Theme.primary : Theme.onSurfaceVariant
                    font.family: Theme.font
                    font.pixelSize: 8 * root.s
                    font.weight: dateCell.modelData === root.now.getDate()
                        ? Font.Bold : Font.Normal
                }
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.inset
        anchors.bottomMargin: 12 * root.s
        height: 4 * root.s
        radius: height / 2
        color: Qt.alpha(Theme.primary, 0.16)
        anchors.rightMargin: root.isMusic || root.widgetId === "pomodoro"
            ? 82 * root.s : 16 * root.s
        visible: root.progressVisible

        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, root.progress))
            height: parent.height
            radius: parent.radius
            color: Theme.primary
            Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            id: musicSeekArea
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 22 * root.s
            enabled: root.isMusic && root.hasPlayer && root.player.canSeek
                && root.player.positionSupported && Players.lengthSec > 0 && !Players.live
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: function(mouse) {
                if (!root.hasPlayer)
                    return;
                root.player.position = Math.max(0, Math.min(1, mouse.x / width))
                    * Players.lengthSec;
                root.player.positionChanged();
            }
        }
    }

    WaveProgress {
        id: pulseProgress
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.inset
        anchors.rightMargin: 82 * root.s
        anchors.bottomMargin: 6 * root.s
        height: 18 * root.s
        value: root.trackProgress
        actualValue: root.trackProgress
        isPlaying: Players.playing
        lineWidth: 1.5 * root.s
        amplitude: 1.8 * root.s
        wavelength: 20 * root.s
        trackColor: Qt.alpha(Theme.onSurfaceVariant, 0.35)
        fillColor: Theme.primary
        playheadColor: Theme.onSurface
        visible: root.widgetId === "musicPulse"

        MouseArea {
            id: pulseSeekArea
            anchors.fill: parent
            enabled: root.hasPlayer && root.player.canSeek
                && root.player.positionSupported && Players.lengthSec > 0 && !Players.live
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: function(mouse) {
                if (!root.hasPlayer)
                    return;
                root.player.position = Math.max(0, Math.min(1, mouse.x / width))
                    * Players.lengthSec;
                root.player.positionChanged();
            }
        }
    }

    Row {
        id: musicControls
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: root.inset
        anchors.bottomMargin: 8 * root.s
        spacing: 2 * root.s
        visible: root.isMusic
        z: 3

        Repeater {
            model: ["prev", Players.playing ? "pause" : "play", "next"]
            delegate: Item {
                id: musicControl
                required property string modelData
                width: 22 * root.s
                height: 22 * root.s
                opacity: enabled ? 1 : 0.4
                enabled: root.hasPlayer && (musicControl.modelData === "prev"
                    ? root.player.canGoPrevious
                    : musicControl.modelData === "next"
                        ? root.player.canGoNext : root.player.canTogglePlaying)

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: musicControl.modelData === "play" || musicControl.modelData === "pause"
                        ? Theme.primary : Qt.alpha(Theme.onSurface, 0.08)
                }
                GlyphIcon {
                    anchors.centerIn: parent
                    width: 12 * root.s
                    height: width
                    name: musicControl.modelData
                    color: musicControl.modelData === "play" || musicControl.modelData === "pause"
                        ? Theme.onPrimary : Theme.onSurface
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: musicControl.enabled
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (!root.hasPlayer)
                            return;
                        if (musicControl.modelData === "prev")
                            root.player.previous();
                        else if (musicControl.modelData === "next")
                            root.player.next();
                        else
                            root.player.togglePlaying();
                    }
                }
            }
        }
    }

    Rectangle {
        id: timerToggle
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: root.inset
        anchors.bottomMargin: 8 * root.s
        width: 48 * root.s
        height: 22 * root.s
        radius: height / 2
        color: Theme.primary
        visible: root.widgetId === "pomodoro"
        z: 3
        Text {
            anchors.centerIn: parent
            text: DesktopWidgetState.focusTimerRunning ? "PAUSE" : "START"
            color: Theme.onPrimary
            font.family: Theme.font
            font.pixelSize: 8 * root.s
            font.weight: Font.Bold
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: DesktopWidgetState.toggleFocusTimer()
        }
    }

    Row {
        id: forecast
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.inset
        anchors.rightMargin: root.inset
        anchors.bottomMargin: 12 * root.s
        spacing: 5 * root.s
        visible: root.widgetId === "weatherHours" || root.widgetId === "weather"

        Repeater {
            model: root.upcomingHours
            delegate: Column {
                id: forecastCell
                required property var modelData
                width: (forecast.width - 20 * root.s) / 5
                spacing: 2 * root.s
                Text {
                    width: parent.width
                    text: forecastCell.modelData.hour + "h"
                    color: Theme.onSurfaceVariant
                    font.family: Theme.font
                    font.pixelSize: 7 * root.s
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    width: parent.width
                    text: forecastCell.modelData.temp + "°"
                    color: Theme.onSurface
                    font.family: Theme.font
                    font.pixelSize: 8 * root.s
                    horizontalAlignment: Text.AlignHCenter
                }
                Rectangle {
                    width: parent.width * 0.7 * Math.max(0.08, Math.min(1,
                        (forecastCell.modelData.temp + 10) / 40))
                    height: 3 * root.s
                    radius: height / 2
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: Theme.primary
                    opacity: 0.68
                }
                Text {
                    width: parent.width
                    text: forecastCell.modelData.rain + "%"
                    color: Theme.onSurfaceVariant
                    font.family: Theme.font
                    font.pixelSize: 7 * root.s
                    horizontalAlignment: Text.AlignHCenter
                    visible: root.widgetId === "weatherHours"
                }
            }
        }
    }

    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.inset
        anchors.rightMargin: root.inset
        anchors.bottomMargin: 12 * root.s
        spacing: 5 * root.s
        visible: root.widgetId === "sysQuad" || root.widgetId === "sysCores"

        Repeater {
            model: root.widgetId === "sysQuad" ? root.quadMetrics : root.systemMetrics

            delegate: Column {
                id: metricCell
                required property var modelData
                width: (parent.width - 15 * root.s)
                    / (root.widgetId === "sysQuad" ? root.quadMetrics.length : root.systemMetrics.length)
                spacing: 2 * root.s

                Rectangle {
                    width: parent.width
                    height: 18 * root.s
                    radius: 5 * root.s
                    color: Qt.alpha(Theme.primary, 0.14)
                    Rectangle {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        width: parent.width * metricCell.modelData.value / 100
                        height: Math.max(2 * root.s, parent.height * metricCell.modelData.value / 100)
                        radius: parent.radius
                        color: Theme.primary
                    }
                }

                Text {
                    width: parent.width
                    text: metricCell.modelData.label + " " + metricCell.modelData.value + "%"
                    color: Theme.onSurfaceVariant
                    font.family: Theme.font
                    font.pixelSize: 8 * root.s
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    Canvas {
        id: activityRings
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: detail.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.inset
        anchors.rightMargin: root.inset
        anchors.topMargin: 2 * root.s
        anchors.bottomMargin: 11 * root.s
        visible: root.widgetId === "profileRings"
        antialiasing: true

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            var radius = Math.max(5, Math.min(height * 0.34, width / 10));
            for (var i = 0; i < root.ringMetrics.length; i++) {
                var cx = width * (i + 0.5) / root.ringMetrics.length;
                var cy = height * 0.42;
                ctx.beginPath();
                ctx.arc(cx, cy, radius, 0, Math.PI * 2);
                ctx.lineWidth = 4 * root.s;
                ctx.strokeStyle = Qt.alpha(Theme.onSurface, 0.12);
                ctx.stroke();
                ctx.beginPath();
                ctx.arc(cx, cy, radius, -Math.PI / 2,
                    -Math.PI / 2 + Math.PI * 2 * root.ringMetrics[i].value / 100);
                ctx.lineWidth = 4 * root.s;
                ctx.lineCap = "round";
                ctx.strokeStyle = Qt.alpha(Theme.primary, 0.65 + i * 0.15);
                ctx.stroke();
            }
        }
    }

    Row {
        anchors.left: activityRings.left
        anchors.right: activityRings.right
        anchors.bottom: activityRings.bottom
        visible: root.widgetId === "profileRings"

        Repeater {
            model: root.ringMetrics
            delegate: Text {
                required property var modelData
                width: activityRings.width / root.ringMetrics.length
                text: modelData.label + " " + modelData.value + "%"
                color: Theme.onSurfaceVariant
                font.family: Theme.font
                font.pixelSize: 7 * root.s
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    Canvas {
        id: orbitCanvas
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: detail.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.inset
        anchors.rightMargin: root.inset
        anchors.topMargin: 2 * root.s
        anchors.bottomMargin: 8 * root.s
        visible: root.widgetId === "sysOrbit"
        antialiasing: true

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            var metrics = root.systemMetrics;
            var cx = width / 2;
            var cy = height / 2;
            var maxRadius = Math.max(8, Math.min(width * 0.42, height * 0.46));
            for (var i = 0; i < metrics.length; i++) {
                var radius = maxRadius * (i + 1) / metrics.length;
                var angle = (metrics[i].value / 100) * Math.PI * 2 - Math.PI / 2;
                ctx.beginPath();
                ctx.arc(cx, cy, radius, 0, Math.PI * 2);
                ctx.lineWidth = 1 * root.s;
                ctx.strokeStyle = Qt.alpha(Theme.primary, 0.3);
                ctx.stroke();
                ctx.beginPath();
                ctx.arc(cx + Math.cos(angle) * radius, cy + Math.sin(angle) * radius,
                    3 * root.s, 0, Math.PI * 2);
                ctx.fillStyle = Qt.alpha(Theme.primary, 0.6 + i * 0.2);
                ctx.fill();
            }
        }
    }

    Text {
        visible: root.widgetId === "stickyNote"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.margins: 14 * root.s
        anchors.topMargin: 8 * root.s
        text: Flags.desktopWidgetNotes.length > 0
            ? Flags.desktopWidgetNotes : "Add a note in Desktop Widgets settings"
        color: Theme.onSurface
        font.family: Theme.font
        font.pixelSize: 12 * root.s
        wrapMode: Text.WordWrap
        maximumLineCount: 6
    }
}

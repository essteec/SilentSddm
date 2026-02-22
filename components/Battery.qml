import QtQuick
import QtQuick.Controls

IconButton {
    id: batteryButton

    // Battery state
    property int percent: 0
    property bool isCharging: false
    property string batLabel: "?%"

    height: Config.menuAreaButtonsSize * Config.generalScale
    icon: Config.getIcon(Config.batteryIcon)
    iconSize: Config.batteryIconSize
    label: batLabel
    showLabel: true
    contentColor: Config.batteryContentColor
    activeContentColor: Config.batteryActiveContentColor
    backgroundColor: Config.batteryBackgroundColor
    backgroundOpacity: Config.batteryBackgroundOpacity
    activeBackgroundOpacity: Config.batteryActiveBackgroundOpacity
    borderRadius: Config.menuAreaButtonsBorderRadius
    borderSize: Config.batteryBorderSize
    fontFamily: Config.menuAreaButtonsFontFamily
    fontSize: 10
    activeFocusOnTab: false
    focus: false
    tooltipText: "Battery: " + batLabel + (isCharging ? " (charging)" : "")

    function readSysFile(path) {
        try {
            var req = new XMLHttpRequest();
            req.open("GET", "file://" + path, false);
            req.send(null);
            if (req.status === 0 || req.status === 200) {
                return req.responseText.trim();
            }
        } catch (e) {}
        return "";
    }

    function updateBattery() {
        var batPaths = [
            "/sys/class/power_supply/BAT0",
            "/sys/class/power_supply/BAT1",
            "/sys/class/power_supply/BAT2",
            "/sys/class/power_supply/battery",
            "/sys/class/power_supply/BAT"
        ];
        for (var i = 0; i < batPaths.length; i++) {
            var cap = readSysFile(batPaths[i] + "/capacity");
            var parsed = parseInt(cap);
            if (cap !== "" && !isNaN(parsed)) {
                percent = parsed;
                var status = readSysFile(batPaths[i] + "/status");
                isCharging = (status === "Charging" || status === "Full");
                batLabel = percent + (isCharging ? "+" : "") + "%";
                return;
            }
        }
        batLabel = "?%";
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: batteryButton.updateBattery()
    }

    Component.onCompleted: updateBattery()
}

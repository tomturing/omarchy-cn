import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "local.netspeed"

  property int rxRate: 0
  property int txRate: 0
  property real totalDown: 0
  property real totalUp: 0
  property string activeIface: ""
  property bool hasData: false
  property bool compactMode: setting("compact", false)

  function formatSpeed(bytes, compact) {
    if (!bytes || isNaN(bytes) || bytes < 0) {
      return compact ? "0K" : "0.0 KB/s"
    }
    if (compact) {
      if (bytes < 1024) return bytes + "B"
      if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(0) + "K"
      if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + "M"
      return (bytes / (1024 * 1024 * 1024)).toFixed(1) + "G"
    } else {
      if (bytes < 1024) return bytes + " B/s"
      if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB/s"
      if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + " MB/s"
      return (bytes / (1024 * 1024 * 1024)).toFixed(2) + " GB/s"
    }
  }

  function formatBytes(bytes) {
    if (!bytes || isNaN(bytes) || bytes < 0) return "0 B"
    if (bytes < 1024) return bytes + " B"
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB"
    if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + " MB"
    return (bytes / (1024 * 1024 * 1024)).toFixed(2) + " GB"
  }

  readonly property string displayLabel: {
    if (!root.hasData) return "↓ --  ↑ --"
    if (root.vertical) {
      return "↓" + formatSpeed(root.rxRate, true) + "\n↑" + formatSpeed(root.txRate, true)
    }
    return "↓ " + formatSpeed(root.rxRate, root.compactMode) + "  ↑ " + formatSpeed(root.txRate, root.compactMode)
  }

  readonly property string tooltip: {
    if (!root.hasData) return "实时网速: 正在获取数据..."
    return "实时网速监控\n" +
           "网卡接口: " + (root.activeIface || "未知") + "\n" +
           "下载速度: " + formatSpeed(root.rxRate, false) + " (累计: " + formatBytes(root.totalDown) + ")\n" +
           "上传速度: " + formatSpeed(root.txRate, false) + " (累计: " + formatBytes(root.totalUp) + ")\n" +
           "(点击切换精简/详细显示)"
  }

  Process {
    id: speedProc
    command: ["bash", "-c", "exec \"$HOME/.config/omarchy/plugins/local.netspeed/netspeed.sh\""]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        var str = String(line || "").trim()
        if (!str || str.charAt(0) !== '{') return
        try {
          var data = JSON.parse(str)
          root.rxRate = data.down
          root.txRate = data.up
          root.totalDown = data.total_down
          root.totalUp = data.total_up
          root.activeIface = data.iface
          root.hasData = true
        } catch (e) {}
      }
    }
  }

  Timer {
    interval: 2500
    running: !speedProc.running
    repeat: true
    onTriggered: speedProc.running = true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.displayLabel
    fontSize: Style.font.caption
    horizontalMargin: 6
    tooltipText: root.tooltip
    onPressed: function() {
      root.compactMode = !root.compactMode
    }
  }
}

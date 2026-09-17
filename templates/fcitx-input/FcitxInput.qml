import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Shows the active fcitx5 input method on the bar and toggles it on click.
// Reads the current IM with `fcitx5-remote -n` and maps the engine name to a
// short label: keyboard-* layouts read as EN, the common CJK engines read as
// 中 / あ / 한, anything else falls back to its first three letters.
BarWidget {
  id: root
  moduleName: "local.fcitx-input"

  property string imName: ""

  readonly property string imLabel: {
    if (!root.imName) return ""
    if (root.imName.indexOf("keyboard-") === 0) return "EN"
    var map = {
      "rime": "中", "pinyin": "中", "libpinyin": "中", "shuangpin": "中",
      "chewing": "中", "hangul": "한", "mozc": "あ", "anthy": "あ"
    }
    if (map[root.imName] !== undefined) return map[root.imName]
    return root.imName.substring(0, 3).toUpperCase()
  }

  function refresh() {
    if (!queryProc.running) queryProc.running = true
  }

  Component.onCompleted: refresh()
  Component.onDestruction: {
    queryProc.running = false
    toggleProc.running = false
  }

  Process {
    id: queryProc
    command: ["fcitx5-remote", "-n"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.imName = (text || "").trim()
    }
  }

  // Poll: fcitx5-remote is cheap, poll every 1.5s to balance responsiveness and CPU load
  Timer {
    interval: 1500
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  visible: imLabel !== ""
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.imLabel
    fontSize: Style.font.caption
    horizontalMargin: 6
    tooltipText: root.imName
    onPressed: function() {
      if (!toggleProc.running) toggleProc.running = true
    }
  }

  // `fcitx5-remote` with no args cycles to the next input method.
  Process {
    id: toggleProc
    command: ["fcitx5-remote"]
  }
}

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.qfield
import org.qgis
import Theme

Item {
  id: plugin

  property var mainWindow: iface.mainWindow()
  property var mapCanvas: iface.mapCanvas()

  // ── state ────────────────────────────────────────────────────────────────────
  property var currentLayer: null
  property string currentFieldName: ""
  property bool currentFieldIsText: true
  property var selectedValues: []
  property bool filterEnabled: true

  // ComboBox models — plain JS arrays, QfComboBox handles them directly
  property var layerNames: []
  property var layerMap: ({})      // name → QgsVectorLayer
  property var fieldNames: []

  // long-press guard (onPressAndHold is unreliable on QfToolButton in QField 4.x)
  property bool wasLongPress: false

  Component.onCompleted: {
    iface.addItemToPluginsToolbar(pluginButton)
  }

  ListModel { id: valueModel }

  // ── toolbar button ──────────────────────────────────────────────────────────
  QfToolButton {
    id: pluginButton
    iconSource: 'icon.svg'
    iconColor: (filterEnabled && selectedValues.length > 0)
      ? Theme.mainColor : Theme.toolbarTextColor
    bgcolor: Theme.darkGray
    round: true

    onClicked: {
      if (!plugin.wasLongPress) {
        refreshLayers()
        filterPanel.visible = true
      }
      plugin.wasLongPress = false
    }
    onPressed:  holdTimer.start()
    onReleased: holdTimer.stop()
  }

  Timer {
    id: holdTimer
    interval: 600
    repeat: false
    onTriggered: {
      plugin.wasLongPress = true
      clearFilter()
    }
  }

  // ── layer / field / value loading ────────────────────────────────────────────
  function refreshLayers() {
    var prevName = currentLayer ? currentLayer.name : ""
    var lm = {}
    var names = []

    // ProjectUtils.mapLayers is the correct QField 4.x API for all project layers
    var layers = ProjectUtils.mapLayers(qgisProject)
    for (var id in layers) {
      var lyr = layers[id]
      if (lyr && lyr.type === 0) {   // 0 = QgsMapLayerType::VectorLayer
        names.push(lyr.name)
        lm[lyr.name] = lyr
      }
    }
    names.sort()
    layerMap   = lm
    layerNames = names

    var restoreIdx = names.indexOf(prevName)
    var targetIdx  = restoreIdx >= 0 ? restoreIdx : (names.length > 0 ? 0 : -1)
    layerCombo.currentIndex = targetIdx
    // Qt.callLater defers until after QML bindings settle; onActivated won't
    // fire for programmatic index changes so we trigger selectLayer explicitly.
    Qt.callLater(function() {
      if (layerCombo.currentIndex >= 0 && layerNames.length > 0)
        selectLayer(layerNames[layerCombo.currentIndex])
    })
  }

  function selectLayer(name) {
    var lyr = layerMap[name]
    if (!lyr) return
    currentLayer      = lyr
    currentFieldName  = ""
    selectedValues    = []
    valueModel.clear()

    // fields.names is a Q_PROPERTY on QgsFields (Q_GADGET) → plain JS string array
    var f = lyr.fields
    var names = (f && f.names) ? f.names.slice() : []
    names.sort()
    fieldNames = names
    fieldCombo.currentIndex = -1
  }

  function selectField(name) {
    if (!currentLayer || !name) return
    currentFieldName = name
    selectedValues   = []
    valueModel.clear()

    // Detect string vs numeric via fields.at() which is Q_INVOKABLE on QgsFields
    currentFieldIsText = true
    try {
      var allNames = currentLayer.fields.names || []
      for (var i = 0; i < allNames.length; i++) {
        if (allNames[i] === name) {
          var f = currentLayer.fields.at(i)
          // QVariant::String = 10, QMetaType::QString = 2014
          if (f) currentFieldIsText = (f.type === 10 || f.type === 2014)
          break
        }
      }
    } catch(_) {}

    // Map logical field position to the layer's physical attribute index
    var logicalIdx = -1
    var allNames2  = currentLayer.fields.names || []
    for (var j = 0; j < allNames2.length; j++) {
      if (allNames2[j] === name) { logicalIdx = j; break }
    }
    var attrs   = []
    try { attrs = currentLayer.attributeList() || [] } catch(_) {}
    var realIdx = (logicalIdx >= 0 && logicalIdx < attrs.length)
      ? attrs[logicalIdx] : logicalIdx

    // Collect unique values with LayerUtils feature iterator (confirmed QField 4.x API)
    var seen = {}
    var arr  = []
    try {
      var it    = LayerUtils.createFeatureIteratorFromExpression(currentLayer, "1=1")
      var count = 0
      while (it.hasNext() && count < 10000) {
        var feat = it.next()
        var val  = feat.attribute(realIdx)
        if (val === undefined) val = feat.attribute(name)  // fallback to name lookup
        if (val !== null && val !== undefined) {
          var s = String(val).trim()
          if (s !== "" && s !== "NULL" && !seen[s]) { seen[s] = true; arr.push(s) }
        }
        count++
      }
    } catch(e) {
      mainWindow.displayToast(qsTr("Error reading values: ") + e)
    }

    arr.sort(function(a, b) {
      return a.localeCompare(b, undefined, { sensitivity: 'base' })
    })
    for (var m = 0; m < arr.length; m++) {
      valueModel.append({ val: arr[m], checked: false })
    }
  }

  // ── filter logic ─────────────────────────────────────────────────────────────
  function toggleValue(val, on) {
    var arr = selectedValues.slice()
    var pos = arr.indexOf(val)
    if (on && pos < 0)   arr.push(val)
    else if (!on && pos >= 0) arr.splice(pos, 1)
    selectedValues = arr
    applyFilter()
  }

  function buildExpr() {
    if (selectedValues.length === 0) return ""
    var fn = currentFieldName
    if (currentFieldIsText) {
      var quoted = selectedValues.map(function(v) {
        return "'" + v.replace(/'/g, "''") + "'"
      })
      return '"' + fn + '" IN (' + quoted.join(', ') + ')'
    }
    return '"' + fn + '" IN (' + selectedValues.join(', ') + ')'
  }

  function applyFilter() {
    if (!currentLayer) return
    var expr = (filterEnabled && selectedValues.length > 0) ? buildExpr() : ""

    // subsetString is a settable Q_PROPERTY in QField 4.x (not setSubsetString())
    currentLayer.subsetString = expr
    currentLayer.removeSelection()
    if (expr) currentLayer.selectByExpression(expr)
    currentLayer.triggerRepaint()
    mapCanvas.refresh()
  }

  function clearFilter() {
    // Clear subset string and selection on every vector layer
    var layers = ProjectUtils.mapLayers(qgisProject)
    for (var id in layers) {
      var lyr = layers[id]
      if (lyr && lyr.type === 0) {
        try { lyr.subsetString = ""; lyr.removeSelection(); lyr.triggerRepaint() } catch(_) {}
      }
    }
    selectedValues = []
    filterEnabled  = true
    filterToggle.checked = true
    for (var i = 0; i < valueModel.count; i++) {
      valueModel.setProperty(i, "checked", false)
    }
    mapCanvas.refresh()
    mainWindow.displayToast(qsTr("Filter cleared"))
  }

  // ── panel ─────────────────────────────────────────────────────────────────────
  Item {
    id: filterPanel
    visible: false
    parent: mainWindow.contentItem
    anchors.fill: parent
    z: 1000

    // scrim
    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.45)
      MouseArea { anchors.fill: parent; onClicked: filterPanel.visible = false }
    }

    // sheet
    Rectangle {
      id: sheet
      width:  Math.min(460, parent.width - 24)
      height: parent.height * 0.88
      anchors.centerIn: parent
      radius: 14
      color:  Theme.mainBackgroundColor
      MouseArea { anchors.fill: parent; onClicked: {} }  // absorb scrim clicks

      ColumnLayout {
        anchors { fill: parent; margins: 16 }
        spacing: 10

        // ── header ────────────────────────────────────────────────────────────
        RowLayout {
          Layout.fillWidth: true
          Text {
            text: qsTr("Feature Filter")
            font { pixelSize: 20; bold: true }
            color: Theme.mainTextColor
            Layout.fillWidth: true
          }
          Rectangle {
            width: 36; height: 36; radius: 18
            color: Qt.rgba(128, 128, 128, 0.18)
            Text { anchors.centerIn: parent; text: "✕"; font.pixelSize: 16; color: Theme.mainTextColor }
            MouseArea { anchors.fill: parent; onClicked: filterPanel.visible = false }
          }
        }

        // ── layer picker ──────────────────────────────────────────────────────
        Text { text: qsTr("Layer"); font.pixelSize: 12; color: Theme.secondaryTextColor }
        QfComboBox {
          id: layerCombo
          Layout.fillWidth: true
          model: layerNames
          // onActivated fires only on user interaction, not programmatic index changes
          onActivated: {
            if (index >= 0 && index < layerNames.length)
              selectLayer(layerNames[index])
          }
        }

        // ── field picker ──────────────────────────────────────────────────────
        Text { text: qsTr("Field"); font.pixelSize: 12; color: Theme.secondaryTextColor }
        QfComboBox {
          id: fieldCombo
          Layout.fillWidth: true
          model: fieldNames
          onActivated: {
            if (index >= 0 && index < fieldNames.length)
              selectField(fieldNames[index])
          }
        }

        // ── filter toggle ─────────────────────────────────────────────────────
        RowLayout {
          spacing: 0
          CheckBox {
            id: filterToggle
            checked: filterEnabled
            onCheckedChanged: { filterEnabled = checked; applyFilter() }
          }
          Text { text: qsTr("Filter active"); color: Theme.mainTextColor; font.pixelSize: 14 }
        }

        // ── search ────────────────────────────────────────────────────────────
        TextField {
          id: searchField
          Layout.fillWidth: true
          placeholderText: qsTr("Search values…")
          font.pixelSize: 14
          leftPadding: 10
        }

        // ── values list ───────────────────────────────────────────────────────
        Rectangle {
          Layout.fillWidth: true
          Layout.fillHeight: true
          color:  "transparent"
          border { color: Qt.rgba(128, 128, 128, 0.22); width: 1 }
          radius: 6
          clip:   true

          // placeholder when empty
          Text {
            anchors.centerIn: parent
            visible: valueModel.count === 0
            text: currentFieldName === ""
              ? qsTr("Select a layer and a field")
              : qsTr("No values found")
            color: Theme.secondaryTextColor
            font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter
            width: parent.width - 32
            wrapMode: Text.WordWrap
          }

          ListView {
            id: valueList
            anchors { fill: parent; margins: 2 }
            model: valueModel
            clip:  true
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Rectangle {
              property bool matchesSearch: searchField.text === ""
                || model.val.toLowerCase().indexOf(searchField.text.toLowerCase()) >= 0
              width:   valueList.width
              height:  matchesSearch ? 46 : 0
              visible: matchesSearch
              color: model.checked
                ? Qt.rgba(0.1, 0.65, 0.1, 0.15)
                : (index % 2 === 0 ? "transparent" : Qt.rgba(128, 128, 128, 0.06))

              RowLayout {
                anchors { fill: parent; leftMargin: 4; rightMargin: 8 }
                spacing: 2

                CheckBox {
                  checked: model.checked
                  onClicked: {
                    valueModel.setProperty(index, "checked", checked)
                    toggleValue(model.val, checked)
                  }
                }

                Text {
                  text: model.val
                  color: Theme.mainTextColor
                  font.pixelSize: 14
                  Layout.fillWidth: true
                  elide: Text.ElideRight
                  verticalAlignment: Text.AlignVCenter
                }
              }
            }
          }
        }

        // ── footer ────────────────────────────────────────────────────────────
        RowLayout {
          Layout.fillWidth: true
          spacing: 8
          Button {
            text: qsTr("Clear All")
            Layout.fillWidth: true
            onClicked: clearFilter()
          }
          Button {
            text: qsTr("Close")
            Layout.fillWidth: true
            onClicked: filterPanel.visible = false
          }
        }
      }
    }
  }
}

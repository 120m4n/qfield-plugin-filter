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

  // ── filter state ────────────────────────────────────────────────────────────
  property var layerList: []          // parallel JS array for layer objects
  property var currentLayer: null
  property var fieldList: []          // [{name, index, isText}]
  property int currentFieldIndex: -1
  property string currentFieldName: ""
  property bool currentFieldIsText: true
  property var selectedValues: []
  property bool filterEnabled: true

  Component.onCompleted: {
    iface.addItemToPluginsToolbar(pluginButton)
  }

  ListModel { id: layerModel }
  ListModel { id: fieldModel }
  ListModel { id: valueModel }

  // ── toolbar button ──────────────────────────────────────────────────────────
  QfToolButton {
    id: pluginButton
    iconSource: 'icon.svg'
    iconColor: (filterEnabled && selectedValues.length > 0)
      ? Theme.mainColor
      : Theme.toolbarTextColor
    bgcolor: Theme.darkGray
    round: true

    onClicked: {
      refreshLayerList()
      filterPanel.visible = true
    }

    onPressAndHold: {
      clearFilter()
    }
  }

  // ── helpers ─────────────────────────────────────────────────────────────────
  function refreshLayerList() {
    var prevId = currentLayer ? currentLayer.id : ""
    layerList = []
    layerModel.clear()

    var layers = mapCanvas.mapSettings.layers
    for (var i = 0; i < layers.length; i++) {
      var lyr = layers[i]
      if (lyr && lyr.type === 0) {   // 0 = QgsMapLayerType::VectorLayer
        layerList.push(lyr)
        layerModel.append({ name: lyr.name })
      }
    }

    if (layerList.length === 0) return

    var idx = 0
    if (prevId !== "") {
      for (var j = 0; j < layerList.length; j++) {
        if (layerList[j].id === prevId) { idx = j; break }
      }
    }
    layerCombo.currentIndex = idx
    // Qt.callLater defers until after the model binding has settled,
    // since onActivated won't fire for programmatic index changes.
    Qt.callLater(function() { selectLayer(layerCombo.currentIndex) })
  }

  function selectLayer(idx) {
    if (idx < 0 || idx >= layerList.length) return
    currentLayer = layerList[idx]
    currentFieldIndex = -1
    currentFieldName = ""
    selectedValues = []
    fieldList = []
    fieldModel.clear()
    valueModel.clear()

    var fields = currentLayer.fields()
    // fields.count is a Q_PROPERTY on QgsFields (Q_GADGET) — do NOT call as fields.count()
    var n = fields.count
    for (var i = 0; i < n; i++) {
      var f = fields.at(i)
      // f.type and f.name are Q_PROPERTY values; QVariant::String=10, QMetaType::QString=2014
      var isText = (f.type === 10 || f.type === 2014)
      fieldList.push({ name: f.name, index: i, isText: isText })
      fieldModel.append({ name: f.name })
    }
    fieldCombo.currentIndex = -1
  }

  function selectField(idx) {
    if (idx < 0 || idx >= fieldList.length) return
    var fi = fieldList[idx]
    currentFieldIndex = fi.index
    currentFieldName = fi.name
    currentFieldIsText = fi.isText
    selectedValues = []
    valueModel.clear()

    // uniqueValues() is Q_INVOKABLE and returns a QVariantList mapped to a JS array
    var vals = currentLayer.uniqueValues(currentFieldIndex) || []
    var arr = []
    for (var k = 0; k < vals.length; k++) {
      var v = vals[k]
      if (v !== null && v !== undefined && String(v) !== "" && String(v) !== "NULL") {
        arr.push(String(v))
      }
    }
    arr.sort(function(a, b) {
      return a.localeCompare(b, undefined, { sensitivity: 'base' })
    })
    for (var m = 0; m < arr.length; m++) {
      valueModel.append({ val: arr[m], checked: false })
    }
  }

  function toggleValue(val, on) {
    var arr = selectedValues.slice()
    var pos = arr.indexOf(val)
    if (on && pos < 0) arr.push(val)
    else if (!on && pos >= 0) arr.splice(pos, 1)
    selectedValues = arr
    applyFilter()
  }

  function applyFilter() {
    if (!currentLayer) return
    if (!filterEnabled || selectedValues.length === 0) {
      currentLayer.setSubsetString("")
    } else {
      var fn = currentFieldName
      var isText = currentFieldIsText
      var parts = selectedValues.map(function(v) {
        return isText
          ? '"' + fn + '" = \'' + v.replace(/'/g, "''") + '\''
          : '"' + fn + '" = ' + v
      })
      currentLayer.setSubsetString(parts.join(' OR '))
    }
    mapCanvas.refresh()
  }

  function clearFilter() {
    selectedValues = []
    filterEnabled = true
    filterToggle.checked = true
    for (var i = 0; i < valueModel.count; i++) {
      valueModel.setProperty(i, "checked", false)
    }
    if (currentLayer) {
      currentLayer.setSubsetString("")
      mapCanvas.refresh()
    }
    mainWindow.displayToast(qsTr("Filter cleared"))
  }

  // ── filter panel ────────────────────────────────────────────────────────────
  Item {
    id: filterPanel
    visible: false
    parent: mainWindow.contentItem
    anchors.fill: parent
    z: 1000

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.45)
      MouseArea {
        anchors.fill: parent
        onClicked: filterPanel.visible = false
      }
    }

    Rectangle {
      id: sheet
      width: Math.min(460, parent.width - 24)
      height: parent.height * 0.88
      anchors.centerIn: parent
      radius: 14
      color: Theme.mainBackgroundColor
      MouseArea { anchors.fill: parent; onClicked: {} }  // block scrim

      ColumnLayout {
        anchors { fill: parent; margins: 16 }
        spacing: 10

        // header
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
            Text {
              anchors.centerIn: parent
              text: "✕"
              font.pixelSize: 16
              color: Theme.mainTextColor
            }
            MouseArea { anchors.fill: parent; onClicked: filterPanel.visible = false }
          }
        }

        // layer picker
        Text { text: qsTr("Layer"); font.pixelSize: 12; color: Theme.secondaryTextColor }
        ComboBox {
          id: layerCombo
          Layout.fillWidth: true
          model: layerModel
          textRole: "name"
          // onActivated fires only on explicit user interaction, not on programmatic changes
          onActivated: selectLayer(index)
        }

        // field picker
        Text { text: qsTr("Field"); font.pixelSize: 12; color: Theme.secondaryTextColor }
        ComboBox {
          id: fieldCombo
          Layout.fillWidth: true
          model: fieldModel
          textRole: "name"
          onActivated: selectField(index)
        }

        // filter enabled toggle
        RowLayout {
          spacing: 0
          CheckBox {
            id: filterToggle
            checked: filterEnabled
            onCheckedChanged: {
              filterEnabled = checked
              applyFilter()
            }
          }
          Text {
            text: qsTr("Filter active")
            color: Theme.mainTextColor
            font.pixelSize: 14
          }
        }

        // search box
        TextField {
          id: searchField
          Layout.fillWidth: true
          placeholderText: qsTr("Search values…")
          font.pixelSize: 14
          leftPadding: 10
        }

        // values list
        Rectangle {
          Layout.fillWidth: true
          Layout.fillHeight: true
          color: "transparent"
          border { color: Qt.rgba(128, 128, 128, 0.22); width: 1 }
          radius: 6
          clip: true

          ListView {
            id: valueList
            anchors { fill: parent; margins: 2 }
            model: valueModel
            clip: true
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Rectangle {
              property bool matchesSearch: searchField.text === ""
                || model.val.toLowerCase().indexOf(searchField.text.toLowerCase()) >= 0
              width: valueList.width
              height: matchesSearch ? 46 : 0
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

        // footer
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

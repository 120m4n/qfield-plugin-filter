# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a minimal QField plugin template by OPENGIS.ch. QField is a mobile GIS application built on QGIS. Plugins are written in **QML** (Qt Markup Language) — no compilation required.

The example plugin adds a toolbar button that reads the device's GPS position and displays it as a toast notification.

## Plugin Structure

QField plugins consist of exactly:
- `metadata.txt` — plugin manifest (name, version, icon, author)
- `main.qml` — plugin logic and UI
- `icon.svg` — toolbar button icon

## Deployment & Testing

There is no build system. To test changes, copy the plugin directory to QField's plugin folder and (re)launch QField:

- **Android/iOS**: copy to QField's plugin directory via the app's file manager or adb
- **Desktop QField**: typically `~/.local/share/QField/plugins/<plugin-name>/`

Testing is manual: enable GPS (or a simulator), tap the toolbar button, verify the toast appears with lat/lon.

## Architecture

`main.qml` exposes two injected properties that QField sets at load time:

| Property | Type | Purpose |
|---|---|---|
| `mainWindow` | QField window | Used to show toast messages via `mainWindow.displayToast()` |
| `positionSource` | GNSS source | Provides `active`, `position.latitudeValid`, `position.longitudeValid`, `position.coordinate` |

`Component.onCompleted` calls `iface.addItemToPluginsToolbar(pluginButton)` to register the button. The `iface` global is QField's plugin interface — it also exposes `iface.mainWindow()` and `iface.findItemByObjectName()` for accessing other QField internals.

QML imports used:
- `org.qfield` — `QfToolButton`, `Theme`, `iface`
- `org.qgis` — QGIS core types

## Extending the Template

To add new UI panels or dialogs, create additional `.qml` files and instantiate them inside `main.qml`. All QField-specific components (`QfToolButton`, `Theme`, etc.) are available through the `org.qfield` module without any extra setup.

# qfield-plugin-filter

A QField plugin that adds an interactive feature filter panel to the map toolbar. It lets field users filter any vector layer by selecting values from a chosen field — without writing QGIS expressions by hand.

## Features

- **Toolbar button** — tap to open the filter panel; **long-press (600 ms) to clear all active filters** across every vector layer.
- **Layer picker** — lists all vector layers in the current QGIS project.
- **Field picker** — lists all fields of the selected layer, sorted alphabetically.
- **Value list** — scans up to 10 000 features and shows unique, non-null values as checkboxes. Supports both text and numeric fields.
- **Multi-select** — choose one or more values; the filter is applied immediately as an `IN (…)` expression via `subsetString`.
- **Search box** — filter the value list in real time to find values quickly.
- **Filter toggle** — enable/disable the active filter without losing your selection.
- **Clear All** — removes the subset string and selection from every vector layer and resets the panel.

The toolbar button icon changes color (to the QField main color) whenever a filter is active, giving instant visual feedback.

## How it works

1. Tap the toolbar button → the filter panel slides open.
2. Select a **Layer** from the drop-down.
3. Select a **Field** — unique values are loaded automatically.
4. Check one or more values → the layer is filtered on the map in real time.
5. Use the **search box** to narrow down long value lists.
6. Toggle **"Filter active"** to temporarily suspend the filter.
7. Tap **Clear All** (or long-press the toolbar button) to remove all filters.

## Installation

Copy the plugin directory to QField's plugin folder and relaunch QField:

| Platform | Path |
|---|---|
| Desktop | `~/.local/share/QField/plugins/<plugin-name>/` |
| Android / iOS | use the app's file manager or `adb push` |

Enable the plugin from **QField → Settings → Plugins**.

## Plugin structure

| File | Purpose |
|---|---|
| `main.qml` | Plugin logic and UI |
| `icon.svg` | Toolbar button icon |
| `metadata.txt` | Plugin manifest (name, version, author) |

## Credits

The idea and original implementation concept are based on the work of **woupss** in the [Qfield-filter-plugin](https://github.com/woupss/Qfield-filter-plugin) repository.

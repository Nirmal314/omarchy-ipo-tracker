# IPO Tracker

An Omarchy bar widget that tracks active Indian mainboard IPOs: grey market premium (GMP), daily GMP history, subscription numbers, price bands, lot sizes, and the key dates between open and listing. It shows a single pill in the bar with the Lucide chart-line icon, and clicking it opens a panel with every IPO currently open for bidding or coming up.

The data comes from [ipowatch.in](https://ipowatch.in), which is public and needs no API key. SME and NSE-evolved issues are filtered out, so the pill only counts mainboard IPOs.

## Keyboard shortcuts

| Key | Action |
| --- | --- |
| `/` | Focus the search field, keeping the current text selected |
| `⌫` / `Backspace` | Clear the search field |
| `Esc` | Clear the search and exit search mode (press again to close the panel) |
| `↑` `↓` / `j` `k` | Move focus between IPO cards |
| `↵` / `Enter` | Expand or collapse the focused card |
| `Tab` / `Shift+Tab` | Cycle sort mode (Default → GMP % → Close date) |
| `R` / right- or middle-click | Refresh data immediately |

### Optional: open the panel from anywhere with `Super` + `I`

The panel is not bound to a global key by default, but it exposes an IPC
`toggle` method, so you can wire it up yourself in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + I", "IPO tracker", "omarchy-shell shell toggle archer-nemo.ipo-tracker")
```

Before adding it, check `omarchy menu keybindings --print`; if `SUPER + I`
is already taken you must `hl.unbind("SUPER + I")` first — say what it was
bound to. Then validate with `hyprctl reload` and `hyprctl configerrors`.

## Features

- **GMP at a glance**: the pill shows the next-ish IPO summary; each card shows band, lot, and minimum investment plus the current GMP and its day-over-day trend.
- **Daily GMP sparkline**: hover the bars in a card to read each day's GMP and the change since the previous day.
- **Subscriptions**: QIB / NII / Retail / Total subscription bars for live IPOs, colored once a category crosses 1x.
- **Key dates**: open, close, allotment, refunds, demat credit, and listing date, plus RHP links when a card is expanded.
- **Search and sort**: `/` focuses search, `Tab` cycles sort modes (default / GMP % / close date), `↵` expands the focused card.
- **Refresh**: `R` or middle-click refreshes; the shell also refreshes automatically, every 10 minutes by default.

## Requirements

- Omarchy with the Quickshell shell
- `bash`, `python3`, and `curl` (all present on a stock Omarchy install)

## How it works

The widget runs its bundled `collector.sh`, which delegates to `collector.py`. On each refresh the collector:

1. Pulls the GMP page and the subscription status page from ipowatch.in.
2. Fetches the individual IPO and GMP-history pages (threaded, 4 at a time) to get exact bands, lot sizes, key dates, RHP/DRHP links, and the daily GMP series.
3. Drops SME issues, merging everything into a single JSON object.
4. Prints that JSON to stdout, where `Service.qml` parses it and feeds `Panel.qml`.

Nothing is stored outside the cache under `~/.local/state/omarchy/ipo-tracker/`. The detail cache is valid for two hours, and the last snapshot is reused if the network is unreachable, so the widget keeps working offline with a "showing last snapshot" note.

## Usage

Click the pill to open the panel. The bar pill is click-only; open/upcoming state and DnD / screen-record / weather widgets share the center section unchanged.

Live IPOs are listed under a "Now bidding" header, upcoming ones under "Upcoming". Expanded cards show the subscription bars, the key-date grid, and a link to the IPO's prospectus (RHP/DRHP).

## Configuration

The refresh interval is a plugin setting, defaulting to 600 seconds. It lives under the widget's settings block in `~/.config/omarchy/shell.json`, for example:

```json
{
  "id": "archer-nemo.ipo-tracker",
  "refreshIntervalSec": 300
}
```

Values are clamped to 60–86400 seconds. The layout entry itself only needs the `id`; the rest is optional.

## Installation

```sh
omarchy plugin add https://github.com/Nirmal314/omarchy-ipo-tracker --enable
omarchy bar move archer-nemo.ipo-tracker --section center
```

Remove the widget with `omarchy plugin remove archer-nemo.ipo-tracker`.

## Troubleshooting

### The pill is missing from the bar

Confirm the plugin ID lines up: the manifest declares `id` `"archer-nemo.ipo-tracker"`, and `~/.config/omarchy/shell.json` must reference that same id in `bar.layout`. A mismatch (for example an entry using the folder name `omarchy-ipo-tracker`) means the shell cannot resolve the widget.

After fixing the id, rescan so the shell notices the plugin folder:

```sh
omarchy-shell shell rescanPlugins
```

### The pill shows but no data appears

Check the widget's error line inside the open panel. Common causes: no network (the collector falls back to the cached snapshot), or `python3`/`curl` missing. The collector can be run by hand to see its raw output and exit status:

```sh
~/.config/omarchy/plugins/omarchy-ipo-tracker/bin/collector.sh
```

Saved edits under `~/.config/omarchy/plugins/` reload automatically. If they do not, force a rescan with `omarchy-shell shell rescanPlugins` or restart the shell with `omarchy restart shell`.

## Security and system access

Omarchy plugins run unsandboxed with your user permissions, so review the code before installing it. This plugin:

- Makes plain HTTPS requests only to ipowatch.in, with no API key and no telemetry.
- Reads only its own cache under `~/.local/state/omarchy/ipo-tracker/`.
- Writes that cache only, and only while refreshing.
- Runs no elevated commands and changes nothing else on the system.

## License

MIT, per the plugin manifest.
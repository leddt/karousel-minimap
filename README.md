# Karousel Mini-map

> **PROTOTYPE — USE AT YOUR OWN RISK**
>
> This project is an **experimental prototype**, not a finished product.
> It exists to explore a Karousel layout mini-map on Plasma. Expect rough
> edges, breaking changes, incomplete error handling, and possible desktop
> instability.
>
> There is **no support commitment**, no compatibility guarantee, and no
> warranty of any kind. If you install or run this software, you do so
> entirely **at your own risk**. The authors are not responsible for data
> loss, session crashes, broken panels, or any other damage that may result.
>
> Do **not** treat this as production-ready software.

Plasma 6 panel widget (and a small standalone PyQt demo) that visualizes
[Karousel](https://github.com/peterfajdiga/karousel)’s **logical** tiling
layout. It talks to a forked Karousel build that exports layout JSON over
D-Bus (`org.kde.karousel`).

## Status

| Item | Reality |
| --- | --- |
| Maturity | Prototype / proof of concept |
| Stability | Untested outside one developer desktop |
| Support | None — issues may go unanswered |
| API / D-Bus shape | May change without notice |
| Upstream Karousel | Requires a **fork** with layout D-Bus export (not stock Karousel) |

If you need a reliable daily driver, wait until this is no longer labeled a
prototype — or fork it and harden it yourself.

## What it does

- Shows Karousel columns and tiled windows in a compact panel mini-map
- Highlights focus and (roughly) the scroll viewport
- Click a tile to try activating that window via TaskManager
- Uses a small shared D-Bus bus process so Karousel can push layout updates
  and multiple clients can read them

## Requirements

- KDE Plasma 6 / KWin Wayland (developed on that stack)
- A Karousel build that publishes layouts to `org.kde.karousel` (e.g. the
  `feature/layout-dbus-export` work on a personal fork)
- Python 3 with `dbus-python` and PyGObject (for the layout bus)
- Optional standalone window: PyQt6

## Install the Plasma widget (prototype)

```bash
./plasmoid/install.sh
```

Then: right-click panel → **Add Widgets** → **Karousel Mini-map**.

Or preview:

```bash
plasmawindowed org.leddt.karousel.minimap
```

The install script also enables a user systemd unit
`karousel-layout-bus.service` that owns `org.kde.karousel`.

### Reloading after code changes (no logout)

Removing and re-adding the widget often **does not** pick up QML changes
because Plasma caches compiled QML. You do **not** need to log out.

```bash
./plasmoid/reload.sh
```

That upgrades the package, clears `~/.cache/plasmashell/qmlcache`, and calls
`refreshCurrentShell` (falls back to restarting `plasma-plasmashell`).

If the soft refresh is not enough:

```bash
rm -rf ~/.cache/plasmashell/qmlcache
systemctl --user restart plasma-plasmashell
```

That restarts the shell only (panels/desktop redraw; open apps usually stay).

## Standalone PyQt window (optional)

```bash
# Live (needs the layout bus + Karousel export)
python3 run.py

# Synthetic demo (no Karousel)
python3 run.py --demo
```

## Architecture (why a “bus” exists)

KWin scripts can call D-Bus methods but do not easily register a service.
Karousel therefore **pushes** layout JSON into a small daemon that owns
`org.kde.karousel`. Clients (plasmoid, `run.py`) call `GetLayout` or watch
`LayoutChanged`.

Only one process can own the bus **name**; many clients can read from it.

## License

MIT — see [LICENSE](LICENSE).

Again: the software is provided **“AS IS”**, without warranty. **Use at your
own risk.**

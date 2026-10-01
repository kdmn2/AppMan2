# AppMan2

**AppMan2** is a maintained fork of [**AppMan**](https://github.com/ivan-hc/AppMan),
a command line utility to install, update and manage AppImages and other
portable programs for GNU/Linux using an AUR-style database of shell scripts.

AppMan2 is a **separate project** from AppMan with its own repository identity
and its own self-update source, while staying **fully compatible** with AppMan's
existing configuration, application metadata and installed applications.

> **Critical distinction:** AppMan2 is updated **exclusively from the AppMan2
> repository**. It never updates itself from `ivan-hc/AppMan` or `ivan-hc/AM`.

## The two update systems

```
 AppMan2
    │
    ├── self-update  ──────►  AppMan2 GitHub repository   (APPMAN2_REPO)
    │
    └── manages AppImages ─►  existing AppMan/AM app database + per-app
                              AM-updater scripts
```

* **AppMan2 itself** is updated from the AppMan2 repository.
* **Applications managed by AppMan2** are updated with the exact same
  mechanisms and sources as the original AppMan — nothing about application
  updates changed.

## Features (in addition to everything AppMan already does)

* **Independent self-update** — AppMan2 updates itself from its own
  repository, never from `ivan-hc/AppMan` (see
  [docs/APPMAN2-SELF-UPDATE.md](docs/APPMAN2-SELF-UPDATE.md)).
* **Stalled-download protection** — downloads that stop making progress are
  dropped after a timeout, partial files are cleaned up, slow-but-progressing
  downloads are never touched (see
  [docs/STALLED-DOWNLOADS.md](docs/STALLED-DOWNLOADS.md)).
* **Honest update reporting** — apps that are merely *checked* are never
  reported as *updated*; every result (updated / already up to date / failed /
  skipped / unsupported) is tracked and summarized (see
  [docs/UPDATE-REPORTING.md](docs/UPDATE-REPORTING.md)).
* **Real automatic AppImage updates** — applications that support AppImage
  delta updates (embedded update information / `.zsync`) are actually updated,
  including apps installed without an `AM-updater` (see
  [docs/AUTO-UPDATE-APPS.md](docs/AUTO-UPDATE-APPS.md)).

## Installation

Requires `bash`, `wget` **or** `curl`, and GNU coreutils (AppMan2 can fetch
missing optional tools automatically, exactly like AppMan).

### From this repository

```bash
git clone https://github.com/kdmn2/AppMan2.git
cd AppMan2
./INSTALL
```

`./INSTALL` installs AppMan2 as **`appman2`** so it can coexist with the
original AppMan (it never overwrites an existing `appman`). If you really
want to replace the original AppMan instead, pass the name explicitly:

```bash
./INSTALL appman
```

or, manually:

```bash
mkdir -p ~/.local/bin
cp ./appman ~/.local/bin/appman2     # NOTE: appman2, not appman
chmod +x ~/.local/bin/appman2
```

> `APPMAN2_REPO` in the `appman` script is pre-configured to this repository
> (`https://raw.githubusercontent.com/kdmn2/AppMan2/main`), which is where
> AppMan2 updates **itself** from. If you build your own fork, edit it to point
> at your repository; until it points at a real AppMan2 repository,
> `appman -s`/`appman -u` will warn and refuse to self-update rather than fall
> back to the original AppMan repository.

## Quick start

```bash
appman -h                    # help
appman -i firefox            # install an app (local, AppMan-style)
appman -f                    # list installed apps
appman -u                    # update apps AND AppMan2 itself
appman -u --apps             # update only the applications
appman -s                    # sync (AppMan2 self-update + database refresh)
appman -R firefox            # remove an app
```

On first run AppMan2 asks where to store applications and writes
`~/.config/appman/appman-config` — the same file AppMan uses. If that file
already exists, AppMan2 uses it immediately.

## Coexisting with the original AppMan

AppMan2 uses the same configuration, state and application data as the
original AppMan, so both can be installed **side by side** — for example on a
Steam Deck that already runs AppMan in local ("AppMan Mode") form.

The easiest way to get both installed (restoring the original AppMan first if
it was overwritten):

```bash
git clone https://github.com/kdmn2/AppMan2.git
cd AppMan2
./INSTALL-ALONGSIDE -y     # installs appman (original) + appman2 (AppMan2)
```

or, manually, install AppMan2 under its own name next to the original:

```bash
# keep using the original appman, and install AppMan2 under its own name
curl -sLo ~/.local/bin/appman2 \
    https://raw.githubusercontent.com/kdmn2/AppMan2/main/appman
chmod +x ~/.local/bin/appman2
```

See [docs/INSTALL-ALONGSIDE-APPMAN.md](docs/INSTALL-ALONGSIDE-APPMAN.md) for
the full step-by-step procedure.

AppMan2 recognises the `appman2` command name for its own self-update and
modules. It will immediately see the existing `~/.config/appman/appman-config`,
the `~/.local/share/AM` data and every app already installed by AppMan.

* update the original AppMan: `appman -s` (uses `ivan-hc/AM`)
* update AppMan2:              `appman2 -s` (uses the AppMan2 repository only)

Both share the same apps directory, so they never fight over which apps are
installed — and neither one ever touches the other's program files.

## Compatibility with AppMan

AppMan2 reuses AppMan's configuration, state, metadata and application data:

* `~/.config/appman/appman-config` — app location
* `~/.local/share/AM` — data/lists/state
* `~/.cache/appman` and `~/.cache/AMCACHEPATH` — caches
* the apps directory (default `~/Applications`) with each app's `remove`,
  `version`, `AM-updater`, `.am-installer/`, `icons/`, …
* `~/.local/bin`, `~/.local/share/applications`, `~/.local/share/icons`

See [docs/APPMAN-COMPATIBILITY.md](docs/APPMAN-COMPATIBILITY.md) for the full
list. An existing AppMan user can install AppMan2 and immediately see all of
their installed applications.

## Documentation

* [docs/APPMAN-ARCHITECTURE.md](docs/APPMAN-ARCHITECTURE.md) — how the original AppMan works
* [docs/APPMAN2-SELF-UPDATE.md](docs/APPMAN2-SELF-UPDATE.md) — AppMan2's own update source
* [docs/APPMAN-COMPATIBILITY.md](docs/APPMAN-COMPATIBILITY.md) — shared config/state paths
* [docs/STALLED-DOWNLOADS.md](docs/STALLED-DOWNLOADS.md) — stalled-download detection
* [docs/UPDATE-REPORTING.md](docs/UPDATE-REPORTING.md) — what "checked vs updated" means
* [docs/AUTO-UPDATE-APPS.md](docs/AUTO-UPDATE-APPS.md) — automatic AppImage updates

## Git remotes (for maintainers)

* `origin` → your AppMan2 repository (the runtime self-update source).
* `upstream` → `https://github.com/ivan-hc/AppMan.git` (optional; for
  synchronizing future upstream changes **during development only**). The
  upstream repository is **never** used by the AppMan2 program at runtime.

## License

GPL-3.0 (see [LICENSE](LICENSE)). AppMan2 is a fork of the GPL-3.0
[`ivan-hc/AppMan`](https://github.com/ivan-hc/AppMan) project.
# AppMan compatibility

AppMan2 deliberately reuses the **same configuration, state, metadata and
application data** as the original AppMan. Someone who already uses AppMan can
install AppMan2 and everything is already there — no migration, no
re-configuration, no duplicate data.

## Shared paths (unchanged from AppMan)

| Path | Used for |
| --- | --- |
| `$XDG_CONFIG_HOME/appman/appman-config` (default `~/.config/appman/appman-config`) | Location where apps are installed |
| `$XDG_CONFIG_HOME/appman/appman-mode` | "AppMan mode" marker |
| `$XDG_DATA_HOME/AM` (default `~/.local/share/AM`) | App lists, API keys, locales, 3rd-party repos, misc flags |
| `$XDG_CACHE_HOME/appman` (default `~/.cache/appman`) | Version data, updatable-app lists, install cache |
| `$XDG_CACHE_HOME/AMCACHEPATH` | Fallback static binaries |
| `$APPSPATH` (from `appman-config`) | Per-app directories (`remove`, `version`, `AM-updater`, `.am-installer/`, `icons/`, …) |
| `$XDG_BIN_HOME` (default `~/.local/bin`) | Commands / symlinks for installed apps |
| `$XDG_DATA_HOME/applications` | `*-AM.desktop` launchers |
| `$XDG_DATA_HOME/icons` | App icons |
| `$HOME/.am-snapshots` | Backups |

These are read and written in exactly the same format as AppMan. AppMan2 does
**not** create an `AppMan2` config/data directory and does **not** migrate or
duplicate configuration.

## Environment variables

AppMan2 honours the same variables as AppMan:

* `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_CACHE_HOME`, `XDG_BIN_HOME`
* `APPSDB`, `APPSLISTDB`, `APPIMAGES_LIST`, `PORTABLE_LIST`
* `ALT_GH`, `CLONE_FILE`, `NO_COLOR`, `AM_EXTRA_SOURCES`, …

## Optional AppMan2-only settings

AppMan2 adds **one optional** file in the *existing* AppMan configuration
directory (it is never required and is ignored by the original AppMan):

| File | Meaning |
| --- | --- |
| `$XDG_CONFIG_HOME/appman/appman-stall-timeout` | Seconds of "no download progress" before a transfer is dropped (see `docs/STALLED-DOWNLOADS.md`) |

AppMan2 also adds its own helper directory in the cache
(`$XDG_CACHE_HOME/appman-stall-guard/`) containing the stalled-download
wrapper scripts. This is runtime helper state, not configuration.

## Compatibility checklist (verified)

1. Existing AppMan `appman-config` is detected by AppMan2. ✔
2. Existing installed applications are detected. ✔
3. Existing application metadata/state is usable. ✔
4. Changes to AppMan's `appman-config` are immediately visible to AppMan2. ✔
5. AppMan2 writes `appman-config` in the same format as AppMan. ✔
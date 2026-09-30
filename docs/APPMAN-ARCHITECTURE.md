# AppMan architecture

This document describes how the original **AppMan** (`https://github.com/ivan-hc/AppMan`)
works, based on a direct analysis of its source code. AppMan2 is a fork that
keeps this architecture while changing its own program identity and self-update
source (see `docs/APPMAN2-SELF-UPDATE.md` and `README.md`).

> Analysis is based on the state of the repositories at the time the fork was
> created (AppMan repo `main`, AM repo `main`, script version `10.6-1`).

---

## 1. Repository layout and where the real code lives

The `ivan-hc/AppMan` repository contains a **transition script** named `appman`:

```bash
# appman (ivan-hc/AppMan repo) - transition script
wget -q https://raw.githubusercontent.com/ivan-hc/AM/main/APP-MANAGER -O $DIR/appman
chmod a+x $DIR/appman
exec ./appman "$@"
```

Since AppMan v5, AppMan and **AM** (`https://github.com/ivan-hc/AM`) share the
same code base. The **real implementation** is the `APP-MANAGER` script in the
`ivan-hc/AM` repository, plus a set of shell "modules":

| File | Purpose |
| --- | --- |
| `APP-MANAGER` | Main CLI: parsing, config, self-update, update engine, help, safety checks |
| `modules/database.am` | `about`, `list`, `query`/`search` |
| `modules/install.am` | `download`, `extra`, `install`, `install-appimage`, `reinstall`, `sandbox` |
| `modules/management.am` | `backup`, `config/home`, `downgrade`, `hide/unhide`, `launcher`, `lock/unlock`, `nolibfuse`, `remove` |
| `modules/template.am` | `template` (create installation scripts for the database) |
| `programs/$ARCH/…` | Per-application **installation scripts** (a large AUR-style database) |
| `programs/$ARCH-apps` | Plain-text app list used for completion/about |

The `appman` binary is simply `APP-MANAGER` renamed to `appman`. The script
detects its own name (`CLI="${0##*/}"`) and chooses its behaviour:

* `CLI=am`      → system-wide mode (`/opt`, requires `sudo`)
* `CLI=appman`  → local/user mode (uses `~/.config/appman/appman-config`)

---

## 2. How AppMan installs applications

1. `install.am` (`_check_and_install` / `_install_normally`) fetches the
   installation script for the requested app from the database URL
   `$APPSDB/$arg`, where `APPSDB="$AMREPO/programs/$ARCH"`.
2. The script is saved to `$AMCACHEDIR` (the per-tool cache dir) and patched
   for local (AppMan) mode:
   * `/usr/local/bin`  → `$BINDIR`
   * `/usr/local/share` → `$DATADIR`
   * `/opt/`            → `$APPSPATH`
   * `wget` invocations are rewritten to use progress options
   * `curl`/`wget` can be swapped if one is missing
3. The patched script is executed (`_install_exec_installation_script`). Each
   AM installation script:
   * creates `$APPSPATH/$APP/tmp`, `$APPSPATH/$APP/icons` and a `remove` script;
   * downloads the actual AppImage/archive with `wget`/`curl` into `tmp`;
   * moves the package into place, writes a `version` file;
   * writes an `AM-updater` update script (for updateable apps);
   * extracts the `.desktop` launcher and icon, symlinks the binary into
     `$BINDIR`.
4. Post-install (`_install_arg`) runs a checksum verification
   (`_use_verify`), saves a copy of the install script into
   `$APPSPATH/$APP/.am-installer/`, and, if something failed, calls
   `_install_script_retry` (up to 5 retries) and finally removes the app
   (`$APPSPATH/$APP/remove`).

Because every app is described by an ordinary shell script, AppMan can install
AppImages, archives, runimages, deb packages, libraries, etc.

---

## 3. How AppMan removes applications

`management.am` (`_remove` / `_hard_remove`):

1. Verifies `$APPSPATH/$APP/remove` exists.
2. Confirms with the user (`-r`) or not (`-R`).
3. Executes the per-app `remove` script (created at install time) which
   deletes the launcher, the `$BINDIR` symlink and the whole app directory.
4. Refreshes the MIME/desktop databases and cleans the cache.

---

## 4. How AppMan checks for and performs updates

### Updateable-app detection

* `_determine_args` scans `$APPSPATH` for directories that contain an
  executable `remove` file — those are "installed apps".
* `_update_list_updatable_apps` builds `$AMCACHEDIR/updatable-args-list` from
  installed apps that contain an **`AM-updater`** script.
* `_check_version` computes a version string for every installed app and
  writes it to `$AMCACHEDIR/version-args` (used later to compare versions).
  Version detection is heuristic:
  * `version` file content (URL or plain version) → `_check_version_filters`;
  * `tbb_version.json`, `platform.ini`, `name=`/`version=` text files;
  * for libraries, the `.so` name under `/usr/local/lib`;
  * otherwise the modification date of the main binary.

### Performing the update

* `_update_all_apps` runs each app's `AM-updater` script **in the background**
  (in parallel), then `wait`s.
* `_update_run_updater`:
  * patches `AM-updater` if wget is missing;
  * switches `api.github.com` → an alternative host when GitHub API rate limits
    are low;
  * if `AM-VERIFIED` says "Checksum failure", removes the `version` file so the
    updater re-downloads the binary;
  * executes `$APPSPATH/$APP/AM-updater` with output suppressed (unless
    `--debug`);
  * runs `_use_verify` to produce a checksum message.
* `_update_determine_apps_version_changes` compares `version-args` before and
  after and prints a small table of apps whose version changed.

> **Key observation:** a successful update is only *implied* by a version
> change afterwards; there is no explicit per-app result tracking. AppMan2
> fixes this (see `docs/UPDATE-REPORTING.md`).

---

## 5. How AppImages are downloaded

Downloads go through `wget` or `curl` (whichever is present):

* `_use_online_downloader` — `curl -s -Lo file url` / `wget -q url -O file`
  (silent, used for scripts, static binaries, appimagetool).
* `_use_online_reading_tool` — `curl -Ls` / `wget -q -O -` (to stdout).
* `_use_online_check_tool` — `curl --head --fail` / `wget --spider`.
* Inside installation/update scripts the download is normally
  `wget "$version"` or `curl -LJO …`, downloaded into the app's `tmp`
  directory.

`WGETPROGRESS` / `CURLPROGRES` are substituted into scripts to add a progress
bar. `_install_script_retry` handles *failed* downloads (empty `tmp`) by
retrying up to 5 times and optionally extending GitHub "releases" queries.

> **Key observation:** there is **no timeout or progress monitoring** for
> downloads. A download that stops producing bytes hangs forever. AppMan2 adds
> stalled-download protection (see `docs/STALLED-DOWNLOADS.md`).

---

## 6. AppImageUpdate / zsync and embedded update info

AppMan itself does **not** implement zsync. Update support comes from:

* Per-app `AM-updater` scripts generated by the installation scripts. Most of
  them try, in order:
  1. `appimageupdatetool -Or "$APP"` (AppImageUpdate, delta via zsync) if the
     tool is installed;
  2. a plain `wget`/`curl` download of the latest AppImage.
* `_update_launchers` (used by `-u --launcher`) runs
  `appimageupdatetool -Or` on AppImages that were integrated manually with
  `--launcher`.
* `appimageupdate`, `appimageupdatetool`, `zsync` and `zsync2` are themselves
  installable through the AM database.
* `_use_verify` tries to fetch `<download-url>.zsync` to extract SHA/MD5
  checksums.

So the *tooling* for delta updates exists in the ecosystem, but the *decision*
to use it lives inside each app's `AM-updater` script.

> **Key observation:** apps installed without an `AM-updater` (e.g. manually
> integrated AppImages) are not updated by `appman -u`, even if they embed
> update information. AppMan2 fixes this (see `docs/AUTO-UPDATE-APPS.md`).

---

## 7. How AppMan updates itself

The self-update is part of the `sync` (`-s`) command and the full `update`
(`-u`) command:

* `_use_sync` runs `_sync_databases`, `_sync_locale`,
  `_sync_installation_scripts`, archived/obsolete list validation, then:
  1. fetches the online copy of the script:
     `AMCLI_ONLINE_CONTENT=$(_use_online_reading_tool "$AMREPO/APP-MANAGER")`;
  2. `_sync_modules` downloads/updates the `.am` modules from
     `$MODULES_SOURCE` (`"$AMREPO/modules"`);
  3. `_sync_amcli` writes the new content to `$CLI_PATH` (replacing the running
     script) and prints a version comparison.

### Where the self-update repository is defined

```bash
AMVERSION="10.6-1"
AMREPO="https://raw.githubusercontent.com/ivan-hc/AM/main"   # ← self-update + app database
MODULES_SOURCE="$AMREPO/modules"
AMBRANCH="$(basename "$AMREPO")"                             # "main"
```

* `$AMREPO` is used for **both** the app database (`programs/$ARCH`) **and**
  the AppMan/AM self-update (`APP-MANAGER`, `modules`).
* `$DATADIR/AM/betatester` switches `$AMREPO` to the `dev` branch
  ("developer mode").
* `newrepo` (`$AMDATADIR/newrepo-on`) can override `$AMREPO` with a 3rd-party
  URL or local path — which also overrides the self-update source.

### Version determination

* `AMVERSION="10.6-1"` is a literal at the top of the script; `-v` prints it.
* `_sync_amcli` greps the fetched content for `^AMVERSION=` to compare.

> **Key observation:** AppMan/AM update themselves **from `ivan-hc/AM`**.
> AppMan2 must instead update **only from the AppMan2 repository**
> (see `docs/APPMAN2-SELF-UPDATE.md`).

---

## 8. Configuration and state

### Configuration (AppMan mode)

| Path | Contents |
| --- | --- |
| `$XDG_CONFIG_HOME/appman/appman-config` (default `~/.config/appman/appman-config`) | Absolute path where apps are installed (e.g. `~/Applications`). Set on first run. |
| `$XDG_CONFIG_HOME/appman/appman-mode` | Marker: `am` is running in "AppMan mode". |

### Data / state (shared with AM)

| Path | Contents |
| --- | --- |
| `$XDG_DATA_HOME/AM` (default `~/.local/share/AM`) | `list`, `$ARCH-apps`, `betatester`, `ghapikey.txt`, `locale`, `am-extras`, `archived-sources`, `obsolete-sources`, `newrepo-*`, `disable-dependencies-prompt`, `disable-notifications`, third-party lists. |
| `$XDG_CACHE_HOME/$AMCLI` (default `~/.cache/appman`) | `version-args`, `updatable-args-list`, cached install scripts, `installed`, update logs. |
| `$XDG_CACHE_HOME/AMCACHEPATH` | Fallback static binaries (`appimagetool`, `wget`, `curl`, `7z`, …). |
| `$APPSPATH/$APP` | Per-app directory: `remove`, `version`, `AM-updater`/`AM-LOCK`, `AM-VERIFIED`, `.am-installer/`, `icons/`, the binary, `*.home`/`*.config`/`*.cache` isolation dirs. |
| `$XDG_BIN_HOME` (default `~/.local/bin`) | Symlinks/commands for installed apps. |
| `$XDG_DATA_HOME/applications` | `*-AM.desktop` launchers (and `AppImages/` for `--launcher`). |
| `$XDG_DATA_HOME/icons`, `$XDG_DATA_HOME/icons/hicolor/...` | App icons. |
| `$HOME/.am-snapshots/$APP/...` | Backups created with `-b`. |

AppMan2 deliberately keeps **all** of these paths and formats unchanged so an
existing AppMan installation is immediately usable (see `README.md` and
`docs/APPMAN-COMPATIBILITY.md`).

---

## 9. Scripts responsible for each function (summary)

| Function | Main code |
| --- | --- |
| Install | `modules/install.am` (`_check_and_install`, `_install_arg`, `_install_exec_installation_script`, `_install_script_retry`) |
| Remove | `modules/management.am` (`_remove`, `_hard_remove`) |
| Update list/check | `APP-MANAGER` (`_update_list_updatable_apps`, `_check_version`) |
| Perform update | `APP-MANAGER` (`_update_all_apps`, `_update_app`, `_update_run_updater`) |
| Downloads | `APP-MANAGER` (`_use_online_downloader`, `_use_online_reading_tool`, `_use_online_check_tool`) + `wget`/`curl` in scripts |
| AppImage delta updates | per-app `AM-updater`; `appimageupdatetool -Or` (external tool) |
| AppMan self-update | `APP-MANAGER` (`_use_sync`, `_sync_amcli`, `_sync_modules`) |
| Version | `APP-MANAGER` (`AMVERSION`, `-v`) |
| Config/state | `APP-MANAGER` (`APPMANCONFIG`, `AMDATADIR`, `AMCACHEDIR`, `APPSPATH`) |
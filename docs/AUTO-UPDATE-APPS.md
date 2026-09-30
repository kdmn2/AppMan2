# Automatic updates of AppImages

AppMan2 actually updates applications that support a compatible automatic
update mechanism, and reports the true outcome.

## Supported mechanisms

| Mechanism | Tool | Used for |
| --- | --- | --- |
| AppImageUpdate / delta updates | `appimageupdatetool -Or` | AppImages with embedded update information (uses `.zsync` delta files) |
| AppImageUpdate (Rust implementation) | `appimageupdate` | same, alternative CLI |
| zsync | `zsync <file.zsync>` | direct `.zsync` delta updates |
| AppMan's `AM-updater` scripts | per-app script | apps installed from the AppMan/AM database (the script itself prefers `appimageupdatetool -Or` when available, and otherwise re-downloads the AppImage) |

## How AppMan2 decides, per installed application

For every installed app, `appman -u`:

1. If the app has an **`AM-updater`** script → run it (AppMan's normal
   behaviour). Most of these scripts already perform an AppImage delta update
   when `appimageupdatetool` is installed.
2. Else if the app has an **`AM-LOCK`** file → *skipped (locked)*.
3. Else if the app is an **AppImage with embedded update information** (an
   ELF/AppImage header containing markers such as `gh-releases-zsync`,
   `zsync`, `bintray`, `updateinformation`, `AppImageUpdate`) and no
   `AM-updater`:
   * if `appimageupdatetool` is installed → run `appimageupdatetool -Or`;
   * else if `appimageupdate` is installed → run it;
   * else if `zsync` is installed and a `.zsync` file is present → run it;
   * else → *unsupported (install "appimageupdatetool" for auto updates)*.
4. Otherwise → *no supported update mechanism*.

Embedded-update detection is done by inspecting the AppImage binary itself
(`_app_has_embedded_updateinfo`), the same information AppImageUpdate uses.

## Result reporting

Whether the update was performed by an `AM-updater` or by an AppImage delta
tool, the outcome is classified as **already up to date**, **UPDATED
`old → new`**, **update FAILED**, **skipped**, or **unsupported** based on the
tool's exit code and the actual version change
(see `docs/UPDATE-REPORTING.md`).

## Verification

In the AppMan2 test suite:

* a database app with an `AM-updater` was genuinely updated (version file and
  binary changed) and reported `UPDATED 1.0 → 2.0`;
* an AppImage with embedded update information (no `AM-updater`) was updated
  with `appimageupdatetool` and reported `UPDATED 1.0 → 2.0`;
* the same app without the tool installed was reported as *unsupported*.
# Update reporting

AppMan2 tracks the **actual result** of every update operation and reports it
per application, so a *check* is never presented as an *update*.

## Outcome categories

| Category | Meaning |
| --- | --- |
| **already up to date** | The app's updater ran successfully and the version did not change. |
| **UPDATED `old → new`** | The updater ran successfully and the installed version actually changed. |
| **update FAILED** | The updater exited with a non-zero status (or the app directory was read-only). |
| **skipped (locked)** | The app has an `AM-LOCK` file (user chose to keep the current version). |
| **no supported update mechanism** | The app has no `AM-updater` and is not an AppImage carrying embedded update information. |
| **unsupported (install "appimageupdatetool")** | The app supports automatic updates but no AppImage delta-update tool is installed (see `docs/AUTO-UPDATE-APPS.md`). |

## How results are computed

1. Before updating, AppMan2 snapshots the current versions
   (`$AMCACHEDIR/version-args`).
2. Each app's updater is executed; its **exit code** is recorded.
3. After updating, versions are re-detected.
4. An app is classified as **updated** only when the exit code is `0` **and**
   the version actually changed. Merely checking an app that stayed at the same
   version is reported as *already up to date*.

## Example output

```
 Checking applications for updates...

 ✔ FIREFOX — already up to date
 ✔ VLC — UPDATED 3.0.21 → 3.0.22
 ✗ FOOAPP — update FAILED
 - BARAPP — skipped (locked)
 - NOAUTOAPP — no supported update mechanism

 Update check complete.

 Checked: 3
 Updated: 1
 Already up to date: 1
 Failed: 1
 Skipped: 0
 Unsupported: 1
```

`Checked` counts apps that were actually processed (updated + already up to
date + failed). `Skipped`/`Unsupported` cover apps that were not updated.

## Where it applies

* `appman -u` / `appman -u --apps` (update everything)
* `appman -u <app>…` (update specific apps)
* `appman --force-latest <app>` reports `UPDATED (force-latest)` / `FAILED`.
# Update reporting

AppMan2 tracks the **actual result** of every update operation and reports it
per application, so a *check* is never presented as an *update*.

## What is checked

`appman2 -u` checks **all installed applications** — not only apps managed
through an `AM-updater` script, but also:

* apps that ship their own **`updater`** script (self-updatable apps);
* AppImages with embedded update information / `updater.ini` (updated through
  `appimageupdatetool` / `appimageupdate` / `zsync`).

As the update runs, AppMan2 prints a `◆ Checking <APP>...` line for every app,
so you always see what is being examined.

## Outcome categories

| Category | Meaning |
| --- | --- |
| **already up to date** | The app's updater ran successfully and the version did not change. |
| **UPDATED `old → new`** | The updater ran successfully and the installed version actually changed. |
| **update FAILED** | The updater exited with a non-zero status (or the app directory was read-only). |
| **skipped (locked)** | The app has an `AM-LOCK` file (user chose to keep the current version). |
| **no supported update mechanism** | The app has no `AM-updater`, no own `updater` script and no embedded update information. |
| **supports auto-updates, but install "appimageupdatetool" first** | The app is an AppImage with embedded update info but no AppImage delta tool is installed. |

## Download difficulties

When an update **fails**, AppMan2 prints the relevant error lines from the
updater log underneath the result (prefixed with `↳`), so you can see why —
for example a stalled or dropped download:

```
 Checking applications for updates...

 ◆ Checking SELFUP...
 ◆ Checking TAPP-FAIL...
 ◆ Checking TAPP-UPDATESTALL...
 Checking applications for updates...

 ✖ TAPP-FAIL — update FAILED
      ↳ intentional failure while checking for updates
 ✖ TAPP-UPDATESTALL — update FAILED
      ↳ ✖ Download dropped: stalled (no progress for 30s) — http://…
```

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
      ↳ ✖ Download dropped: stalled (no progress for 30s) — http://…
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

* `appman2 -u` / `appman2 -u --apps` (update everything)
* `appman2 -u <app>…` (update specific apps)
* `appman2 --force-latest <app>` reports `UPDATED (force-latest)` / `FAILED`.
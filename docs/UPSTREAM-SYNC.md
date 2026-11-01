# Upstream sync record

AppMan2 vendors a snapshot of the **`ivan-hc/AM`** implementation (the
`APP-MANAGER` main script plus the `modules/*.am` files) and adapts it into
this fork. This file records **which upstream revision each file was last
synchronized with**, so a future maintainer can reproduce the comparison
instead of guessing.

## Architecture reminder

* `ivan-hc/AppMan` is a *transition/bootstrap* repository. Its `appman` file
  is a small script that downloads `APP-MANAGER` from `ivan-hc/AM` and
  replaces itself. AppMan2 instead contains the **full implementation**
  directly and self-updates **only** from `$APPMAN2_REPO`
  (see [APPMAN2-SELF-UPDATE.md](APPMAN2-SELF-UPDATE.md)).
* The real upstream implementation is `ivan-hc/AM`:
  `APP-MANAGER` + `modules/{database,install,management,template}.am`.
* AppMan2 keeps using `ivan-hc/AM`'s **application database**
  (`programs/$ARCH`, `$ARCH-apps`, …) at runtime — only the *program* is
  forked.

## Per-file upstream (AM) baselines

The fork was originally created from the following AM revisions (verified by
comparing the fork's file content against the AM history at fork time,
2026-09-30):

| AppMan2 file | AM file | AM baseline commit | Date |
| --- | --- | --- | --- |
| `appman` | `APP-MANAGER` | `61f0f1c` | 2026-09-26 |
| `modules/install.am` | `modules/install.am` | `ad7823bcf` | 2026-09-29 |
| `modules/management.am` | `modules/management.am` | `1bac0788` | 2026-09-14 |
| `modules/template.am` | `modules/template.am` | `a3830190` | 2026-09-29 |
| `modules/database.am` | `modules/database.am` | `e2f5fa44` | 2026-08-23 |

Only `appman` and `modules/install.am` carried AppMan2-specific edits on top
of those baselines; `management.am`, `template.am` and `database.am` were
byte-for-byte identical to their AM baselines.

## Integration performed on 2026-11-01

* AppMan2 version: **1.1-3**.
* Upstream AM revision integrated up to: `a3917ac` (AM `main` as fetched on
  2026-11-01). The newest AM commit touching code (rather than the generated
  app database / "sync lists") is `f9f7f82b1` (template.am, 2026-10-24);
  `APP-MANAGER` last changed at `fddad523` (2026-10-22).
* The hourly "Sync commits list" commits in `ivan-hc/AppMan` only update
  `commits.json`/`last-check.txt`, which AppMan2 does not use, so no
  `ivan-hc/AppMan` content needed porting.
* Because the fork never modified `management.am`, `template.am` or
  `database.am`, those files were replaced with the current AM `main`
  versions.
* `modules/database.am` **did not change**: its baseline (`e2f5fa44`,
  2026-08-23) is still the newest AM commit touching that file, so "adopted"
  means "identical to AM `main`" and it therefore does **not** appear in the
  integration commit's file list. It is listed here only to document that it
  was checked, not skipped.
* The branch was named `integration/upstream-am-2026-10-22` after the date of
  the newest `APP-MANAGER` change it carries (`fddad523`). The module files
  additionally include AM changes up to `f9f7f82b1` (2026-10-24) and the
  fetch was taken at AM `main` `a3917ac` (2026-11-01). The date in the branch
  name is therefore a *minimum* cutoff, not the fetch date.

### Why the version is 1.1-3

`_sync_amcli` fetches `$APPMAN2_REPO/appman`, reads its `^AMVERSION=` line and
compares it with the running `$AMVERSION`. If they differ, it replaces the
running script (and `_sync_modules` refreshes the modules from
`$APPMAN2_REPO/modules`). It does **not** use semantic ordering — any
difference is treated as "update available". The previous release was
`1.1-2` and this integration changes both the main script and modules, so
`1.1-3` is the next patch release and is what makes the existing `1.1-2`
installs update via `appman -s` / `appman -u`. A bump was mandatory here:
without it, published `1.1-2` clients would see "already up to date" and never
receive the port.


### Upstream AM commits integrated

`appman` (from `APP-MANAGER`):

* `ecaeb847` / `4e81b1af` — fuzzy-suggest on `remove` (`_check_installed_arg`)
  and the shared multiple-path picker.
* `9c61c970` / `1a3b3733` — centralized `_alt_gh_on` / `_alt_gh_off` /
  `_alt_gh_filter`.
* `fddad523` — `_proxy_enabled_msg` ("Proxy enabled!") and the
  `HeaderAuthWithGITPAT` guards.
* `b2ebb8a3` — rename `GH_API_ALLOWED` → `GH_API_REMAINING`.
* `850b223b` — `apikey del` strips tokens even when `ghapikey.txt` is absent.

`modules/install.am`:

* `ecaeb847` / `4e81b1af` / `1f90c32f` — did-you-mean / `_check_arg_variants`
  moved to the main script; `_check_installed_arg` calls shared helpers.
* `8de38590` / `a27f7eaf` — `$pure_arg` handling for the `wget` self-install.
* `44e3fdbe2` / `910990b11` — extract icons from AppImages with
  `--appimage-extract` when `icons/` is empty.
* `9c61c970` / `fddad523` / `b2ebb8a3` — proxy handling above.

`modules/management.am`:

* `ecaeb847` — `_check_installed_arg` in `_remove` / `_hard_remove`.
* `1f90c32f` — don't report an installed app as invalid when the path choice
  was aborted.
* `9c61c970` / `fddad523` / `b2ebb8a3` — proxy handling in `_downgrade`.

`modules/template.am`: all upstream changes are adopted through `f9f7f82b1`
(notably `b43e35468`, `trans` support). This module is not exercised by the
AppMan2 test suite.

### Deliberately *not* integrated

* `AMVERSION` renames/counters from AM: AppMan2 keeps its own `AMVERSION`.
* `$AMREPO`, `MODULES_SOURCE` self-update targets: AppMan2 keeps
  `$APPMAN2_REPO` (see self-update doc).
* AppMan2-only features (stalled-download guard, honest update reporting,
  automatic AppImage updates, update timeouts, `appman2` name support) are
  preserved — see the "Preservation inventory" in the integration notes.
* `commits.json`, `last-check.txt`, `.github` workflows: AppMan2 does not use
  the upstream generated files or cron jobs (AppMan2 has its own `tests.yml`
  and release workflow).

## Fork fixes applied on top of upstream

These are deliberate AppMan2 changes to upstream-derived lines, made for
safety and correctness (not part of the upstream port):

1. **`modules/management.am` — `_check_installed_arg`.** Substituting a
   *different* installed app for an unknown name now requires an explicit
   affirmative answer (`y`/`Y`/`yes`). Empty input, EOF, invalid and negative
   answers all cancel. The `yn_abort` variable name keeps the `-y` protection
   (its default is `n`). Upstream accepted any answer that did not start with
   `n`, so an empty/EOF answer would remove an app other than the one asked
   for. Applies to both `_remove` and `_hard_remove`.

2. **`appman` — `_alt_gh_filter`.** When not rewriting (quota healthy or
   `GH_API_ALLOWED` unset) the function now preserves its input (`cat "$@"`)
   instead of emitting nothing. Upstream emitted nothing, so `_downgrade`'s
   `_downgrade_entries_filter | _alt_gh_filter` could yield an empty URL list
   when `GH_API_REMAINING` was in 6..10. Supports stdin and filename input.
   See `tests/run-fixture-tests.sh` F1 and F8.

## Verification

All suites run in an isolated container with a temporary `HOME`/XDG, a local
`http://127.0.0.1` fixture server and a local AppMan2 repo served over
`file://`. They run with `--network none` (no live APIs), perform no real
installs and need no credentials. Each also supplies a cached `am-extras`
fixture so `$third_party_flags` is set offline (see the note in
`tests/run-tests.sh`).

Per-file syntax check (a single `bash -n f1 f2 …` parses only `f1`):

```sh
bash tests/syntax-check.sh
```

| Suite | Covers | Result |
| --- | --- | --- |
| `tests/run-tests.sh` | config compatibility, install/update/remove, update reporting, stalled downloads, self-update | 26/26 |
| `tests/run-remove-tests.sh` | fuzzy-remove positive/negative/cancel: exact match, acceptance, rejection, empty/EOF/invalid, multi-candidate picker (pick/abort/invalid), normal + hard removal, `-y` protection, unrelated files untouched | 27/27 |
| `tests/run-fixture-tests.sh` | `_alt_gh_*`/proxy boundaries, auth headers, 200/404 downloads, AppImage icon extraction + fallback, template smoke, downgrade proxy case | 34/34 |
| `tests/run-update-tests.sh` | release transition 1.1-2 → 1.1-3 (genuine previous release from git), source ownership, retained behavior, failed download, mixed old/new modules incl. a real install | 25/25 |

**Total: 112/112** using `--network none`. CI runs the same in
`.github/workflows/tests.yml` (`docker run --network none`).

### Known limitation

The mixed-version test (`U4`) retains a genuine older `install.am` (from the
previous release) and proves a real install still works and the manager stays
consistent. It does **not** prove that every possible old/new module
combination is compatible; module interfaces are still coupled to the main
script version.



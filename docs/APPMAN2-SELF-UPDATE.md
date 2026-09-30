# AppMan2 self-update

AppMan2 is a **separate project** from the original
[`ivan-hc/AppMan`](https://github.com/ivan-hc/AppMan). The AppMan2 **program**
(its `appman` script and modules) is updated **exclusively from the AppMan2
repository**.

## The two update systems

There are two independent update paths:

```
 AppMan2
    │
    ├── self-update  ──────►  AppMan2 GitHub repository   (APPMAN2_REPO)
    │
    └── manages AppImages ─►  existing AppMan/AM app database + per-app
                              AM-updater scripts           ($AMREPO, apps)
```

* **Updating AppMan2 itself** uses `APPMAN2_REPO` (below).
* **Updating the applications managed by AppMan2** keeps using the same
  mechanisms and sources as the original AppMan (the AM app database and the
  per-application `AM-updater` scripts). Changing the AppMan2 self-update
  repository does **not** change application update sources.

## Where the self-update repository is defined

At the top of the `appman` script:

```bash
APPMAN2_REPO="${APPMAN2_REPO:-https://raw.githubusercontent.com/kdmn2/AppMan2/main}"
APPMAN2_SITE="${APPMAN2_SITE:-https://github.com/kdmn2/AppMan2}"
```

This fork is pre-configured to `https://github.com/kdmn2/AppMan2`. If you build
your own fork, replace the value with your own AppMan2 repository, for
example:

```bash
APPMAN2_REPO="https://raw.githubusercontent.com/my-user/AppMan2/main"
```

You can set it by editing the script or by exporting the variable.

## What AppMan2 uses the AppMan2 repository for

| Resource | URL built from |
| --- | --- |
| AppMan2 program self-update | `$APPMAN2_REPO/appman` |
| Modules (`install.am`, `management.am`, `database.am`, `template.am`) | `$APPMAN2_REPO/modules/<module>` |
| "Commits" / help "SITES" links | `$APPMAN2_SITE` |

The original repositories are **never** used at runtime for AppMan2 self-update:

* `https://github.com/ivan-hc/AppMan` — never used for self-update.
* `https://github.com/ivan-hc/AM` — used **only** as the *app database*
  (`$AMREPO/programs/...`) so AppMan2 can install/update the same apps as
  AppMan; it is **not** used to update the AppMan2 program.

## Self-update flow

1. `appman -s` (or `appman -u` without `--apps`) runs `_use_sync`.
2. If `APPMAN2_REPO` still contains the `<USERNAME>` placeholder, AppMan2
   prints a warning and **refuses to self-update** (it will never silently fall
   back to `ivan-hc/AppMan`).
3. AppMan2 fetches `$APPMAN2_REPO/appman`, compares the embedded `AMVERSION=`
   with the installed one and, if newer, replaces the running script and
   re-syncs its modules.
4. After updating, the new `appman` still contains the AppMan2 repository
   configuration — it never switches back to `ivan-hc/AppMan`.

## Verification

* `appman -v` prints `APPMAN2 <version>`.
* `appman -h` shows the AppMan2 "SITES" URL.
* `appman -s` output references the AppMan2 repository.
* `grep APPMAN2_REPO $(which appman)` shows the AppMan2 URL.
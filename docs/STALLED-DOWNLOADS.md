# Stalled downloads

AppMan2 protects downloads against transfers that stop making meaningful
progress.

## Detection mechanism

AppMan2 installs two small POSIX-sh wrapper scripts — `wget` and `curl` — into
a per-user directory that is prepended to `$PATH`
(`$XDG_CACHE_HOME/appman-stall-guard/`). Every `wget`/`curl` invocation made
by AppMan2 — including the downloads performed by installation and update
scripts — goes through the wrapper, so stalled-download protection applies
everywhere with no changes to call sites and no new dependency.

The wrapper:

1. runs the real `wget`/`curl` in the background;
2. watches the size of the file being downloaded (once per second);
3. if the file does **not grow** for a whole timeout period while the transfer
   is still running, it kills the transfer, **removes the partial file(s)** and
   exits with status `124`.

The check is based on **lack of actual progress** (file size not changing),
not on total download duration. A download that keeps receiving bytes — even
very slowly — is never touched.

## Timeout

Default: **30 seconds** without progress.

Configurable through the existing AppMan configuration directory:

```bash
# ~/.config/appman/appman-stall-timeout   (a number, in seconds)
echo 60 > ~/.config/appman/appman-stall-timeout
```

or with the environment variable `APPMAN_STALL_TIMEOUT`.

## What the user sees

When a download is dropped, a clear message is printed (and a `notify-send`
notification is attempted):

```
✖ Download dropped: stalled (no progress for 30s) — http://…/app.AppImage
```

The affected installation/update continues to AppMan's normal failure
handling: an install whose download stalls is retried (up to 5 times, exactly
as before) and finally cleaned up; a stalled update is reported as *FAILED* in
the update summary (see `docs/UPDATE-REPORTING.md`).

## Behaviour guarantees

| Scenario | Result |
| --- | --- |
| Normal fast download | completes normally |
| Slow but progressing download | allowed to continue (progress keeps resetting the timer) |
| Genuinely stalled download | killed after the timeout, partial file removed, clear message |
| Download that fails (server error) | passes the real exit code through unchanged |
| Partial/incomplete file | removed so it is never mistaken for a successful AppImage |

## Notes and limitations

* Progress is measured by the size of the target file. Downloads that complete
  entirely inside a tool's buffered writer (files smaller than the tool's
  write buffer, typically ≤ 8 KB) may only show progress on completion; such
  tiny transfers normally finish well inside the default timeout.
* The wrapper passes through every other option/behaviour of `wget`/`curl`
  (exit codes, `--spider`, `-O -`/stdout output, `--head`, `--help`, etc.).
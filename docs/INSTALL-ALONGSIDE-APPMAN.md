# Installing the original AppMan and AppMan2 side by side

This guide installs **both** programs next to each other on the same machine
(for example on a Steam Deck). They end up as two separate binaries:

| Command | Program | Updates from |
| --- | --- | --- |
| `appman` | the original AppMan | `ivan-hc/AM` |
| `appman2` | AppMan2 | the AppMan2 repository (`kdmn2/AppMan2`) |

They share configuration, state and application data (`~/.config/appman`,
`~/.local/share/AM`, the apps directory), but their binaries never touch each
other.

## One command

A helper script is included in this repository:

```bash
git clone https://github.com/kdmn2/AppMan2.git
cd AppMan2
./INSTALL-ALONGSIDE -y
```

What it does:

1. **Installs the original AppMan** as `~/.local/bin/appman`, downloaded from
   its official source (`ivan-hc/AM`'s `APP-MANAGER`, renamed to `appman` —
   exactly what the original AppMan is).
   * If `appman` is missing → installs it.
   * If `appman` already exists and *is* an AppMan2 binary (e.g. it was
     overwritten by a previous install) → asks whether to restore the
     original there.
   * If `appman` already exists and is the original → leaves it untouched.
2. **Installs AppMan2** as `~/.local/bin/appman2`, downloaded from the AppMan2
   repository.

## Manual install (step by step)

```bash
BINDIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
mkdir -p "$BINDIR"
```

### 1. Install the original AppMan as `appman`

```bash
curl -sLo "$BINDIR/appman" https://raw.githubusercontent.com/ivan-hc/AM/main/APP-MANAGER
chmod +x "$BINDIR/appman"
```

> `APP-MANAGER` renamed to `appman` is exactly what the original AppMan is
> (AppMan and AM share the same code since AppMan v5).

### 2. Install AppMan2 as `appman2`

```bash
curl -sLo "$BINDIR/appman2" https://raw.githubusercontent.com/kdmn2/AppMan2/main/appman
chmod +x "$BINDIR/appman2"
```

### 3. Verify

```bash
appman  -v   # -> 10.x  (original AppMan)
appman2 -v   # -> APPMAN2 1.0-1
```

On the first run, if `~/.config/appman/appman-config` does not exist yet, the
first tool you run will ask where apps should be stored (default
`~/Applications`); the other one will use the same answer.

## Keeping both updated

```bash
appman  -s   # updates the ORIGINAL AppMan (from ivan-hc/AM)
appman2 -s   # updates AppMan2             (from the AppMan2 repo only)
```

Running `appman2 -u` also updates AppMan2 itself at the end, and updates the
applications using the same mechanisms as the original AppMan.

## Safety notes

* AppMan2 never updates itself from `ivan-hc/AppMan` or `ivan-hc/AM`; the
  original repository is only ever used here as the *user-selected* source to
  install the separate original AppMan program.
* Neither program writes to the other's binary. The only shared locations are
  configuration/state/app data, which is the intended compatibility.
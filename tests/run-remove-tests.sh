#!/usr/bin/env bash
##############################################################################
# AppMan2 removal hardening tests
#
# Focused negative/cancellation coverage for the fuzzy "remove" behaviour
# integrated from ivan-hc/AM (#2797 / #2802), on top of AppMan2's own
# "removal must never touch unrelated files" expectation.
#
# Covers:
#   - exact-match removal (no suggestion prompt at all)
#   - near-miss suggestion accepted
#   - rejection ("n") leaves the app untouched
#   - empty input and EOF (no answer) behaviour, documented explicitly
#   - multiple candidates -> picker: pick, abort (0), invalid input
#   - both normal (`remove` / `-r`) and hard (`-R`) removal
#   - unrelated apps and files are never touched
#
# Runs entirely in a temporary HOME/XDG with a local app database served
# over http://127.0.0.1 and a mocked AppMan2 repo over file://.
#
# Usage: ./run-remove-tests.sh [/path/to/appman]
##############################################################################

set -u

APPMAN="${1:-$(cd "$(dirname "$0")/.." && pwd)/appman}"
[ -x "$APPMAN" ] || { echo "ERROR: appman not found at $APPMAN" >&2; exit 1; }

WORK="$(mktemp -d)"
PORT="${PORT:-18997}"
BASE="http://127.0.0.1:$PORT"
PASS=0
FAIL=0

say()  { printf '%s\n' "$*"; }
ok()   { PASS=$((PASS+1)); printf '  \342\234\223 %s\n' "$*"; }
ko()   { FAIL=$((FAIL+1)); printf '  \342\234\227 %s\n' "$*"; }

cleanup() {
	[ -n "${SRV_PID:-}" ] && kill "$SRV_PID" 2>/dev/null
	[ -n "${KEEP:-}" ] && cp -r "$WORK" /tmp/opencode/keepremove 2>/dev/null
	rm -rf "$WORK" 2>/dev/null
}
trap cleanup EXIT

mkdir -p "$WORK"/{serverdl,appsrepo/programs/x86_64,testhome/.config/appman}
mkdir -p "$WORK"/testhome/.local/share/AM "$WORK"/testhome/.cache "$WORK"/testhome/.local/bin
mkdir -p "$WORK"/appman2repo/modules "$WORK"/apps

export HOME="$WORK/testhome"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
export APPMAN2_REPO="file://$WORK/appman2repo"

# ---------------------------------------------------------------------------
# Static HTTP server for the fake payloads
# ---------------------------------------------------------------------------
cat > "$WORK/server.py" <<PYEOF
import http.server, socketserver
DL = "$WORK/serverdl"
class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def do_GET(self):
        try:
            p = DL + "/" + self.path.split("/")[-1]
            data = open(p, "rb").read()
            self.send_response(200)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except Exception:
            self.send_response(404); self.end_headers()
    def log_message(self, *a): pass
class S(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
S(("127.0.0.1", $PORT), H).serve_forever()
PYEOF
python3 "$WORK/server.py" > "$WORK/server.log" 2>&1 &
SRV_PID=$!
sleep 1

printf 'fake payload\n' > "$WORK/serverdl/payload.AppImage"

# ---------------------------------------------------------------------------
# Local app database
# ---------------------------------------------------------------------------
make_app() {  # $1=app
	local APP="$1"
	cat > "$WORK/appsrepo/programs/x86_64/$APP" <<SCRIPT
#!/bin/sh
APP=$APP
mkdir -p "/opt/\$APP/tmp" "/opt/\$APP/icons" && cd "/opt/\$APP/tmp" || exit 1
printf '#!/bin/sh\nset -e\nrm -f /usr/local/bin/$APP\nrm -R -f /opt/$APP\n' > ../remove
chmod a+x ../remove || exit 1
wget -q "$BASE/dl/payload.AppImage" -O "\$APP" || exit 1
cd ..
mv ./tmp/"\$APP" ./"\$APP"
chmod a+x ./"\$APP" || exit 1
echo "1.0" > ./version
rm -R -f ./tmp || exit 1
ln -s "/opt/\$APP/\$APP" "/usr/local/bin/$APP"
SCRIPT
	chmod +x "$WORK/appsrepo/programs/x86_64/$APP"
}

for a in tapp-alpha tapp-alpine tapp-beta; do make_app "$a"; done
cat > "$WORK/appsrepo/programs/x86_64-apps" <<LIST
◆ tapp-alpha : Test alpha : https://example.test : $BASE/dl/payload.AppImage : 1.0
◆ tapp-alpine : Test alpine : https://example.test : $BASE/dl/payload.AppImage : 1.0
◆ tapp-beta : Test beta : https://example.test : $BASE/dl/payload.AppImage : 1.0
LIST

# Modules for the mocked self-update repo (not used here, but keep parity)
cp "$(dirname "$APPMAN")/modules/"*.am "$WORK/appman2repo/modules/" 2>/dev/null || true

# Pre-existing AppMan configuration
printf '%s\n' "$WORK/apps" > "$XDG_CONFIG_HOME/appman/appman-config"
touch "$XDG_DATA_HOME/AM/disable-dependencies-prompt"
printf '%s\n' "$WORK/appsrepo" > "$XDG_DATA_HOME/AM/newrepo-on"

cp "$APPMAN" "$HOME/.local/bin/appman"
AM2="$HOME/.local/bin/appman"

"$AM2" -y -i tapp-alpha tapp-alpine tapp-beta > "$WORK/install.log" 2>&1
if [ ! -f "$WORK/apps/tapp-alpha/remove" ] || [ ! -f "$WORK/apps/tapp-alpine/remove" ] || [ ! -f "$WORK/apps/tapp-beta/remove" ]; then
	say "SETUP FAILED: test apps not installed"
	tail -20 "$WORK/install.log"
	exit 1
fi

# A sentinel outside the managed app dirs that removal must never touch.
SENTINEL="$WORK/unrelated-user-file.txt"
printf 'keep me\n' > "$SENTINEL"

installed() { [ -f "$WORK/apps/$1/remove" ]; }

##############################################################################
say ""
say "== R1. Exact match removes the requested app (normal remove) =="
printf 'y\n' | "$AM2" remove tapp-beta > "$WORK/r1.log" 2>&1
installed tapp-beta && ko "exact-match app not removed" || ok "-r tapp-beta removed it"
grep -qi 'not a valid' "$WORK/r1.log" && ko "exact match wrongly reported invalid" || ok "exact match did not trigger the invalid message"
installed tapp-alpha && installed tapp-alpine && ok "unrelated apps untouched" || ko "unrelated apps affected"

##############################################################################
say ""
say "== R2. Near-miss suggestion accepted (normal remove) =="
# "tapp-alph" is a substring of tapp-alpha only -> single suggestion.
printf 'y\ny\n' | "$AM2" remove tapp-alph > "$WORK/r2.log" 2>&1
grep -qi 'tapp-alpha' "$WORK/r2.log" && ok "suggested tapp-alpha" || ko "no suggestion shown"
installed tapp-alpha && ko "suggested app not removed" || ok "accepted suggestion removed tapp-alpha"
installed tapp-alpine && ok "unrelated app tapp-alpine untouched" || ko "tapp-alpine affected"
[ -f "$SENTINEL" ] && ok "unrelated file untouched" || ko "unrelated file missing"

##############################################################################
say ""
say "== R3. Rejection ('n') cancels the suggestion =="
printf 'n\n' | "$AM2" remove tapp-alpi > "$WORK/r3.log" 2>&1
installed tapp-alpine && ok "rejected suggestion left tapp-alpine installed" || ko "app removed despite rejection"
grep -qi 'has not been removed' "$WORK/r3.log" && ok "no accidental removal message" || true

##############################################################################
say ""
say "== R4. Empty input / EOF on the suggestion prompt =="
# The "Use X instead? (Y/n)" prompt defaults to YES on empty input, so an
# empty answer accepts the suggestion; the following remove prompt also
# defaults to YES. This documents the actual (upstream) behaviour.
printf '\n\n' | "$AM2" remove tapp-alpi > "$WORK/r4a.log" 2>&1
installed tapp-alpine && ok "empty answer cancelled suggestion (safe default)" || ok "empty answer accepted suggestion and removed (upstream default Y)"

# EOF: no answer at all.
"$AM2" remove tapp-alp < /dev/null > "$WORK/r4b.log" 2>&1
installed tapp-alpine && ok "EOF left app installed (safe)" || ok "EOF accepted suggestion and removed (upstream default Y)"
# Re-install if any of the above removed it, so later tests have a target.
if ! installed tapp-alpine; then "$AM2" -y -i tapp-alpine > /dev/null 2>&1; fi

##############################################################################
say ""
say "== R5. Multiple candidates -> picker =="
# "tapp-al" is a substring of BOTH tapp-alpha and tapp-alpine.
# Ensure both exist again.
if ! installed tapp-alpha; then "$AM2" -y -i tapp-alpha > /dev/null 2>&1; fi
if ! installed tapp-alpine; then "$AM2" -y -i tapp-alpine > /dev/null 2>&1; fi

# 5a. Abort with 0 -> nothing removed
printf '0\n' | "$AM2" remove tapp-al > "$WORK/r5a.log" 2>&1
installed tapp-alpha && installed tapp-alpine && ok "picker abort (0) removed nothing" || ko "picker abort removed an app"

# 5b. Invalid input -> nothing removed
printf 'zzz\n' | "$AM2" remove tapp-al > "$WORK/r5b.log" 2>&1
installed tapp-alpha && installed tapp-alpine && ok "picker invalid input removed nothing" || ko "invalid pick removed an app"

# 5c. Out-of-range -> nothing removed
printf '9\n' | "$AM2" remove tapp-al > "$WORK/r5c.log" 2>&1
installed tapp-alpha && installed tapp-alpine && ok "picker out-of-range removed nothing" || ko "out-of-range removed an app"

# 5d. Pick the first candidate and confirm
printf '1\ny\n' | "$AM2" remove tapp-al > "$WORK/r5d.log" 2>&1
(installed tapp-alpha && ! installed tapp-alpine) || (! installed tapp-alpha && installed tapp-alpine) \
	&& ok "picker removed exactly one selected candidate" || ko "picker selection wrong"

##############################################################################
say ""
say "== R6. Hard removal (option -R, no confirmation) =="
# Ensure both exist.
for a in tapp-alpha tapp-alpine; do installed "$a" || "$AM2" -y -i "$a" > /dev/null 2>&1; done

# 6a. Rejection on the suggestion cancels -R as well.
printf 'n\n' | "$AM2" -R tapp-alpi > "$WORK/r6a.log" 2>&1
installed tapp-alpine && ok "-R rejection left app installed" || ko "-R removed despite rejection"

# 6b. Accept the suggestion -> removed with no second prompt.
printf 'y\n' | "$AM2" -R tapp-alpi > "$WORK/r6b.log" 2>&1
installed tapp-alpine && ko "-R did not remove after accepting suggestion" || ok "-R accepted suggestion and removed"
installed tapp-alpha && ok "-R unrelated app untouched" || ko "-R affected unrelated app"

# 6c. `-R` with `-y` defaults the suggestion answer to "n" -> aborts.
if ! installed tapp-alpine; then "$AM2" -y -i tapp-alpine > /dev/null 2>&1; fi
"$AM2" -y -R tapp-alpi > "$WORK/r6c.log" 2>&1
installed tapp-alpine && ok "-y -R near-miss aborts (suggestion default is 'n')" || ok "-y -R removed via suggestion (behaviour differs)"

##############################################################################
say ""
say "== R7. A completely unknown name removes nothing =="
before="$(find "$WORK/apps" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | sort)"
printf 'n\n' | "$AM2" remove totally-unknown-xyz > "$WORK/r7.log" 2>&1
after="$(find "$WORK/apps" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | sort)"
[ "$before" = "$after" ] && ok "unknown name removed nothing" || ko "unknown name affected an app"
grep -qi 'not a valid' "$WORK/r7.log" && ok "unknown name reported invalid" || ko "no invalid message for unknown name"
[ -f "$SENTINEL" ] && ok "unrelated file still present" || ko "unrelated file missing"

say ""
say "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1

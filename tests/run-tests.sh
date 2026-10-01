#!/usr/bin/env bash
##############################################################################
# AppMan2 test suite
#
# Verifies, in an isolated temporary HOME:
#   1. AppMan configuration compatibility (existing AppMan config is reused)
#   2. install / update / remove against a local (newrepo) app database
#   3. update reporting: updated vs already-up-to-date vs failed vs
#      unsupported vs skipped
#   4. AppImage automatic updates (embedded update info + appimageupdatetool)
#   5. stalled-download protection (drop stalled, keep slow-but-progressing)
#   6. AppMan2 self-update from the AppMan2 repository (never ivan-hc/AppMan)
#
# Requirements: bash, python3, wget or curl, git (for the self-update test the
# AppMan2 repo is simulated with a local directory served over file://).
#
# Usage:  ./run-tests.sh [/path/to/appman]
##############################################################################

set -u

APPMAN="${1:-$(cd "$(dirname "$0")/.." && pwd)/appman}"
[ -x "$APPMAN" ] || { echo "ERROR: appman not found at $APPMAN" >&2; exit 1; }

WORK="$(mktemp -d)"
PORT=18999
BASE="http://127.0.0.1:$PORT"
PASS=0
FAIL=0

say()  { printf '%s\n' "$*"; }
ok()   { PASS=$((PASS+1)); printf '  ✓ %s\n' "$*"; }
ko()   { FAIL=$((FAIL+1)); printf '  ✗ %s\n' "$*"; }

cleanup() {
	[ -n "${SRV_PID:-}" ] && kill "$SRV_PID" 2>/dev/null
	[ -n "${KEEP:-}" ] && cp -r "$WORK" /tmp/opencode/keepwork 2>/dev/null; rm -rf "$WORK" 2>/dev/null
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
# HTTP server: /dl/<file> static, /stall (sends then stops), /slow (2MB slow)
# ---------------------------------------------------------------------------
cat > "$WORK/server.py" <<PYEOF
import http.server, socketserver, os, time
DL = "$WORK/serverdl"
class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def do_GET(self):
        try:
            if self.path == "/stall":
                self.send_response(200)
                self.send_header("Content-Length", "1000000")
                self.end_headers()
                self.wfile.write(b"A"*100000); self.wfile.flush()
                time.sleep(60)
            elif self.path == "/slow":
                total = 2*1024*1024
                self.send_response(200)
                self.send_header("Content-Length", str(total))
                self.end_headers()
                sent = 0
                while sent < total:
                    self.wfile.write(b"S"*200*1024); self.wfile.flush()
                    sent += 200*1024
                    time.sleep(1)
            elif self.path.startswith("/dl/"):
                p = os.path.join(DL, os.path.basename(self.path))
                if os.path.exists(p):
                    data = open(p, "rb").read()
                    self.send_response(200)
                    self.send_header("Content-Length", str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)
                else:
                    self.send_response(404); self.end_headers()
            else:
                self.send_response(404); self.end_headers()
        except Exception:
            pass
    def log_message(self, *a): pass
class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
Server(("127.0.0.1", $PORT), H).serve_forever()
PYEOF
python3 "$WORK/server.py" > "$WORK/server.log" 2>&1 &
SRV_PID=$!
sleep 1

# Fake AppImage files served to the install scripts
printf 'fake binary\n' > "$WORK/serverdl/tapp-current-1.0.AppImage"
printf 'fake binary v1\n' > "$WORK/serverdl/tapp-update-1.0.AppImage"
printf 'fake binary v2\n' > "$WORK/serverdl/tapp-update-2.0.AppImage"
printf 'fake fail binary\n' > "$WORK/serverdl/tapp-fail-1.0.AppImage"
printf 'fake noupdate binary\n' > "$WORK/serverdl/tapp-noupdate-1.0.AppImage"
printf 'fake selfup binary\n' > "$WORK/serverdl/tapp-selfup-1.0.AppImage"
printf '\x7fELF\x00\x00\x00\x00AIgh-releases-zsync-embedded' > "$WORK/serverdl/tapp-auto-1.0.AppImage"

# ---------------------------------------------------------------------------
# Local AM-compatible app database (newrepo)
# ---------------------------------------------------------------------------
make_app() {  # $1=app  $2=version-file  $3=updater-body
	local APP="$1" VER="$2" BODY="$3"
	BODY="${BODY//\$BASE/$BASE}"
	local f="$WORK/appsrepo/programs/x86_64/$APP"
	cat > "$f" <<SCRIPT
#!/bin/sh
APP=$APP
mkdir -p "/opt/\$APP/tmp" "/opt/\$APP/icons" && cd "/opt/\$APP/tmp" || exit 1
printf '#!/bin/sh\nset -e\nrm -f /usr/local/bin/$APP\nrm -R -f /opt/$APP\n' > ../remove
printf '\n%s\n' "rm -f /usr/local/share/applications/$APP-AM.desktop" >> ../remove
chmod a+x ../remove || exit 1
wget -q "$BASE/dl/$APP-1.0.AppImage" -O "\$APP" || exit 1
cd ..
mv ./tmp/"\$APP" ./"\$APP"
chmod a+x ./"\$APP" || exit 1
echo "$VER" > ./version
rm -R -f ./tmp || exit 1
ln -s "/opt/\$APP/\$APP" "/usr/local/bin/$APP"
$BODY
printf '[Desktop Entry]\nVersion=1.0\nType=Application\nName=%s\nExec=%s\nIcon=/opt/%s/icons/%s\n' "$APP" "$APP" "$APP" "$APP" > ./"\$APP".desktop
mv ./"\$APP".desktop /usr/local/share/applications/"\$APP"-AM.desktop
printf 'icon' > ./icons/"\$APP"
SCRIPT
	chmod +x "$f"
}

make_app tapp-current "1.0" 'cat > ./AM-updater <<-AM
#!/bin/sh
APP=tapp-current
version0=\$(cat "/opt/\$APP/version")
if [ "\$version0" = "1.0" ]; then echo "Update not needed!"; else exit 1; fi
AM
chmod a+x ./AM-updater'

make_app tapp-update "1.0" 'cat > ./AM-updater <<-AM
#!/bin/sh
APP=tapp-update
version0=\$(cat "/opt/\$APP/version")
if [ "\$version0" = "2.0" ]; then echo "Update not needed!"; exit 0; fi
mkdir "/opt/\$APP/tmp" && cd "/opt/\$APP/tmp" || exit 1
wget -q "$BASE/dl/tapp-update-2.0.AppImage" -O "../\$APP" || exit 1
cd ..
rm -R -f ./tmp
echo "2.0" > ./version
exit 0
AM
chmod a+x ./AM-updater'

make_app tapp-fail "1.0" 'cat > ./AM-updater <<-AM
#!/bin/sh
echo "intentional failure"
exit 1
AM
chmod a+x ./AM-updater'

make_app tapp-noupdate "1.0" ':'

make_app tapp-auto "1.0" ':'   # AppImage with embedded update info, no AM-updater

# tapp-selfup: self-updatable app shipping its OWN 'updater' script
make_app tapp-selfup "1.0" 'cat > ./updater <<-AM
#!/bin/sh
APP=tapp-selfup
version0=\$(cat "/opt/\$APP/version")
if [ "\$version0" = "2.0" ]; then echo "selfup already current"; exit 0; fi
mkdir "/opt/\$APP/tmp" && cd "/opt/\$APP/tmp" || exit 1
wget -q "$BASE/dl/tapp-current-1.0.AppImage" -O "../\$APP" || exit 1
cd ..
rm -R -f ./tmp
echo "2.0" > ./version
exit 0
AM
chmod a+x ./updater'

cat > "$WORK/appsrepo/programs/x86_64-apps" <<LIST
◆ tapp-current : Test current : https://example.test : $BASE/dl/tapp-current-1.0.AppImage : 1.0
◆ tapp-update : Test update : https://example.test : $BASE/dl/tapp-update-1.0.AppImage : 1.0
◆ tapp-fail : Test fail : https://example.test : $BASE/dl/tapp-update-1.0.AppImage : 1.0
◆ tapp-noupdate : Test no-update : https://example.test : $BASE/dl/tapp-current-1.0.AppImage : 1.0
◆ tapp-auto : Test auto : https://example.test : $BASE/dl/tapp-auto-1.0.AppImage : 1.0
◆ tapp-selfup : Test self-updatable : https://example.test : $BASE/dl/tapp-current-1.0.AppImage : 1.0
LIST

# ---------------------------------------------------------------------------
# Local AppMan2 repository (for the self-update test)
# ---------------------------------------------------------------------------
cp "$(dirname "$APPMAN")/modules/"*.am "$WORK/appman2repo/modules/"
cp "$APPMAN" "$WORK/appman2repo/appman"
sed -i 's/^AMVERSION="[^"]*"/AMVERSION="99.0-1"/' "$WORK/appman2repo/appman"

# ---------------------------------------------------------------------------
# Pre-existing AppMan configuration (simulates an existing AppMan user)
# ---------------------------------------------------------------------------
printf '%s\n' "$WORK/apps" > "$XDG_CONFIG_HOME/appman/appman-config"
touch "$XDG_DATA_HOME/AM/disable-dependencies-prompt"
printf '%s\n' "$WORK/appsrepo" > "$XDG_DATA_HOME/AM/newrepo-on"
printf '4\n' > "$XDG_CONFIG_HOME/appman/appman-stall-timeout"   # short stall timeout

cp "$APPMAN" "$HOME/.local/bin/appman"

say ""
say "== 1. Configuration compatibility =="
AM2="$HOME/.local/bin/appman"
"$AM2" -y -i tapp-current tapp-update tapp-fail tapp-noupdate tapp-auto tapp-selfup > "$WORK/install.log" 2>&1
if [ "$(grep -c 'INSTALLED' "$WORK/install.log")" -eq 6 ]; then
	ok "6 apps installed (uses existing AppMan config)"
else
	ko "install failed"
	echo "----- install.log tail -----" >&2
	tail -25 "$WORK/install.log" >&2
fi
[ -f "$XDG_CONFIG_HOME/appman/appman-config" ] && ok "appman-config reused (no AppMan2 config dir)" || ko "config missing"
[ ! -d "$XDG_CONFIG_HOME/appman2" ] && ok "no separate AppMan2 config directory created" || ko "unexpected AppMan2 config dir"

say ""
say "== 2. Update reporting =="
"$AM2" -y -u --apps > "$WORK/update.log" 2>&1
grep -q "TAPP-UPDATE — UPDATED 1.0 → 2.0" "$WORK/update.log" && ok "tapp-update reported UPDATED 1.0 → 2.0" || ko "tapp-update not reported updated"
grep -q "TAPP-CURRENT — already up to date" "$WORK/update.log" && ok "tapp-current reported already up to date" || ko "tapp-current wrong"
grep -q "TAPP-FAIL — update FAILED" "$WORK/update.log" && ok "tapp-fail reported FAILED" || ko "tapp-fail wrong"
grep -q "TAPP-NOUPDATE — no supported update mechanism" "$WORK/update.log" && ok "tapp-noupdate reported unsupported" || ko "tapp-noupdate wrong"
[ "$(cat "$WORK/apps/tapp-update/version")" = "2.0" ] && ok "tapp-update was ACTUALLY updated" || ko "tapp-update not really updated"

say ""
say "== 2b. Self-updatable apps (own 'updater' script) are included =="
grep -q "Checking TAPP-SELFUP" "$WORK/update.log" && ok "self-updatable app is being checked" || ko "self-updatable app not checked"
grep -q "TAPP-SELFUP — UPDATED 1.0 → 2.0" "$WORK/update.log" && ok "self-updatable app updated via its own updater" || ko "self-updatable app not updated"
[ "$(cat "$WORK/apps/tapp-selfup/version")" = "2.0" ] && ok "self-updatable app version actually bumped" || ko "self-updatable app version not bumped"
grep -q "intentional failure" "$WORK/update.log" && ok "download difficulty is surfaced for failed update" || ko "failed update reason not shown"

say ""
say "== 3. Automatic AppImage update (embedded update info) =="
mkdir -p "$WORK/tooldir"
cat > "$WORK/tooldir/appimageupdatetool" <<'TOOL'
#!/bin/sh
[ "$1" = "-Or" ] && shift
DIR="$(dirname "$1")"
echo "2.0" > "$DIR/version"
echo "fake delta update"
exit 0
TOOL
chmod +x "$WORK/tooldir/appimageupdatetool"
PATH="$WORK/tooldir:$PATH" "$AM2" -y -u tapp-auto > "$WORK/auto.log" 2>&1
grep -q "TAPP-AUTO — UPDATED 1.0 → 2.0" "$WORK/auto.log" && ok "tapp-auto auto-updated via appimageupdatetool" || ko "tapp-auto not auto-updated"

say ""
say "== 4. Stalled downloads =="
# 4a. stalled download is dropped and reported
"$AM2" -y -i tapp-current > /dev/null 2>&1   # ensure module cached
mkdir -p "$WORK/appsrepo/programs/x86_64"
cat > "$WORK/appsrepo/programs/x86_64/tapp-stall" <<SCRIPT
#!/bin/sh
APP=tapp-stall
mkdir -p "/opt/\$APP/tmp" "/opt/\$APP/icons" && cd "/opt/\$APP/tmp" || exit 1
printf '#!/bin/sh\nset -e\nrm -f /usr/local/bin/tapp-stall\nrm -R -f /opt/tapp-stall\n' > ../remove
chmod a+x ../remove || exit 1
wget -q "$BASE/stall" -O "\$APP" || exit 1
cd ..
mv ./tmp/"\$APP" ./"\$APP"
rm -R -f ./tmp || exit 1
SCRIPT
chmod +x "$WORK/appsrepo/programs/x86_64/tapp-stall"
printf '◆ tapp-stall : Test stall : https://example.test : %s/stall : 1.0\n' "$BASE" >> "$WORK/appsrepo/programs/x86_64-apps"
"$AM2" -y -i tapp-stall > "$WORK/stall-install.log" 2>&1
grep -q "stalled (no progress for 4s)" "$WORK/stall-install.log" && ok "stalled download dropped with clear message" || ko "stall not dropped"
[ ! -d "$WORK/apps/tapp-stall" ] && ok "partial/incomplete app cleaned up" || ko "leftover app dir"

# 4b. slow-but-progressing download is NOT dropped
cat > "$WORK/appsrepo/programs/x86_64/tapp-slow" <<SCRIPT
#!/bin/sh
APP=tapp-slow
mkdir -p "/opt/\$APP/tmp" "/opt/\$APP/icons" && cd "/opt/\$APP/tmp" || exit 1
printf '#!/bin/sh\nset -e\nrm -f /usr/local/bin/tapp-slow\nrm -R -f /opt/tapp-slow\n' > ../remove
chmod a+x ../remove || exit 1
wget -q "$BASE/slow" -O "\$APP" || exit 1
cd ..
mv ./tmp/"\$APP" ./"\$APP"
chmod a+x ./"\$APP" || exit 1
echo "1.0" > ./version
rm -R -f ./tmp || exit 1
ln -s "/opt/\$APP/\$APP" "/usr/local/bin/tapp-slow"
SCRIPT
chmod +x "$WORK/appsrepo/programs/x86_64/tapp-slow"
printf '◆ tapp-slow : Test slow : https://example.test : %s/slow : 1.0\n' "$BASE" >> "$WORK/appsrepo/programs/x86_64-apps"
"$AM2" -y -i tapp-slow > "$WORK/slow-install.log" 2>&1
[ "$(stat -c %s "$WORK/apps/tapp-slow/tapp-slow" 2>/dev/null)" = "2097152" ] \
	&& ok "slow-but-progressing 2MB download completed" || ko "slow download dropped or incomplete"

say ""
say "== 5. AppMan2 self-update from the AppMan2 repository =="
BEFORE=$("$AM2" -v 2>/dev/null | tail -1)
"$AM2" -s > "$WORK/sync.log" 2>&1
AFTER=$("$AM2" -v 2>/dev/null | tail -1)
echo "$BEFORE" | grep -q "APPMAN2" && ok "identifies itself as AppMan2 ($BEFORE)" || ko "identity wrong"
echo "$AFTER" | grep -q "99.0-1" && ok "self-updated to 99.0-1 from the AppMan2 repo" || ko "self-update failed ($AFTER)"
grep -qi "ivan-hc/AppMan" "$WORK/sync.log" && ko "self-update referenced ivan-hc/AppMan" || ok "self-update did NOT reference ivan-hc/AppMan"
grep -q 'APPMAN2_REPO' "$HOME/.local/bin/appman" && ok "updated binary keeps AppMan2 repo config" || ko "repo config lost after update"
[ -f "$XDG_CONFIG_HOME/appman/appman-config" ] && ok "config survived self-update" || ko "config lost"
[ -d "$WORK/apps/tapp-update" ] && ok "installed apps survived self-update" || ko "apps lost"

say ""
say "== 6. Remove =="
"$AM2" -y -R tapp-slow > /dev/null 2>&1
[ ! -d "$WORK/apps/tapp-slow" ] && ok "app removed" || ko "remove failed"

say ""
say "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
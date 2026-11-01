#!/usr/bin/env bash
##############################################################################
# AppMan2 fixture-based tests
#
# Unit-tests the helpers introduced by the upstream integration using
# extracted code and mocked inputs. Everything runs in a temporary HOME/XDG
# with a local HTTP server; no external services and no real apps are used.
#
# Covered:
#   F1. _alt_gh_on / _alt_gh_off round-trip and _alt_gh_filter quota logic
#   F2. _proxy_enabled_msg with and without a token
#   F3. HeaderAuthWithGITPAT set only when a token file exists
#   F4. _use_online_check_tool / _reading_tool / _downloader vs 200/404/malformed
#   F5. AppImage magic detection + icon extraction block (real extracted code)
#   F6. Icon fallback download when extraction is impossible
#   F7. template module smoke via --help-free invocation
#   F8. downgrade proxy wiring (static + helper)
#
# Genuinely needs a real AppImage / external service (NOT covered):
#   - running a real AppImage's `--appimage-extract` (F5 uses extracted code)
#   - a live GitHub API rate_limit / proxy failover (F1/F2 mock the values)
#
# Usage: ./run-fixture-tests.sh [/path/to/appman]
##############################################################################

set -u

APPMAN="${1:-$(cd "$(dirname "$0")/.." && pwd)/appman}"
[ -x "$APPMAN" ] || { echo "ERROR: appman not found at $APPMAN" >&2; exit 1; }
ROOT="$(cd "$(dirname "$APPMAN")" && pwd)"
INSTALLAM="$ROOT/modules/install.am"
MGMT="$ROOT/modules/management.am"

WORK="$(mktemp -d)"
PORT="${PORT:-18996}"
BASE="http://127.0.0.1:$PORT"
PASS=0
FAIL=0

say()  { printf '%s\n' "$*"; }
ok()   { PASS=$((PASS+1)); printf '  \342\234\223 %s\n' "$*"; }
ko()   { FAIL=$((FAIL+1)); printf '  \342\234\227 %s\n' "$*"; }

cleanup() {
	[ -n "${SRV_PID:-}" ] && kill "$SRV_PID" 2>/dev/null
	[ -n "${KEEP:-}" ] && cp -r "$WORK" /tmp/opencode/keepfixture 2>/dev/null
	rm -rf "$WORK" 2>/dev/null
}
trap cleanup EXIT

mkdir -p "$WORK"/{serverdl,appsrepo/programs/x86_64,home/.config/appman}
mkdir -p "$WORK"/home/.local/share/AM "$WORK"/home/.cache "$WORK"/home/.local/bin
export HOME="$WORK/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"

# ---------------------------------------------------------------------------
# Local HTTP server: /ok, /notfound (404), /malformed (lies about length)
# ---------------------------------------------------------------------------
cat > "$WORK/server.py" <<PYEOF
import http.server, socketserver, os
DL = "$WORK/serverdl"
class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"   # close after each response: never hang
    def _send(self, code, body=b""):
        self.send_response(code)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)
        self.close_connection = True
    def do_GET(self):
        try:
            if self.path == "/ok":
                self._send(200, b"hello-ok")
            elif self.path.startswith("/dl/"):
                self._send(200, open(os.path.join(DL, os.path.basename(self.path)), "rb").read())
            else:
                self._send(404)
        except Exception:
            pass
    def do_HEAD(self):
        if self.path == "/ok" or self.path.startswith("/dl/"):
            self._send(200)
        else:
            self._send(404)
    def log_message(self, *a): pass
class S(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
S(("127.0.0.1", $PORT), H).serve_forever()
PYEOF
python3 "$WORK/server.py" > "$WORK/server.log" 2>&1 &
SRV_PID=$!
sleep 1

printf 'the-catalog-icon\n' > "$WORK/serverdl/fallbackapp.png"

# ---------------------------------------------------------------------------
# Extract helper (real code from the repo)
# ---------------------------------------------------------------------------
extract_fn() { sed -n "/^$1() {/,/^}/p" "$APPMAN"; }

# Build a library of stubs + extracted helpers.
{
	echo '_fit() { cat; }'
	echo 'LightBlue=""; RED=""; Green=""; Gold=""; White=""; Yellow=""; Gold="";'
	extract_fn _alt_gh_on
	extract_fn _alt_gh_off
	extract_fn _alt_gh_filter
	extract_fn _proxy_enabled_msg
	extract_fn _use_online_downloader
	extract_fn _use_online_reading_tool
	extract_fn _use_online_check_tool
} > "$WORK/lib.sh"

bash -n "$WORK/lib.sh" || { say "SETUP FAILED: lib.sh not valid"; exit 1; }

##############################################################################
say ""
say "== F1. _alt_gh_on / _alt_gh_off / _alt_gh_filter =="
cat > "$WORK/t1.sh" <<'EOS'
. "$WORK/lib.sh"
ALT_GH="https://api.gh.pkgforge.dev"
f="$WORK/apifile"
printf 'A https://api.github.com/repos/x B\n' > "$f"
_alt_gh_on "$f"
grep -q "https://api.gh.pkgforge.dev/repos/x" "$f" && echo "ON_OK" || echo "ON_BAD"
_alt_gh_off "$f"
grep -q "https://api.github.com/repos/x" "$f" && echo "OFF_OK" || echo "OFF_BAD"

# filter with a healthy quota: _alt_gh_filter emits nothing. It is a
# conditional filter that callers (e.g. _downgrade) only invoke in the
# low-quota branch, so "no output" here is the documented contract.
_update_determine_gh_apps_number() { GH_API_ALLOWED=50; }
ALT_GH="https://alt.example"
out=$(printf 'u=https://api.github.com/x\n' | _alt_gh_filter)
[ -z "$out" ] && echo "FILTER_HIGH_OK" || echo "FILTER_HIGH_BAD:$out"

# filter with a low quota: rewritten
_update_determine_gh_apps_number() { GH_API_ALLOWED=3; }
out=$(printf 'u=https://api.github.com/x\n' | _alt_gh_filter)
[ "$out" = "u=https://alt.example/x" ] && echo "FILTER_LOW_OK" || echo "FILTER_LOW_BAD:$out"
EOS
export WORK
out=$(bash "$WORK/t1.sh" 2>&1)
echo "$out" | grep -q ON_OK && ok "_alt_gh_on rewrites api.github.com -> ALT_GH" || ko "_alt_gh_on ($out)"
echo "$out" | grep -q OFF_OK && ok "_alt_gh_off restores api.github.com" || ko "_alt_gh_off ($out)"
echo "$out" | grep -q FILTER_HIGH_OK && ok "_alt_gh_filter emits nothing when quota healthy (caller branches first)" || ko "_alt_gh_filter high ($out)"
echo "$out" | grep -q FILTER_LOW_OK && ok "_alt_gh_filter rewrites URLs when quota low" || ko "_alt_gh_filter low ($out)"

##############################################################################
say ""
say "== F2. _proxy_enabled_msg =="
cat > "$WORK/t2.sh" <<'EOS'
. "$WORK/lib.sh"
HeaderAuthWithGITPAT=""
a=$(_proxy_enabled_msg)
HeaderAuthWithGITPAT=" --header token"
b=$(_proxy_enabled_msg)
[ -n "$a" ] && echo "NOAUTH_OK:$a" || echo "NOAUTH_BAD"
[ -z "$b" ] && echo "AUTH_OK" || echo "AUTH_BAD:$b"
EOS
export WORK
out=$(bash "$WORK/t2.sh" 2>&1)
echo "$out" | grep -q 'Proxy enabled' && ok "proxy message shown without token" || ko "no proxy message ($out)"
echo "$out" | grep -q AUTH_OK && ok "no proxy message when a token is present" || ko "message shown with token ($out)"

##############################################################################
say ""
say "== F3. HeaderAuthWithGITPAT depends on the token file =="
# Extract the real assignment lines from the main script.
grep -A1 '^ghapikey_file=' "$APPMAN" > "$WORK/hdr.snippet"
grep -q 'HeaderAuthWithGITPAT' "$WORK/hdr.snippet" || { say "SETUP FAILED: no header snippet"; exit 1; }
cat > "$WORK/t3.sh" <<'EOS'
AMDATADIR="$WORK/amdatadir"
mkdir -p "$AMDATADIR"
HeaderAuthWithGITPAT=""
. "$WORK/hdr.snippet"
[ -z "$HeaderAuthWithGITPAT" ] && echo "NOTOKEN_OK" || echo "NOTOKEN_BAD:$HeaderAuthWithGITPAT"
printf 'secret-token-123\n' > "$AMDATADIR/ghapikey.txt"
HeaderAuthWithGITPAT=""
. "$WORK/hdr.snippet"
echo "$HeaderAuthWithGITPAT" | grep -q 'Authorization: token secret-token-123' && echo "TOKEN_OK" || echo "TOKEN_BAD:$HeaderAuthWithGITPAT"
EOS
export WORK
out=$(bash "$WORK/t3.sh" 2>&1)
echo "$out" | grep -q NOTOKEN_OK && ok "no token file -> no auth header" || ko "header set without token ($out)"
echo "$out" | grep -q TOKEN_OK && ok "token file -> Authorization header built" || ko "header not built ($out)"

##############################################################################
say ""
say "== F4. Online helpers vs 200 / 404 / malformed =="
cat > "$WORK/t4.sh" <<'EOS'
. "$WORK/lib.sh"
BASE="$BASE"
_use_online_check_tool "$BASE/ok" && echo "CHECK200_OK" || echo "CHECK200_BAD"
_use_online_check_tool "$BASE/notfound" && echo "CHECK404_BAD" || echo "CHECK404_OK"
[ "$(_use_online_reading_tool "$BASE/ok")" = "hello-ok" ] && echo "READ200_OK" || echo "READ200_BAD"
[ -z "$(_use_online_reading_tool "$BASE/notfound")" ] && echo "READ404_OK" || echo "READ404_BAD"
_use_online_downloader "$BASE/ok" "$WORK/dl_ok"
[ "$(cat "$WORK/dl_ok")" = "hello-ok" ] && echo "DL200_OK" || echo "DL200_BAD"
_use_online_downloader "$BASE/notfound" "$WORK/dl_404" 2>/dev/null; rc=$?
# curl without --fail returns 0 and writes the (empty) 404 body; wget returns
# non-zero. Either way the payload must not equal a successful download.
if [ -s "$WORK/dl_404" ]; then echo "DL404_NONEMPTY"; else echo "DL404_EMPTY_rc$rc"; fi
EOS
export WORK BASE
out=$(bash "$WORK/t4.sh" 2>&1)
echo "$out" | grep -q CHECK200_OK && ok "_use_online_check_tool accepts 200" || ko "check 200 ($out)"
echo "$out" | grep -q CHECK404_OK && ok "_use_online_check_tool rejects 404" || ko "check 404 ($out)"
echo "$out" | grep -q READ200_OK && ok "_use_online_reading_tool returns body on 200" || ko "read 200 ($out)"
echo "$out" | grep -q READ404_OK && ok "_use_online_reading_tool returns empty on 404" || ko "read 404 ($out)"
echo "$out" | grep -q DL200_OK && ok "_use_online_downloader saves body on 200" || ko "download 200 ($out)"
if echo "$out" | grep -q DL404_EMPTY; then
	ok "failed download never yields the requested payload (empty file)"
else
	ko "failed download left a non-empty file ($out)"
fi

##############################################################################
say ""
say "== F5. AppImage magic detection + icon extraction block =="
# Extract the real icon block from install.am.
start=$(grep -n '# Check broken/missing icons' "$INSTALLAM" | head -1 | cut -d: -f1)
end=$(grep -n '# Patch .desktop to change paths' "$INSTALLAM" | head -1 | cut -d: -f1)
if [ -n "$start" ] && [ -n "$end" ]; then
	sed -n "${start},$((end-1))p" "$INSTALLAM" > "$WORK/iconblock.sh"
	# The last line should close the block with "fi"
	tail -1 "$WORK/iconblock.sh" | grep -q '^	fi' && ok "extracted icon block ends with 'fi'" || ko "unexpected icon block end: $(tail -1 "$WORK/iconblock.sh")"
else
	ko "could not locate icon block"
fi

# 5a. Magic detection: real AppImage bytes match, a shell script does not.
printf '\x7fELF\x02\x01\x01\x00' > "$WORK/magic_ai"; printf 'AI' >> "$WORK/magic_ai"
printf '#!/bin/sh\necho hi\n' > "$WORK/not_ai"
if head -c10 "$WORK/magic_ai" 2>/dev/null | grep -qa '^.ELF....AI$'; then ok "AppImage magic detected in fixture"; else ko "magic not detected"; fi
if head -c10 "$WORK/not_ai" 2>/dev/null | grep -qa '^.ELF....AI$'; then ko "script wrongly detected as AppImage"; else ok "non-AppImage correctly rejected"; fi

# 5b. Drive the real extraction/move block with a fake extracted dir.
cat > "$WORK/t5.sh" <<'EOS'
set -u
_fit() { cat; }
_use_online_downloader() { :; }     # fallback must not run in the success case
LASTDIRPATH="$WORK/appdir"
pure_arg="myapp"
arg="myapp"
rm -rf "$LASTDIRPATH"; mkdir -p "$LASTDIRPATH/icons" "$LASTDIRPATH/squashfs-root"
# Satisfy the AppImage gate: magic bytes AND the "appimage-extract" string.
{ printf '\x7fELF\x02\x01\x01\x00AI'; printf 'appimage-extract'; } > "$LASTDIRPATH/$pure_arg"
printf 'real-icon-bytes' > "$LASTDIRPATH/squashfs-root/myapp.png"
ln -s /nonexistent-target "$LASTDIRPATH/squashfs-root/broken.png"
cd "$LASTDIRPATH"
. "$WORK/iconblock.sh"
echo "ICONS=$(ls "$LASTDIRPATH/icons" 2>/dev/null | tr '\n' ' ')"
echo "SQUASH=$( [ -d "$LASTDIRPATH/squashfs-root" ] && echo present || echo gone )"
[ "$(cat "$LASTDIRPATH/icons/myapp" 2>/dev/null)" = "real-icon-bytes" ] && echo "MOVE_OK" || echo "MOVE_BAD"
[ ! -e "$LASTDIRPATH/squashfs-root" ] && echo "CLEAN_OK" || echo "CLEAN_BAD"
EOS
export WORK
out=$(bash "$WORK/t5.sh" 2>&1)
echo "$out" | grep -q MOVE_OK && ok "extracted icon moved into icons/ (real code)" || ko "icon not moved ($out)"
echo "$out" | grep -q CLEAN_OK && ok "extracted dir cleaned up" || ko "extracted dir left ($out)"

# 5c. Broken links in icons/ are removed by the block.
cat > "$WORK/t5c.sh" <<'EOS'
set -u
_fit() { cat; }
_use_online_downloader() { :; }
LASTDIRPATH="$WORK/appdir2"
pure_arg="myapp"
arg="myapp"
rm -rf "$LASTDIRPATH"; mkdir -p "$LASTDIRPATH/icons" "$LASTDIRPATH/squashfs-root"
{ printf '\x7fELF\x02\x01\x01\x00AI'; printf 'appimage-extract'; } > "$LASTDIRPATH/$pure_arg"
ln -s /nonexistent "$LASTDIRPATH/icons/deadlink"
printf 'x' > "$LASTDIRPATH/squashfs-root/myapp.png"
cd "$LASTDIRPATH"
. "$WORK/iconblock.sh"
[ ! -e "$LASTDIRPATH/icons/deadlink" ] && echo "DEADLINK_OK" || echo "DEADLINK_BAD"
EOS
export WORK
out=$(bash "$WORK/t5c.sh" 2>&1)
echo "$out" | grep -q DEADLINK_OK && ok "broken icon symlink removed" || ko "dead link kept ($out)"

##############################################################################
say ""
say "== F6. Icon fallback when extraction is impossible =="
# A normal (non-AppImage) app with no icons must fall back to the catalogue.
cat > "$WORK/appsrepo/programs/x86_64/fallbackapp" <<SCRIPT
#!/bin/sh
APP=fallbackapp
mkdir -p "/opt/\$APP/tmp" "/opt/\$APP/icons" && cd "/opt/\$APP/tmp" || exit 1
printf '#!/bin/sh\nset -e\nrm -f /usr/local/bin/fallbackapp\nrm -R -f /opt/fallbackapp\n' > ../remove
chmod a+x ../remove || exit 1
printf 'not-an-appimage\n' > "\$APP"
cd ..
mv ./tmp/"\$APP" ./"\$APP"
chmod a+x ./"\$APP" || exit 1
echo "1.0" > ./version
rm -R -f ./tmp || exit 1
ln -s "/opt/\$APP/\$APP" "/usr/local/bin/fallbackapp"
SCRIPT
chmod +x "$WORK/appsrepo/programs/x86_64/fallbackapp"
printf '◆ fallbackapp : Test fallback : https://example.test : %s/dl/x : 1.0\n' "$BASE" > "$WORK/appsrepo/programs/x86_64-apps"

printf '%s\n' "$WORK/apps" > "$XDG_CONFIG_HOME/appman/appman-config"
touch "$XDG_DATA_HOME/AM/disable-dependencies-prompt"
printf '%s\n' "$WORK/appsrepo" > "$XDG_DATA_HOME/AM/newrepo-on"
cp "$APPMAN" "$HOME/.local/bin/appman"
AM2="$HOME/.local/bin/appman"

AMCATALOGUEICONS="$BASE/dl" "$AM2" -y -i fallbackapp > "$WORK/fb.log" 2>&1
[ -f "$WORK/apps/fallbackapp/version" ] && ok "non-AppImage app installed" || ko "install failed ($(tail -3 "$WORK/fb.log"))"
[ -s "$WORK/apps/fallbackapp/icons/fallbackapp" ] && ok "icon fallback downloaded from the catalogue" || ko "fallback icon missing"

##############################################################################
say ""
say "== F7. template module smoke =="
# The template CLI is interactive/network dependent; smoke-test that the
# module loads and runs without a shell/runtime error, then exits.
cat > "$WORK/tpl.sh" <<'EOS'
#!/usr/bin/env bash
printf '\n\n\n' | "$1" -t
EOS
chmod +x "$WORK/tpl.sh"
timeout 30 "$WORK/tpl.sh" "$AM2" > "$WORK/tpl.log" 2>&1
rc=$?
grep -qiE 'command not found|syntax error|unbound variable' "$WORK/tpl.log" && ko "template smoke produced a shell error" || ok "template module ran without shell error (rc=$rc)"
# It must at least have reached its own logic (not a missing-module error).
grep -qi 'Module not found' "$WORK/tpl.log" && ko "template module missing" || ok "template module present"

##############################################################################
say ""
say "== F8. downgrade proxy wiring =="
# Static: _downgrade must route its URL filter through _alt_gh_filter.
grep -q '_downgrade_entries_filter | _alt_gh_filter' "$MGMT" \
	&& ok "_downgrade pipes through _alt_gh_filter" || ko "_downgrade proxy wiring missing"
grep -q '_alt_gh_on ./AM-rollback' "$MGMT" \
	&& ok "AM-rollback stamped with ALT_GH" || ko "AM-rollback proxy stamp missing"

# Behavioural probe: _alt_gh_filter is a CONDITIONAL filter. It rewrites only
# when GH_API_ALLOWED <= 5 and otherwise emits NOTHING. _downgrade enters its
# proxy branch when GH_API_REMAINING <= 10, but the filter's own test uses
# GH_API_ALLOWED (= remaining - GH_APPS_NUMBER). For remaining in 6..10 the
# filter emits nothing, so entries_list can become empty. This is recorded,
# not asserted as correct.
cat > "$WORK/t9.sh" <<'EOS'
. "$WORK/lib.sh"
ALT_GH="https://alt.example"
for n in 3 5 8; do
  _update_determine_gh_apps_number() { GH_API_ALLOWED=$n; }
  out=$(printf 'https://api.github.com/x\n' | _alt_gh_filter)
  printf 'Q%s=[%s]\n' "$n" "$out"
done
_update_determine_gh_apps_number() { :; }   # GH_API_ALLOWED unset
out=$(printf 'https://api.github.com/x\n' | _alt_gh_filter 2>/dev/null)
printf 'QUNSET=[%s]\n' "$out"
EOS
export WORK
out=$(bash "$WORK/t9.sh" 2>&1)
echo "$out" | grep -q 'Q3=\[https://alt.example/x\]' && ok "filter rewrites at quota 3" || ko "quota 3 ($out)"
echo "$out" | grep -q 'Q5=\[https://alt.example/x\]' && ok "filter rewrites at quota 5 (boundary)" || ko "quota 5 ($out)"
if echo "$out" | grep -q 'Q8=\[\]'; then
	say "    NOTE: _alt_gh_filter emits nothing at GH_API_ALLOWED=8 while"
	say "          _downgrade's proxy gate is GH_API_REMAINING<=10 -> potential empty list (upstream-inherited)"
fi
echo "$out" | grep -q 'QUNSET=\[\]' \
	&& say "    NOTE: with GH_API_ALLOWED unset the numeric test is false and the filter emits nothing" || true

say ""
say "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1

#!/usr/bin/env bash
##############################################################################
# AppMan2 self-update / release transition tests
#
# Verifies the update path from the previous fork release to this integrated
# release using LOCAL repositories (file://), with no network, no credentials
# and no changes to the host installation.
#
#   U1. self-update replaces the executable + modules from $APPMAN2_REPO only
#       (explicit source-ownership markers)
#   U2. retained AppMan2 behavior survives the update
#   U3. a failed manager download leaves the previous installation usable
#       and non-truncated
#   U4. mixed old/new modules: a module missing from a partial release is
#       retained AND the affected operation (install) still works
#
# The "previous release" is taken from git (default ref: main) when available,
# giving a genuine version skew; otherwise a version-downgraded copy is used.
# Override with PREV_REF=<ref>.
#
# Usage: ./run-update-tests.sh [/path/to/appman]
##############################################################################

set -u

APPMAN="${1:-$(cd "$(dirname "$0")/.." && pwd)/appman}"
[ -x "$APPMAN" ] || { echo "ERROR: appman not found at $APPMAN" >&2; exit 1; }
ROOT="$(cd "$(dirname "$APPMAN")" && pwd)"
PREV_REF="${PREV_REF:-main}"

WORK="$(mktemp -d)"
PASS=0
FAIL=0

say()  { printf '%s\n' "$*"; }
ok()   { PASS=$((PASS+1)); printf '  \342\234\223 %s\n' "$*"; }
ko()   { FAIL=$((FAIL+1)); printf '  \342\234\227 %s\n' "$*"; }

cleanup() {
	[ -n "${KEEP:-}" ] && cp -r "$WORK" /tmp/opencode/keepupdate 2>/dev/null
	rm -rf "$WORK" 2>/dev/null
}
trap cleanup EXIT

mkdir -p "$WORK"/{rel/modules,prev,emptyrepo,home/.config/appman}
mkdir -p "$WORK"/home/.local/share/AM "$WORK"/home/.cache "$WORK"/home/.local/bin
mkdir -p "$WORK"/appsrepo/programs/x86_64
export HOME="$WORK/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"

# ---------------------------------------------------------------------------
# Release fixture (this tree): version 1.1-3, release markers on appman + modules
# ---------------------------------------------------------------------------
cp "$APPMAN" "$WORK/rel/appman"
sed -i 's/^AMVERSION="[^"]*"/AMVERSION="1.1-3"/' "$WORK/rel/appman"
printf '# APPMAN2-RELEASE-MARKER-1.1-3\n' >> "$WORK/rel/appman"
for m in database install management template; do
	{ printf '# APPMAN2-RELEASE-MODULE-1.1-3\n'; cat "$ROOT/modules/$m.am"; } > "$WORK/rel/modules/$m.am"
done

# ---------------------------------------------------------------------------
# Previous release fixture: genuine git revision if available, else downgrade
# ---------------------------------------------------------------------------
PREV_SOURCE="downgrade"
if command -v git >/dev/null 2>&1 && [ -e "$ROOT/.git" ]; then
	git -C "$ROOT" config --global --add safe.directory "$ROOT" 2>/dev/null || true
	for ref in "$PREV_REF" "origin/$PREV_REF"; do
		if git -C "$ROOT" cat-file -e "$ref:appman" 2>/dev/null; then
			PREV_REF="$ref"
			PREV_SOURCE="git:$ref"
			git -C "$ROOT" show "$ref:appman" > "$WORK/prev/appman"
			for m in database install management template; do
				git -C "$ROOT" show "$ref:modules/$m.am" > "$WORK/prev/$m.am"
			done
			break
		fi
	done
fi
if [ "$PREV_SOURCE" = "downgrade" ]; then
	cp "$WORK/rel/appman" "$WORK/prev/appman"
	sed -i 's/^AMVERSION="[^"]*"/AMVERSION="1.1-2"/' "$WORK/prev/appman"
	sed -i 's/# APPMAN2-RELEASE-MARKER-1.1-3/# APPMAN2-PREVIOUS-MARKER-1.1-2/' "$WORK/prev/appman"
	for m in database install management template; do
		cp "$WORK/rel/modules/$m.am" "$WORK/prev/$m.am"
	done
fi
sed -i 's/^AMVERSION="[^"]*"/AMVERSION="1.1-2"/' "$WORK/prev/appman"
printf '# APPMAN2-PREVIOUS-MARKER-1.1-2\n' >> "$WORK/prev/appman"
for m in database install management template; do
	{ printf '# APPMAN2-PREV-MODULE-1.1-2\n'; cat "$WORK/prev/$m.am"; } > "$WORK/prev/$m.am.tmp" && mv "$WORK/prev/$m.am.tmp" "$WORK/prev/$m.am"
done

# ---------------------------------------------------------------------------
# AppMan configuration (fresh home; local app DB so everything stays offline)
# ---------------------------------------------------------------------------
printf '%s\n' "$WORK/apps" > "$XDG_CONFIG_HOME/appman/appman-config"
touch "$XDG_DATA_HOME/AM/disable-dependencies-prompt"
printf '# AppMan2 test fixture\nthird_party_flags="soarpkg"\n' > "$XDG_DATA_HOME/AM/am-extras"
printf '%s\n' "$WORK/appsrepo" > "$XDG_DATA_HOME/AM/newrepo-on"
mkdir -p "$WORK/apps"

# A network-free app used to exercise the affected operation (install).
cat > "$WORK/appsrepo/programs/x86_64/appx" <<'SCRIPT'
#!/bin/sh
APP=appx
mkdir -p "/opt/$APP/tmp" "/opt/$APP/icons" && cd "/opt/$APP/tmp" || exit 1
printf '#!/bin/sh\nset -e\nrm -f /usr/local/bin/appx\nrm -R -f /opt/appx\n' > ../remove
chmod a+x ../remove || exit 1
printf 'payload\n' > "$APP"
cd ..
mv ./tmp/"$APP" ./"$APP"
chmod a+x ./"$APP" || exit 1
echo "1.0" > ./version
rm -R -f ./tmp || exit 1
ln -s "/opt/$APP/$APP" "/usr/local/bin/appx"
SCRIPT
chmod +x "$WORK/appsrepo/programs/x86_64/appx"
printf '◆ appx : Test app : https://example.test : http://127.0.0.1:1/appx : 1.0\n' > "$WORK/appsrepo/programs/x86_64-apps"

install_prev() {
	cp "$WORK/prev/appman" "$HOME/.local/bin/appman"
	chmod +x "$HOME/.local/bin/appman"
	mkdir -p "$WORK/apps/appman/modules"
	cp "$WORK/prev/"*.am "$WORK/apps/appman/modules/" 2>/dev/null || true
}
AM2="$HOME/.local/bin/appman"

say "previous release source: $PREV_SOURCE"

##############################################################################
say ""
say "== U1. Update ships executable + modules from APPMAN2_REPO only =="
install_prev
before=$("$AM2" -v 2>/dev/null | tail -1)
echo "$before" | grep -q '1.1-2' && ok "starting version is 1.1-2" || ko "unexpected start version: $before"
grep -q 'APPMAN2-PREVIOUS-MARKER' "$HOME/.local/bin/appman" && ok "previous binary in place" || ko "previous binary missing"

APPMAN2_REPO="file://$WORK/rel" "$AM2" -s > "$WORK/u1.log" 2>&1
after=$("$AM2" -v 2>/dev/null | tail -1)
echo "$after" | grep -q '1.1-3' && ok "self-updated to 1.1-3" || ko "not updated: $after"
grep -q 'RELEASE-MARKER-1.1-3' "$HOME/.local/bin/appman" && ok "binary came from the AppMan2 release repo" || ko "binary not from release repo"
grep -q 'APPMAN2-PREVIOUS-MARKER' "$HOME/.local/bin/appman" && ko "previous binary still present" || ok "previous binary replaced"
grep -qi 'ivan-hc/AppMan' "$WORK/u1.log" && ko "update referenced ivan-hc/AppMan" || ok "update never referenced ivan-hc/AppMan"
if [ -f "$WORK/apps/appman/modules/install.am" ]; then
	if grep -q 'APPMAN2-PREV-MODULE' "$WORK/apps/appman/modules/install.am"; then
		ko "module not updated (previous module still present)"
	else
		grep -q 'APPMAN2-RELEASE-MODULE' "$WORK/apps/appman/modules/install.am" \
			&& ok "modules updated from the release repo" || ko "module has no release marker"
	fi
else
	ko "no modules installed after update"
fi
[ -f "$XDG_CONFIG_HOME/appman/appman-config" ] && ok "configuration preserved" || ko "configuration lost"

##############################################################################
say ""
say "== U2. Retained AppMan2 behavior survives the update =="
grep -q 'APPMAN2_REPO' "$HOME/.local/bin/appman" && ok "APPMAN2_REPO config retained after update" || ko "APPMAN2_REPO lost"
grep -q '_setup_stall_guard()' "$HOME/.local/bin/appman" && ok "stalled-download guard retained" || ko "stall guard lost"
grep -q '_update_report_results()' "$HOME/.local/bin/appman" && ok "update reporting retained" || ko "update reporting lost"
grep -q '_auto_update_appimage()' "$HOME/.local/bin/appman" && ok "automatic AppImage updates retained" || ko "auto-update lost"
"$AM2" -f > "$WORK/u2.log" 2>&1 && ok "manager still runs after update (-f)" || ko "manager broken after update"

##############################################################################
say ""
say "== U3. Failed manager download leaves the old install usable =="
install_prev
APPMAN2_REPO="file://$WORK/emptyrepo" "$AM2" -s > "$WORK/u3.log" 2>&1
v=$("$AM2" -v 2>/dev/null | tail -1)
echo "$v" | grep -q '1.1-2' && ok "still reports previous version after failed update" || ko "version changed unexpectedly: $v"
bash -n "$HOME/.local/bin/appman" && ok "installed binary is still valid shell (not truncated)" || ko "installed binary is corrupt"
grep -q 'APPMAN2-PREVIOUS-MARKER' "$HOME/.local/bin/appman" && ok "previous binary intact after failed update" || ko "previous binary changed"
"$AM2" -f > /dev/null 2>&1 && ok "previous install still runnable after failed update" || ko "previous install broken"
grep -q 'exit 1' "$WORK/u3.log" && ko "failed update aborted the whole command" || ok "failed update did not hard-abort"

##############################################################################
say ""
say "== U4. Mixed old/new modules: retained module still performs its operation =="
install_prev
# Release without install.am (simulate a partially published release).
cp -r "$WORK/rel" "$WORK/rel_partial"
rm -f "$WORK/rel_partial/modules/install.am"
APPMAN2_REPO="file://$WORK/rel_partial" "$AM2" -s > "$WORK/u4.log" 2>&1
v=$("$AM2" -v 2>/dev/null | tail -1)
echo "$v" | grep -q '1.1-3' && ok "manager upgraded despite a missing module" || ko "manager did not upgrade: $v"
"$AM2" -f > /dev/null 2>&1 && ok "manager starts with a partial module set" || ko "manager does not start"

# The old install.am must not have been emptied/truncated.
[ -s "$WORK/apps/appman/modules/install.am" ] && ok "existing install.am not emptied by the partial release" || ko "install.am was emptied"
grep -q 'APPMAN2-PREV-MODULE' "$WORK/apps/appman/modules/install.am" && ok "existing install.am retained (missing in partial release)" || ko "install.am unexpectedly replaced"
bash -n "$WORK/apps/appman/modules/install.am" 2>/dev/null && ok "retained install.am is valid shell" || ko "retained install.am is corrupt"

# Beyond "starts + valid shell": exercise the affected operation. install.am
# is the retained module, so run a real install with the new manager, then a
# remove with the (new) management.am.
"$AM2" -y -i appx > "$WORK/u4-install.log" 2>&1
[ -f "$WORK/apps/appx/version" ] && ok "install works with the retained install.am" || ko "install failed with retained module ($(tail -2 "$WORK/u4-install.log"))"
"$AM2" -y -R appx > "$WORK/u4-remove.log" 2>&1
[ ! -d "$WORK/apps/appx" ] && ok "remove works after the mixed-version update" || ko "remove failed after update"
# LIMITATION: the retained module is an older generation but not arbitrary;
# this proves the retained install.am can install and the manager stays
# consistent, not that every possible old/new module combination is safe.

say ""
say "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1

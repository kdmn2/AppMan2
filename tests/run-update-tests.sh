#!/usr/bin/env bash
##############################################################################
# AppMan2 self-update / release transition tests
#
# Verifies the update path from the previous fork release to this integrated
# release using a LOCAL AppMan2 repo (file://), with no network and no
# changes to the host installation.
#
#   U1. self-update replaces the executable + modules from $APPMAN2_REPO only
#       (explicit source-ownership markers)
#   U2. retained AppMan2 behavior survives the update
#   U3. a failed manager download leaves the previous installation usable
#       and non-truncated
#   U4. mixed old/new modules: a missing module in the release does not
#       corrupt the installed modules, and the manager still runs
#
# Usage: ./run-update-tests.sh [/path/to/appman]
##############################################################################

set -u

APPMAN="${1:-$(cd "$(dirname "$0")/.." && pwd)/appman}"
[ -x "$APPMAN" ] || { echo "ERROR: appman not found at $APPMAN" >&2; exit 1; }
ROOT="$(cd "$(dirname "$APPMAN")" && pwd)"

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
export HOME="$WORK/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"

# ---------------------------------------------------------------------------
# Build two local "releases":
#   prev  = previous fork release (version 1.1-2, previous marker)
#   rel   = this integrated release (version 1.1-3, release marker)
# Both are derived from the tree under test so the mechanics are exact; the
# version + marker differ so ownership is observable.
# ---------------------------------------------------------------------------
cp "$APPMAN" "$WORK/rel/appman"
cp "$ROOT/modules/"*.am "$WORK/rel/modules/"
sed -i 's/^AMVERSION="[^"]*"/AMVERSION="1.1-3"/' "$WORK/rel/appman"
printf '# APPMAN2-RELEASE-MARKER-1.1-3\n' >> "$WORK/rel/appman"

cp "$WORK/rel/appman" "$WORK/prev/appman"
sed -i 's/^AMVERSION="[^"]*"/AMVERSION="1.1-2"/' "$WORK/prev/appman"
sed -i 's/# APPMAN2-RELEASE-MARKER-1.1-3/# APPMAN2-PREVIOUS-MARKER-1.1-2/' "$WORK/prev/appman"
cp "$ROOT/modules/"*.am "$WORK/prev/" 2>/dev/null || true
# Mark the previous release's install.am with a valid comment marker (instead
# of mutating a function, which could make the fixture invalid) so we can tell
# which module is loaded after the update.
{ printf '# OLD-INSTALL-MODULE-MARKER-1.1-2\n'; cat "$ROOT/modules/install.am"; } > "$WORK/prev/install.am"

# AppMan configuration (fresh home, points apps at $WORK/apps)
printf '%s\n' "$WORK/apps" > "$XDG_CONFIG_HOME/appman/appman-config"
touch "$XDG_DATA_HOME/AM/disable-dependencies-prompt"
mkdir -p "$WORK/apps"

install_prev() {
	cp "$WORK/prev/appman" "$HOME/.local/bin/appman"
	chmod +x "$HOME/.local/bin/appman"
	# Pre-seed the previous modules so we can observe an upgrade in place.
	mkdir -p "$WORK/apps/appman/modules"
	cp "$WORK/prev/"*.am "$WORK/apps/appman/modules/" 2>/dev/null || true
}
AM2="$HOME/.local/bin/appman"

##############################################################################
say ""
say "== U1. Update ships executable + modules from APPMAN2_REPO only =="
install_prev
before=$("$AM2" -v 2>/dev/null | tail -1)
echo "$before" | grep -q '1.1-2' && ok "starting version is 1.1-2" || ko "unexpected start version: $before"
grep -q 'PREVIOUS-MARKER' "$HOME/.local/bin/appman" && ok "previous binary in place" || ko "previous binary missing"

APPMAN2_REPO="file://$WORK/rel" "$AM2" -s > "$WORK/u1.log" 2>&1
after=$("$AM2" -v 2>/dev/null | tail -1)
echo "$after" | grep -q '1.1-3' && ok "self-updated to 1.1-3" || ko "not updated: $after"
grep -q 'RELEASE-MARKER-1.1-3' "$HOME/.local/bin/appman" && ok "binary came from the AppMan2 release repo" || ko "binary not from release repo"
grep -q 'PREVIOUS-MARKER' "$HOME/.local/bin/appman" && ko "previous binary still present (update did not replace)" || ok "previous binary replaced"
grep -qi 'ivan-hc/AppMan' "$WORK/u1.log" && ko "update referenced ivan-hc/AppMan" || ok "update never referenced ivan-hc/AppMan"
# Module ownership: the release install.am marker must now be present.
if [ -f "$WORK/apps/appman/modules/install.am" ]; then
	if grep -q 'OLD-INSTALL-MODULE-MARKER' "$WORK/apps/appman/modules/install.am"; then
		ko "module not updated (old marker still present)"
	else
		ok "modules updated from the release repo"
	fi
else
	ko "no modules installed after update"
fi
# Config + apps preserved.
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
# APPMAN2_REPO with no appman file -> the download fails.
APPMAN2_REPO="file://$WORK/emptyrepo" "$AM2" -s > "$WORK/u3.log" 2>&1
v=$("$AM2" -v 2>/dev/null | tail -1)
echo "$v" | grep -q '1.1-2' && ok "still reports previous version after failed update" || ko "version changed unexpectedly: $v"
bash -n "$HOME/.local/bin/appman" && ok "installed binary is still valid shell (not truncated)" || ko "installed binary is corrupt"
grep -q 'PREVIOUS-MARKER' "$HOME/.local/bin/appman" && ok "previous binary intact after failed update" || ko "previous binary changed"
"$AM2" -f > /dev/null 2>&1 && ok "previous install still runnable after failed update" || ko "previous install broken"
grep -q 'exit 1' "$WORK/u3.log" && ko "failed update aborted the whole command" || ok "failed update did not hard-abort the installer"

##############################################################################
say ""
say "== U4. Mixed old/new modules are handled =="
install_prev
# Release without a module file (simulate a partially published release).
cp -r "$WORK/rel" "$WORK/rel_partial"
rm -f "$WORK/rel_partial/modules/install.am"
APPMAN2_REPO="file://$WORK/rel_partial" "$AM2" -s > "$WORK/u4.log" 2>&1
# The manager must still upgrade to 1.1-3 and remain runnable.
v=$("$AM2" -v 2>/dev/null | tail -1)
echo "$v" | grep -q '1.1-3' && ok "manager upgraded despite a missing module" || ko "manager did not upgrade: $v"
"$AM2" -f > /dev/null 2>&1 && ok "manager runnable with a partial module set" || ko "manager broken with partial modules"
# The old install.am must not have been replaced by an empty/truncated file.
if [ -s "$WORK/apps/appman/modules/install.am" ]; then
	ok "existing install.am not emptied by the partial release"
else
	ko "install.am was emptied by the partial release"
fi
grep -q 'OLD-INSTALL-MODULE-MARKER' "$WORK/apps/appman/modules/install.am" \
	&& ok "existing install.am kept (missing in partial release)" || ko "install.am unexpectedly replaced"
bash -n "$WORK/apps/appman/modules/install.am" 2>/dev/null && ok "existing install.am still valid shell" || ko "install.am is corrupt"

say ""
say "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1

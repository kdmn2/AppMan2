#!/usr/bin/env bash
##############################################################################
# Syntax-check every shell file in the repository.
#
# `bash -n file1 file2 ...` only parses the FIRST file, so each file is
# checked separately; any failure makes the whole run fail.
#
# Usage: bash tests/syntax-check.sh
##############################################################################

set -u
cd "$(dirname "$0")/.." || exit 1

files=(appman INSTALL INSTALL-ALONGSIDE modules/*.am tests/*.sh)
fail=0
checked=0

for f in "${files[@]}"; do
	[ -f "$f" ] || continue
	checked=$((checked + 1))
	if bash -n "$f"; then
		printf 'ok   %s\n' "$f"
	else
		printf 'FAIL %s\n' "$f" >&2
		fail=1
	fi
done

printf '\nchecked %d file(s)\n' "$checked"
[ "$fail" -eq 0 ] || { printf 'SYNTAX ERRORS FOUND\n' >&2; exit 1; }

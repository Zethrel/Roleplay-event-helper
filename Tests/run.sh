#!/bin/sh
# Run every test suite. Set VERBOSE=1 to see passing checks too.
#
# Requires Lua 5.1, the version the WoW client runs:
#   apt-get install lua5.1   /   brew install lua@5.1

set -u
cd "$(dirname "$0")/.."

LUA="${LUA:-lua5.1}"
if ! command -v "$LUA" >/dev/null 2>&1; then
	echo "error: $LUA not found. Install Lua 5.1 or set LUA=<interpreter>." >&2
	exit 127
fi

status=0
for suite in Tests/M*.lua; do
	name=$(basename "$suite" .lua)
	if [ "${VERBOSE:-0}" = "1" ]; then
		"$LUA" "$suite" || status=1
	else
		output=$("$LUA" "$suite" 2>&1) || status=1
		printf '%s: %s\n' "$name" "$(printf '%s' "$output" | tail -n 1)"
		printf '%s' "$output" | grep -E '^  FAIL' || true
	fi
done

if [ "$status" -eq 0 ]; then
	echo "OK"
else
	echo "FAILED"
fi
exit "$status"

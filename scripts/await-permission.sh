#!/bin/sh
# Called by `make install` after the login agent is loaded. Waits for the agent
# to report in. If it is waiting for the permission, asks the user to turn it
# on, then waits for the agent to start with it. The agent restarts itself in
# place once it sees the grant; if it has not started after a few seconds, the
# script restarts it through launchd.
#
# Usage: await-permission.sh SERVICE LOG BINARY FIRST_NEW_LOG_LINE

set -eu

SERVICE=$1
LOG=$2
BINARY=$3
FIRST_LINE=$4

STARTED='started version='
WAITING='waiting for permission'
REPORT_SECONDS=10
SETTINGS_URL='x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'
# The build is signed ad hoc, so macOS ties the grant to one build. An entry
# left from an earlier build stays in the list but no longer matches.
REBUILD_HINT="If menubar-guard is already in the list from an earlier build, select it, remove
it with the - button, then add $BINARY again with +.
Switching the old entry off and on does not work for a new build."

new_lines() {
    tail -n "+$FIRST_LINE" "$LOG" 2>/dev/null || true
}

# Waits until a new log line matches the pattern. Fails after REPORT_SECONDS.
wait_for() {
    seconds=0
    while [ "$seconds" -lt "$REPORT_SECONDS" ]; do
        if new_lines | grep -Eq "$1"; then
            return 0
        fi
        sleep 1
        seconds=$((seconds + 1))
    done
    return 1
}

has_started() {
    new_lines | grep -q "$STARTED"
}

if ! wait_for "$STARTED|$WAITING"; then
    echo "The agent has not reported in yet. Check it with: make status"
    exit 0
fi

if has_started; then
    echo "menubar-guard is running with the permission."
    exit 0
fi

echo ""
echo "menubar-guard needs the permission. In System Settings > Privacy & Security >"
echo "Device Control and Data Access, turn on:"
echo "    $BINARY"
echo "$REBUILD_HINT"

if [ ! -t 0 ]; then
    echo "The agent picks up the permission on its own within a few seconds. Then: make status"
    exit 0
fi

open "$SETTINGS_URL" >/dev/null 2>&1 || true

while true; do
    printf 'Type yes when it is on: '
    if ! read -r answer; then
        echo ""
        echo "The agent picks up the permission on its own within a few seconds. Then: make status"
        exit 0
    fi
    case "$answer" in
        yes | y | YES | Y) break ;;
        *) echo "Type yes once it is on, or press Ctrl-C to finish later." ;;
    esac
done

# The agent notices the grant on its own within a second or two.
if wait_for "$STARTED"; then
    echo "menubar-guard is running with the permission."
    exit 0
fi

FIRST_LINE=$(($(wc -l <"$LOG") + 1))
launchctl kickstart -k "$SERVICE"

if wait_for "$STARTED|$WAITING" && has_started; then
    echo "menubar-guard is running with the permission."
    exit 0
fi

echo "menubar-guard still has no permission."
echo "$REBUILD_HINT"
echo "Then run: make restart"
exit 1

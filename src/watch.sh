#!/bin/sh
# Lua runs for one short status request each minute; idle time is a plain sleep.
umask 077
BASE=/usr/lib/nuist-srun
interval=$(/usr/bin/lua "$BASE/srun.lua" interval) || exit 1
case "$interval" in ''|*[!0-9]*) exit 1;; esac
delay=$interval
previous=''
child=''
trap '[ -z "$child" ] || kill "$child" 2>/dev/null; exit 0' INT TERM
while :; do
    if message=$(/usr/bin/lua "$BASE/srun.lua" once); then
        delay=$interval
    else
        delay=$((delay * 2))
        [ "$delay" -le 1800 ] || delay=1800
        message="$message; retry_in=${delay}s"
    fi
    if [ "$message" != "$previous" ]; then
        logger -t nuist-srun "$message"
        previous=$message
    fi
    sleep "$delay" &
    child=$!
    wait "$child"
    child=''
done

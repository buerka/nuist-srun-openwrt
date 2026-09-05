#!/bin/sh
# Keep credentials unless the operator explicitly supplies --purge.
set -eu
ROOT=${DESTDIR:-}
case "$ROOT" in ''|/*) ;; *) echo 'DESTDIR must be an absolute path' >&2; exit 1;; esac
[ "$ROOT" != / ] || { echo 'Omit DESTDIR for a live uninstall' >&2; exit 1; }
case "${1:-}" in ''|--purge) ;; *) echo 'Usage: sh uninstall.sh [--purge]' >&2; exit 1;; esac
if [ -z "$ROOT" ]; then
    [ "$(id -u)" = 0 ] || { echo 'Run as root on OpenWrt' >&2; exit 1; }
    if [ -x /etc/init.d/nuist-srun ]; then
        /etc/init.d/nuist-srun stop
        /etc/init.d/nuist-srun disable
    fi
fi
rm -f "$ROOT/usr/lib/nuist-srun/srun.lua" "$ROOT/usr/lib/nuist-srun/srun_crypto.lua" \
    "$ROOT/usr/lib/nuist-srun/watch.sh" "$ROOT/etc/init.d/nuist-srun"
rmdir "$ROOT/usr/lib/nuist-srun" 2>/dev/null || true
if [ "${1:-}" = --purge ]; then
    rm -f "$ROOT/etc/nuist-srun.json"
    echo 'Removed the program and private configuration.'
else
    echo 'Removed the program; kept /etc/nuist-srun.json.'
fi

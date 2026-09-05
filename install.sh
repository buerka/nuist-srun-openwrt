#!/bin/sh
# Install or update the code; preserve an existing private configuration.
set -eu
umask 077
cd "$(dirname "$0")"
ROOT=${DESTDIR:-}
case "$ROOT" in ''|/*) ;; *) echo 'DESTDIR must be an absolute path' >&2; exit 1;; esac
[ "$ROOT" != / ] || { echo 'Omit DESTDIR for a live install' >&2; exit 1; }
if [ -z "$ROOT" ]; then
    [ "$(id -u)" = 0 ] || { echo 'Run as root on OpenWrt' >&2; exit 1; }
    for tool in lua curl logger; do command -v "$tool" >/dev/null || exit 1; done
    lua -e 'assert(require("nixio").bit); assert(require("luci.jsonc").parse)'
    lua tests/test_crypto.lua
fi
for file in src/srun.lua src/srun_crypto.lua src/watch.sh nuist-srun.init config.example.json; do
    [ -f "$file" ] && [ ! -L "$file" ] || { echo "Invalid source: $file" >&2; exit 1; }
done
target="$ROOT/usr/lib/nuist-srun"
service="$ROOT/etc/init.d/nuist-srun"
config="$ROOT/etc/nuist-srun.json"
for path in "$target" "$service" "$config"; do
    [ ! -L "$path" ] || { echo "Refusing symlink: $path" >&2; exit 1; }
done
mkdir -p "$target" "$ROOT/etc/init.d"
running=0
if [ -z "$ROOT" ] && [ -x "$service" ] && "$service" status >/dev/null 2>&1; then
    running=1
    "$service" stop
fi
copy_atomic() {
    tmp=$(mktemp "$2.XXXXXX")
    cp "$1" "$tmp"
    chmod "$3" "$tmp"
    mv -f "$tmp" "$2"
}
copy_atomic src/srun.lua "$target/srun.lua" 644
copy_atomic src/srun_crypto.lua "$target/srun_crypto.lua" 644
copy_atomic src/watch.sh "$target/watch.sh" 755
copy_atomic nuist-srun.init "$service" 755
if [ ! -e "$config" ]; then
    copy_atomic config.example.json "$config" 600
    echo 'Created /etc/nuist-srun.json with empty credentials; edit it before starting.'
else
    echo 'Preserved the existing /etc/nuist-srun.json.'
fi
if [ "$running" = 1 ]; then
    "$service" start
    echo 'Restarted the previously running service.'
else
    echo 'Installed. The service has not been started or enabled.'
fi

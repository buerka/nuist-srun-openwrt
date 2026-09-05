"""Run the offline release checks. No network or router access is required."""
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile

from check_public import check, ROOT


def run(*command, env=None, success=True):
    result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True)
    if (result.returncode == 0) != success:
        raise AssertionError(f"Command failed expectation: {command}\n{result.stdout}{result.stderr}")
    return result.stdout.strip()


def test_install():
    with tempfile.TemporaryDirectory(prefix="srun-install-test-") as temporary:
        staging = Path(temporary) / "root"
        env = dict(os.environ, DESTDIR=str(staging))
        config = staging / "etc/nuist-srun.json"
        service = staging / "etc/init.d/nuist-srun"
        program = staging / "usr/lib/nuist-srun/srun.lua"
        run("sh", "install.sh", env=env)
        assert config.read_bytes() == (ROOT / "config.example.json").read_bytes()
        assert stat.S_IMODE(config.stat().st_mode) == 0o600
        assert service.stat().st_mode & stat.S_IXUSR
        assert program.read_bytes() == (ROOT / "src/srun.lua").read_bytes()
        settings = json.loads(config.read_text())
        settings.update(username="demo@campus", password="synthetic-install-password")
        config.write_text(json.dumps(settings))
        preserved = config.read_bytes()
        run("sh", "install.sh", env=env)
        assert config.read_bytes() == preserved
        run("sh", "uninstall.sh", env=env)
        assert not service.exists() and not program.exists()
        assert config.read_bytes() == preserved
        run("sh", "install.sh", env=env)
        assert config.read_bytes() == preserved
        run("sh", "uninstall.sh", "--purge", env=env)
        assert not config.exists()
        outside = Path(temporary) / "sentinel"
        outside.write_text("keep")
        config.symlink_to(outside)
        run("sh", "install.sh", env=env, success=False)
        assert outside.read_text() == "keep"
        run("sh", "install.sh", env=dict(env, DESTDIR="relative"), success=False)
    print("PASS: staged install, update, uninstall, purge and symlink protection")


def main():
    lua = os.environ.get("LUA", "lua")
    if not shutil.which(lua):
        raise SystemExit("Lua is required; install Lua 5.1 + LuaBitOp or Lua 5.3+.")
    print(run(lua, "tests/test_crypto.lua"))
    print(run(lua, "tests/test_client.lua"))
    for file in ("install.sh", "uninstall.sh", "nuist-srun.init", "src/watch.sh"):
        run("sh", "-n", file)
    print("PASS: shell syntax")
    test_install()
    check()


if __name__ == "__main__":
    main()

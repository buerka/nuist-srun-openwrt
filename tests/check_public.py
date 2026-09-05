"""Small, offline guard against accidentally committing deployment artifacts."""
import ipaddress
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
FORBIDDEN_DIRS = {"private", "captures", "reference", "__pycache__"}
FORBIDDEN_SUFFIXES = {".har", ".pcap", ".pcapng", ".log", ".pem", ".key", ".zip", ".gz", ".tar", ".pyc"}
RESERVED = [ipaddress.ip_network(n) for n in ("192.0.2.0/24", "198.51.100.0/24", "203.0.113.0/24")]
TOKEN = re.compile(r"(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----)")


def check():
    if (ROOT / ".git").exists():
        names = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split("\0")
        files = [ROOT / name for name in names if name]
    else:
        files = [p for p in ROOT.rglob("*") if p.is_file() and "__pycache__" not in p.parts]
    assert files, "No release files found"
    for path in files:
        rel = path.relative_to(ROOT)
        assert not path.is_symlink(), f"Symlink in release: {rel}"
        assert not FORBIDDEN_DIRS.intersection(rel.parts), f"Private directory: {rel}"
        assert path.suffix.lower() not in FORBIDDEN_SUFFIXES, f"Capture/archive/key file: {rel}"
        assert path.name not in {"config.json", "nuist-srun.json"}, f"Deployment configuration: {rel}"
        assert not path.name.startswith(".env"), f"Environment file: {rel}"
        assert not path.name.endswith(".local.json"), f"Local configuration: {rel}"
        body = path.read_text(encoding="utf-8")
        assert not TOKEN.search(body), f"Possible credential in {rel}"
        # Construct markers to avoid matching this checker itself.
        assert "/" + "Users/" not in body and "C:" + "\\Users\\" not in body, f"Personal path in {rel}"
        for value in re.findall(r"(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?![\w.])", body):
            ip = ipaddress.ip_address(value)
            assert any(ip in net for net in RESERVED), f"Non-documentation IPv4 address in {rel}"
    example = json.loads((ROOT / "config.example.json").read_text())
    assert example["username"] == example["password"] == "", "Example must have empty credentials"
    print(f"PASS: privacy guard ({len(files)} release files)")


if __name__ == "__main__":
    check()

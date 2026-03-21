#!/usr/bin/env python3
"""
Run luau-lsp analyze for given paths and print a count of errors at the end.

Usage:
  python tools/luau_analyze_count.py [paths...]

If no paths are provided, analyzes `server` by default.
"""

import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def find_luau_lsp() -> str:
    """Locate luau-lsp binary across common environments.

    Priority:
    1) LUAU_LSP env var
    2) luau-lsp on PATH
    3) Aftman install (~/.aftman/bin) with platform-appropriate name
    4) Windows default from earlier scripts
    """
    # 1) Explicit override
    env_path = os.getenv("LUAU_LSP")
    if env_path and Path(env_path).exists():
        return env_path

    # 2) PATH
    on_path = shutil.which("luau-lsp")
    if on_path:
        return on_path

    # 3) Repo-local bin (tools/bin)
    repo_bin = ROOT / "tools" / "bin"
    for name in ("luau-lsp", "luau-lsp.exe"):
        p = repo_bin / name
        if p.exists():
            return str(p)

    # 4) Aftman default bin
    home = Path.home()
    aftman_bin = home / ".aftman" / "bin"
    system = platform.system().lower()
    candidates = []
    if system.startswith("win"):
        candidates = [aftman_bin / "luau-lsp.exe", aftman_bin / "luau-lsp"]
    else:
        candidates = [aftman_bin / "luau-lsp", aftman_bin / "luau-lsp.exe"]
    for c in candidates:
        if c.exists():
            return str(c)

    # 5) Legacy Windows path used in some helper scripts
    legacy = str(home / ".aftman" / "bin" / "luau-lsp.exe")
    if Path(legacy).exists():
        return legacy

    # Final fallback: assume it's in PATH (let subprocess error surface clearly)
    return "luau-lsp"

def main(argv: list[str]) -> int:
    # Try to refresh Rojo sourcemap if rojo is available and sourcemap.json is stale/missing
    try:
        import shutil as _sh
        import subprocess as _sp
        sm = ROOT / "sourcemap.json"
        rojo = _sh.which("rojo")
        if rojo:
            _sp.run([rojo, "sourcemap", "default.project.json", "--output", "sourcemap.json"], cwd=ROOT, check=False)
    except Exception:
        pass
    # Match Makefile check target behavior: analyze whole repo by default
    targets = argv or ["."]
    luau = find_luau_lsp()
    cmd = [
        luau,
        "analyze",
        "--platform",
        "roblox",
        "--definitions",
        "tools/defs/roblox-globalTypes.d.luau",
        "--sourcemap",
        "sourcemap.json",
        "--no-strict-dm-types",
        "--ignore=DevPackages/**",
        "--ignore=tools/**",
        "--ignore=tests/**",
        "--ignore=scripts/**",
        *targets,
    ]
    proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    output = proc.stderr + proc.stdout
    sys.stdout.write(output)
    # Count common luau-lsp error lines (dedupe by full line)
    lines = set()
    for line in output.splitlines():
        # Skip dynamic-require warning in headless test bootstrap; it uses runtime resolution
        if "Unknown require:" in line and "scripts/test.server.lua" in line:
            continue
        if (
            "TypeError:" in line
            or "Unknown require:" in line
            or "Argument count mismatch" in line
        ):
            lines.add(line)
    count = len(lines)
    print(f"\nTOTAL ANALYZE ERRORS: {count}")
    # Return 1 only if there are actual errors after filtering
    return 1 if count > 0 else 0

if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

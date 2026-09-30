#!/usr/bin/env python3
"""Refresh generated bindings and provenance after an upstream Gitlink update."""

from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def upstream_git(*arguments: str) -> str:
    return subprocess.run(
        ["git", "-C", str(ROOT / "simdutf"), *arguments],
        check=True, capture_output=True, text=True,
    ).stdout.strip()


def replace_pin(path: Path, pattern: str, replacement: str) -> str:
    contents, count = re.subn(pattern, lambda _: replacement, path.read_text())
    if count != 1:
        raise ValueError(f"Expected exactly one upstream pin in {path.name}; found {count}")
    return contents


def main() -> None:
    sha = upstream_git("rev-parse", "HEAD")
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise ValueError(f"Invalid upstream commit: {sha}")
    tags = [tag for tag in upstream_git("tag", "--points-at", sha).splitlines()
            if re.fullmatch(r"v?\d+\.\d+\.\d+", tag)]
    tag = max(tags, key=lambda value: tuple(map(int, value.lstrip("v").split(".")))) if tags else sha[:12]
    readme = replace_pin(
        ROOT / "README.md", r"pinned to simdutf \*\*[^*\n]+\*\*\n\(`[0-9a-f]{40}`\)",
        f"pinned to simdutf **{tag}**\n(`{sha}`)",
    )
    notice = replace_pin(
        ROOT / "NOTICE", r"pinned to [^:\n]+:\n[0-9a-f]{40}",
        f"pinned to {tag}:\n{sha}",
    )
    subprocess.run([sys.executable, str(ROOT / "Scripts" / "generate-bindings.py")], check=True)
    (ROOT / "README.md").write_text(readme)
    (ROOT / "NOTICE").write_text(notice)
    print(f"Updated bindings and provenance for simdutf {tag} ({sha})")


if __name__ == "__main__":
    main()

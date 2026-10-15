#!/usr/bin/env python3
"""Fail when a client tree contains a service-role credential marker."""

import os
import re
import sys

SKIP_DIRS = {"node_modules", "dist", "build", ".git"}
SKIP_SUFFIXES = (".ttf", ".otf", ".png", ".jpg", ".jpeg", ".mp3", ".woff", ".woff2")
PATTERN = re.compile(r"service_role|c2VydmljZV9yb2xl|sb_secret_[A-Za-z0-9]")


def main() -> int:
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    trees = [
        os.path.join(root, name)
        for name in ("Chendu", "apps/web")
        if os.path.isdir(os.path.join(root, name))
    ]
    if not trees:
        print("no client trees to scan", file=sys.stderr)
        return 1
    hits: list[str] = []
    for tree in trees:
        for dirpath, dirnames, filenames in os.walk(tree):
            dirnames[:] = [name for name in dirnames if name not in SKIP_DIRS]
            for name in filenames:
                if name.endswith(SKIP_SUFFIXES):
                    continue
                path = os.path.join(dirpath, name)
                try:
                    with open(path, "r", encoding="utf-8", errors="ignore") as handle:
                        text = handle.read()
                except OSError:
                    continue
                if PATTERN.search(text):
                    hits.append(path)
    if hits:
        print("\n".join(hits), file=sys.stderr)
        return 1
    print(f"secret scan clean ({len(trees)} trees)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

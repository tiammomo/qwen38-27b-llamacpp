#!/usr/bin/env python3
"""Safely switch the local runtime between loopback and trusted-LAN access."""

from __future__ import annotations

import argparse
import os
import secrets
import tempfile
from pathlib import Path


PROJECT_DIR = Path(__file__).resolve().parent.parent
ENV_FILE = PROJECT_DIR / ".env"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Configure the bind address without exposing LLAMA_API_KEY."
    )
    parser.add_argument(
        "mode",
        choices=("lan", "local"),
        help="lan binds 0.0.0.0 and creates a key if needed; local binds 127.0.0.1",
    )
    return parser.parse_args()


def assignment_index(lines: list[str], name: str) -> int | None:
    prefix = f"{name}="
    matches = [index for index, line in enumerate(lines) if line.startswith(prefix)]
    if len(matches) > 1:
        raise SystemExit(f"Refusing to edit .env: {name} is defined more than once")
    return matches[0] if matches else None


def assignment_value(lines: list[str], name: str) -> str:
    index = assignment_index(lines, name)
    if index is None:
        return ""
    return lines[index].rstrip("\r\n").partition("=")[2]


def set_assignment(lines: list[str], name: str, value: str) -> None:
    index = assignment_index(lines, name)
    replacement = f"{name}={value}\n"
    if index is None:
        if lines and not lines[-1].endswith(("\n", "\r")):
            lines[-1] += "\n"
        lines.append(replacement)
        return
    lines[index] = replacement


def atomic_write(lines: list[str]) -> None:
    descriptor, temporary_name = tempfile.mkstemp(prefix=".env.", dir=PROJECT_DIR)
    temporary_path = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as handle:
            handle.writelines(lines)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, ENV_FILE)
        directory_descriptor = os.open(PROJECT_DIR, os.O_RDONLY)
        try:
            os.fsync(directory_descriptor)
        finally:
            os.close(directory_descriptor)
    finally:
        temporary_path.unlink(missing_ok=True)


def main() -> None:
    args = parse_args()
    if not ENV_FILE.is_file() or ENV_FILE.is_symlink():
        raise SystemExit("Missing regular .env file; copy .env.example to .env first")

    lines = ENV_FILE.read_text(encoding="utf-8").splitlines(keepends=True)
    generated_key = False

    if args.mode == "lan":
        set_assignment(lines, "BIND_ADDRESS", "0.0.0.0")
        if not assignment_value(lines, "LLAMA_API_KEY").strip():
            set_assignment(lines, "LLAMA_API_KEY", secrets.token_hex(32))
            generated_key = True
    else:
        set_assignment(lines, "BIND_ADDRESS", "127.0.0.1")

    atomic_write(lines)
    if args.mode == "lan":
        key_state = "generated" if generated_key else "preserved"
        print(f"LAN access configured; API key {key_state} in .env and was not displayed.")
    else:
        print("Loopback access configured; the existing API key was preserved.")


if __name__ == "__main__":
    main()

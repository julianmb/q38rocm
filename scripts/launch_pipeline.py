#!/usr/bin/env python3
"""Daemonize launcher for the Strix Halo hybrid pipeline (double-fork, fully detached)."""
import os
import sys
import subprocess
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent

def main():
    log_path = "/tmp/pipeline.log"
    args = sys.argv[1:] or ["--device", "Vulkan0", "--draft-n", "4"]

    pid = os.fork()
    if pid > 0:
        print(f"launcher exiting, intermediate pid={pid}")
        return
    os.setsid()

    pid = os.fork()
    if pid > 0:
        os._exit(0)

    log = open(log_path, "ab", buffering=0)
    proc = subprocess.Popen(
        [sys.executable, "-u", str(SCRIPT_DIR / "run_pipeline.py")] + args,
        cwd=str(SCRIPT_DIR),
        stdin=subprocess.DEVNULL,
        stdout=log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    with open("/tmp/pipeline.pid", "w") as f:
        f.write(str(proc.pid))
    log.write(f"[launcher] detached pipeline pid={proc.pid}\n".encode())
    os._exit(0)

if __name__ == "__main__":
    main()

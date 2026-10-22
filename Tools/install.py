"""Install the locally built Sunset app, preserving the previous version."""
import argparse
import datetime
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parent.parent
BUNDLE_ID = "local.sunsetmac"


def bundle_info(app):
    return plistlib.loads((app / "Contents/Info.plist").read_bytes())


def verify(app):
    if bundle_info(app).get("CFBundleIdentifier") != BUNDLE_ID:
        raise RuntimeError(f"Not a Sunset app: {app}")
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], check=True)


def stop_existing(executables):
    # Signals are deliberate: ordinary Quit now keeps Sunset running in the menu bar.
    lines = subprocess.check_output(["/bin/ps", "-axo", "pid=,command="], text=True).splitlines()
    pids = []
    for line in lines:
        fields = line.strip().split(None, 1)
        if len(fields) == 2 and any(fields[1] == app or fields[1].startswith(app + " ") for app in executables):
            pids.append(int(fields[0]))
    for pid in pids:
        os.kill(pid, signal.SIGTERM)
    for _ in range(50):
        alive = []
        for pid in pids:
            try:
                os.kill(pid, 0)
                alive.append(pid)
            except ProcessLookupError:
                pass
        if not alive:
            return
        time.sleep(0.1)
    raise RuntimeError("Sunset did not exit; update canceled before replacing the installed app.")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-open", action="store_true")
    args = parser.parse_args()
    source = ROOT / "build/Sunset.app"
    destination = Path("/Applications/Sunset.app")
    if bundle_info(source).get("CFBundleIdentifier") != BUNDLE_ID:
        raise RuntimeError(f"Not a Sunset app: {source}")
    if destination.exists() and bundle_info(destination).get("CFBundleIdentifier") != BUNDLE_ID:
        raise RuntimeError("A different app already exists at /Applications/Sunset.app; nothing replaced.")

    # Stage and check everything before touching the running/installed version.
    staging = Path(tempfile.mkdtemp(prefix=".sunset-install-", dir=destination.parent))
    candidate = staging / "Sunset.app"
    backup = None
    try:
        subprocess.run(["/usr/bin/ditto", "--noextattr", "--norsrc", str(source), str(candidate)], check=True)
        verify(candidate)
        stop_existing([str(app / "Contents/MacOS/Sunset") for app in [source, destination]])
        if destination.exists():
            stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
            backup = ROOT / "build/backups" / stamp / "Sunset.app"
            backup.parent.mkdir(parents=True)
            shutil.move(str(destination), str(backup))
        try:
            os.replace(candidate, destination)
            verify(destination)
            if not args.no_open:
                subprocess.run(["/usr/bin/open", str(destination)], check=True)
        except Exception:
            if destination.exists():
                shutil.move(str(destination), str(staging / "Failed-Sunset.app"))
            if backup is not None and backup.exists():
                shutil.move(str(backup), str(destination))
                if not args.no_open:
                    subprocess.run(["/usr/bin/open", str(destination)], check=False)
            raise
    finally:
        shutil.rmtree(staging)
    print(f"Installed Sunset {bundle_info(destination)['CFBundleShortVersionString']}: {destination}")
    if backup is not None:
        print(f"Previous version preserved: {backup}")


if __name__ == "__main__":
    main()

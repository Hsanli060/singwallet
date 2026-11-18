import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
DEFAULT_BACKUP_PATH = REPO_ROOT / "scratch" / "singwallet_user_backup.json"


def find_adb(explicit_adb: str | None = None) -> str | None:
    """Locate adb executable via --adb, ADB_PATH, ANDROID_HOME, ANDROID_SDK_ROOT, or PATH."""
    exe_name = "adb.exe" if os.name == "nt" else "adb"
    candidates: list[str] = []

    if explicit_adb:
        candidates.append(explicit_adb)
    if os.environ.get("ADB_PATH"):
        candidates.append(os.environ["ADB_PATH"])
    for sdk_env in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        sdk_root = os.environ.get(sdk_env)
        if sdk_root:
            candidates.append(os.path.join(sdk_root, "platform-tools", exe_name))

    for candidate in candidates:
        if os.path.isfile(candidate):
            return os.path.abspath(candidate)
        found = shutil.which(candidate)
        if found and os.path.isfile(found):
            return found

    for name in ("adb", "adb.exe"):
        found = shutil.which(name)
        if found and os.path.isfile(found):
            return found

    return None


def run_adb(adb_path: str, args: list[str], serial: str | None = None, timeout: int = 60) -> subprocess.CompletedProcess:
    """Run an ADB command and strictly fail if returncode != 0."""
    cmd = [adb_path]
    if serial:
        cmd.extend(["-s", serial])
    cmd.extend(args)
    print(f">> {' '.join(cmd)}")
    res = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="ignore",
        timeout=timeout,
    )
    if res.stdout.strip():
        print(res.stdout.strip())
    if res.stderr.strip():
        print("ERR:", res.stderr.strip())
    if res.returncode != 0:
        print(f"Command failed with exit code {res.returncode}: {' '.join(cmd)}")
        sys.exit(res.returncode or 1)
    return res


def detect_online_device(adb_path: str) -> str:
    """Auto-detect the first online ADB device."""
    res = run_adb(adb_path, ["devices"])
    for line in res.stdout.splitlines()[1:]:
        parts = line.strip().split()
        if len(parts) >= 2 and parts[1] == "device":
            return parts[0]
    print("Error: No online ADB device detected! Connect a device or pass --serial.")
    sys.exit(1)


def validate_backup_file(backup_path: Path) -> None:
    """Ensure backup file exists and contains valid non-empty JSON object."""
    if not backup_path.is_file():
        print(f"Error: Backup file does not exist: {backup_path}")
        sys.exit(1)
    try:
        with open(backup_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as exc:
        print(f"Error: Backup file is not valid JSON ({backup_path}): {exc}")
        sys.exit(1)
    if not isinstance(data, dict) or (not data.get("rawStorage") and not data.get("snapshot")):
        print(f"Error: Backup file missing valid rawStorage/snapshot payload: {backup_path}")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="Upgrade SingWallet Android APK via ADB (lossless install -r by default, optional wipe-reinstall + restore)"
    )
    parser.add_argument("--apk", required=True, help="Path to APK file to install")
    parser.add_argument(
        "--backup",
        default=None,
        help="Path to backup JSON file (default: scratch/singwallet_user_backup.json)",
    )
    parser.add_argument("--serial", default=None, help="Target ADB device serial (auto-detected if omitted)")
    parser.add_argument("--adb", default=None, help="Path to adb executable")
    parser.add_argument(
        "--wipe-reinstall",
        action="store_true",
        help="Uninstall existing app before installing (REQUIRES valid backup file first; use only when signature changes)",
    )
    args = parser.parse_args()

    apk_path = Path(args.apk).expanduser()
    if not apk_path.is_absolute():
        apk_path = (REPO_ROOT / apk_path).resolve()
    if not apk_path.is_file():
        print(f"Error: APK file not found: {apk_path}")
        sys.exit(1)

    backup_explicit = args.backup is not None
    backup_path = Path(args.backup).expanduser() if args.backup else DEFAULT_BACKUP_PATH
    if not backup_path.is_absolute():
        backup_path = (REPO_ROOT / backup_path).resolve()

    if args.wipe_reinstall:
        print("=== Pre-check: Validating backup file before --wipe-reinstall ===")
        validate_backup_file(backup_path)
    elif backup_explicit:
        validate_backup_file(backup_path)

    adb_path = find_adb(args.adb)
    if not adb_path:
        print("Error: adb binary not found! Pass --adb or set ADB_PATH / ANDROID_HOME / ANDROID_SDK_ROOT / PATH.")
        sys.exit(1)

    serial = args.serial or detect_online_device(adb_path)
    print(f"Using ADB: {adb_path}")
    print(f"Target device: {serial}")

    if args.wipe_reinstall:
        print("\n=== Step 1: Uninstalling existing APK (--wipe-reinstall) ===")
        run_adb(adb_path, ["uninstall", "com.singwallet.app"], serial=serial)

        print(f"\n=== Step 2: Installing fresh APK ({apk_path.name}) ===")
        inst = run_adb(adb_path, ["install", str(apk_path)], serial=serial, timeout=120)
    else:
        print(f"\n=== Step 1: Performing lossless upgrade install -r ({apk_path.name}) ===")
        inst = run_adb(adb_path, ["install", "-r", str(apk_path)], serial=serial, timeout=120)

    if "success" not in inst.stdout.lower():
        print("Installation failed (Success confirmation missing)!")
        sys.exit(1)

    print("\n=== Step 3: Launching SingWallet on device ===")
    run_adb(adb_path, ["shell", "am", "start", "-n", "com.singwallet.app/.MainActivity"], serial=serial)

    should_restore = args.wipe_reinstall or backup_explicit or backup_path.is_file()
    if should_restore:
        print("Waiting 4 seconds for WebView initialization...")
        time.sleep(4)

        print("\n=== Step 4: Discovering WebView DevTools socket ===")
        socket_name = None
        for attempt in range(5):
            net_res = run_adb(adb_path, ["shell", "cat", "/proc/net/unix"], serial=serial)
            matches = re.findall(r"@webview_devtools_remote_\d+", net_res.stdout)
            if matches:
                socket_name = matches[-1].replace("@", "")
                print(f"Found active WebView socket: {socket_name}")
                break
            print(f"Retrying socket discovery ({attempt + 1}/5)...")
            time.sleep(2)

        if not socket_name:
            print("Error: Could not find WebView DevTools socket!")
            sys.exit(1)

        print(f"\n=== Step 5: Forwarding tcp:9222 -> localabstract:{socket_name} ===")
        run_adb(adb_path, ["forward", "tcp:9222", f"localabstract:{socket_name}"], serial=serial)

        print(f"\n=== Step 6: Restoring backup from {backup_path} ===")
        restore_script = SCRIPT_DIR / "restore_phone_backup.py"
        restore_res = subprocess.run(
            [sys.executable, str(restore_script), "--file", str(backup_path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="ignore",
        )
        if restore_res.stdout:
            print(restore_res.stdout)
        if restore_res.stderr:
            print("Restore ERR:", restore_res.stderr)
        if restore_res.returncode != 0:
            print(f"Restore script failed with exit code {restore_res.returncode}!")
            sys.exit(restore_res.returncode)
    else:
        print(f"\n[Info] No backup file found at {backup_path}; skipping restore after lossless install -r.")

    print("=== Step 7: Final verification of installed package version ===")
    ver_res = run_adb(adb_path, ["shell", "dumpsys", "package", "com.singwallet.app"], serial=serial)
    for line in ver_res.stdout.splitlines():
        if "versionName=" in line:
            print(f"Installed Version: {line.strip()}")
            break

    print("\nALL UPGRADE & RESTORE STEPS FINISHED SUCCESSFULLY!")


if __name__ == "__main__":
    main()

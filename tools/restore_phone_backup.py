import argparse
import json
import sys
import urllib.request
from pathlib import Path

import websocket


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_BACKUP_PATH = REPO_ROOT / "scratch" / "singwallet_user_backup.json"


def main():
    parser = argparse.ArgumentParser(description="Restore SingWallet WebView backup via local CDP endpoint")
    parser.add_argument(
        "--file",
        type=str,
        default=str(DEFAULT_BACKUP_PATH),
        help="Input backup JSON path (default: scratch/singwallet_user_backup.json)",
    )
    parser.add_argument("--port", type=int, default=9222, help="Local CDP port (default: 9222)")
    args = parser.parse_args()

    backup_path = Path(args.file).expanduser()
    if not backup_path.is_absolute():
        backup_path = (REPO_ROOT / backup_path).resolve()

    if not backup_path.is_file():
        print(f"Error: Backup file not found: {backup_path}")
        sys.exit(1)

    try:
        with open(backup_path, "r", encoding="utf-8") as f:
            backup_content = json.load(f)
    except Exception as exc:
        print(f"Error: Failed to parse backup JSON ({backup_path}): {exc}")
        sys.exit(1)

    if not isinstance(backup_content, dict):
        print(f"Error: Backup JSON must be an object ({backup_path})")
        sys.exit(1)

    cdp_url = f"http://127.0.0.1:{args.port}/json"
    print(f"Connecting to local CDP endpoint ({cdp_url})...")
    try:
        with urllib.request.urlopen(cdp_url, timeout=10) as req:
            tabs = json.loads(req.read().decode("utf-8"))
    except Exception as exc:
        print(f"Error: Failed to query CDP endpoint {cdp_url}: {exc}")
        sys.exit(1)

    target_tab = None
    for t in tabs:
        if "com.singwallet.app" in t.get("url", "") or "SingWallet" in t.get("title", ""):
            target_tab = t
            break

    if not target_tab and tabs:
        target_tab = tabs[0]

    if not target_tab:
        print("Error: No WebView tab found!")
        sys.exit(1)

    ws_url = target_tab.get("webSocketDebuggerUrl")
    if not ws_url:
        print("Error: WebView tab missing webSocketDebuggerUrl!")
        sys.exit(1)

    print(f"Connecting to WebSocket: {ws_url}")
    raw_storage = backup_content.get("rawStorage", {}) or {}
    snapshot = backup_content.get("snapshot")

    restore_script = f"""
    (() => {{
        const errors = [];
        let keysRestored = 0;
        const raw = {json.dumps(raw_storage)};
        for (const [k, v] of Object.entries(raw)) {{
            try {{
                localStorage.setItem(k, v);
                keysRestored++;
            }} catch (e) {{
                errors.push(`localStorage.setItem(${{k}}): ${{e && e.message ? e.message : String(e)}}`);
            }}
        }}

        let restoredSnapshot = false;
        const snap = {json.dumps(snapshot)};
        if (snap) {{
            if (typeof window.importBackupFromJson === 'function') {{
                try {{
                    restoredSnapshot = Boolean(window.importBackupFromJson(snap));
                    if (!restoredSnapshot) {{
                        errors.push('window.importBackupFromJson returned falsy');
                    }}
                }} catch (e) {{
                    errors.push(`importBackupFromJson: ${{e && e.message ? e.message : String(e)}}`);
                }}
            }} else {{
                errors.push('window.importBackupFromJson is not defined on window');
            }}
        }}

        if (errors.length === 0) {{
            setTimeout(() => {{
                window.location.reload();
            }}, 300);
        }}

        return JSON.stringify({{
            ok: errors.length === 0,
            keysRestored: keysRestored,
            snapshotRestored: restoredSnapshot,
            errors: errors
        }});
    }})()
    """

    req_payload = {
        "id": 2,
        "method": "Runtime.evaluate",
        "params": {
            "expression": restore_script,
            "returnByValue": True,
        },
    }

    ws = None
    try:
        ws = websocket.create_connection(ws_url, suppress_origin=True, timeout=15)
        ws.settimeout(15)
        ws.send(json.dumps(req_payload))
        result = ws.recv()
    except Exception as exc:
        print(f"Error: WebSocket communication failed: {exc}")
        sys.exit(1)
    finally:
        if ws is not None:
            try:
                ws.close()
            except Exception:
                pass

    parsed = json.loads(result)
    exception_details = parsed.get("result", {}).get("exceptionDetails")
    if exception_details:
        print("RESTORE FAILED (Runtime.evaluate exception):", json.dumps(exception_details, ensure_ascii=False))
        sys.exit(1)

    value_str = parsed.get("result", {}).get("result", {}).get("value")
    if not value_str:
        print("RESTORE FAILED (Missing evaluation result):", result)
        sys.exit(1)

    try:
        status = json.loads(value_str)
    except Exception as exc:
        print(f"RESTORE FAILED (Invalid JSON return from WebView): {exc} -> {value_str}")
        sys.exit(1)

    print("\n==========================================")
    print("RESTORE RESULT:", json.dumps(status, ensure_ascii=False))
    if not status.get("ok") or status.get("errors"):
        print("RESTORE FAILED! Errors:", status.get("errors"))
        print("==========================================\n")
        sys.exit(1)

    if snapshot is not None and not status.get("snapshotRestored"):
        print("RESTORE FAILED! Snapshot was present in backup but snapshotRestored is False.")
        print("==========================================\n")
        sys.exit(1)

    print("SUCCESS! Data successfully injected and page reloaded!")
    print("==========================================\n")


if __name__ == "__main__":
    main()

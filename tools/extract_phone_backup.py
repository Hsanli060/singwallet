import argparse
import json
import os
import sys
import urllib.request
from pathlib import Path

import websocket


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_BACKUP_PATH = REPO_ROOT / "scratch" / "singwallet_user_backup.json"


def main():
    parser = argparse.ArgumentParser(description="Extract SingWallet WebView backup via local CDP endpoint")
    parser.add_argument(
        "--file",
        type=str,
        default=str(DEFAULT_BACKUP_PATH),
        help="Output backup JSON path (default: scratch/singwallet_user_backup.json)",
    )
    parser.add_argument("--port", type=int, default=9222, help="Local CDP port (default: 9222)")
    args = parser.parse_args()

    out_path = Path(args.file).expanduser()
    if not out_path.is_absolute():
        out_path = (REPO_ROOT / out_path).resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)

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
    eval_expr = """
    (() => {
        let snapshot = null;
        let snapshotError = null;
        try {
            if (typeof window.exportFullBackupSnapshot === 'function') {
                snapshot = window.exportFullBackupSnapshot();
            }
        } catch (e) {
            snapshotError = e && e.message ? e.message : String(e);
        }

        const rawStorage = {};
        for (let i = 0; i < localStorage.length; i++) {
            const key = localStorage.key(i);
            rawStorage[key] = localStorage.getItem(key);
        }

        return JSON.stringify({
            snapshot: snapshot,
            snapshotError: snapshotError,
            rawStorage: rawStorage,
            allMonthlyData: window.allMonthlyData || null,
            vlmConfig: window.vlmConfig || null
        });
    })()
    """

    req_payload = {
        "id": 1,
        "method": "Runtime.evaluate",
        "params": {
            "expression": eval_expr,
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
    if parsed.get("result", {}).get("exceptionDetails"):
        print("Error: Runtime.evaluate threw exception:", parsed["result"]["exceptionDetails"])
        sys.exit(1)

    result_value = parsed.get("result", {}).get("result", {}).get("value")
    if not result_value:
        print("Failed to get result from Runtime.evaluate:", result)
        sys.exit(1)

    data = json.loads(result_value)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    print("\n==========================================")
    print("SUCCESS! User backup successfully extracted!")
    print(f"Saved to: {out_path}")
    print(f"File size: {os.path.getsize(out_path)} bytes")

    snapshot = data.get("snapshot") or {}
    stats = snapshot.get("backupStats", {})
    tx_count = stats.get("transactionCount", 0)
    cat_count = stats.get("categoryCount", 0)
    raw_storage = data.get("rawStorage", {})

    print(f"Transaction count: {tx_count}")
    print(f"Category count: {cat_count}")
    print(f"LocalStorage keys backed up: {len(raw_storage)} keys")
    for k in raw_storage:
        print(f"  - {k} ({len(raw_storage[k])} chars)")
    print("==========================================\n")


if __name__ == "__main__":
    main()

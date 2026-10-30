import sys
import json
import ssl
import time
import base64
import mimetypes
import threading
import subprocess
import urllib.parse
import urllib.request
import urllib.error
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

# Windows MIME types registration
mimetypes.add_type('application/javascript', '.js')
mimetypes.add_type('text/css', '.css')
mimetypes.add_type('text/html', '.html')
mimetypes.add_type('application/json', '.json')

# ADB configuration (Xiaomi 14 / HyperOS)
ADB_PATH = r'D:\Dev\platform-tools\adb.exe'
ADB_DEVICE_ID = '5c2a21cf'
SCREENSHOT_DIRS = ['/sdcard/DCIM/Screenshots', '/sdcard/Pictures/Screenshots']

# In-memory queue for shortcut capture / ingest / backtap watcher
SHORTCUT_QUEUE = []
QUEUE_LOCK = threading.Lock()

# Back-tap screenshot watcher global state & baseline isolation (DEPRECATED & DISABLED by default)
WATCH_SCREENSHOTS_ENABLED = False
AUTO_CLEAN_SCREENSHOTS = False  # 已停用后台自动读取相册截图与自动清理逻辑
SEEN_SCREENSHOTS = set()
BASELINE_INITIALIZED = False
WATCHER_LOCK = threading.Lock()


def _run_adb(args, timeout=6):
    """Run ADB targeting Xiaomi 14 (5c2a21cf) first; fallback to default ADB device on failure or empty output."""
    adb_path = ADB_PATH
    cmds = (
        [adb_path, '-s', ADB_DEVICE_ID] + list(args),
        [adb_path] + list(args),
    )
    last_res = None
    for cmd in cmds:
        try:
            res = subprocess.run(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=timeout
            )
            last_res = res
            if res.returncode == 0 and res.stdout:
                return res
        except Exception:
            continue
    return last_res


def _is_valid_screenshot_file(fname):
    """Filter out hidden/pending/tmp files and keep only finalized .png/.jpg/.jpeg screenshots."""
    if not fname or '/' in fname or fname.endswith(':'):
        return False
    lower = fname.lower()
    if lower.startswith('.') or lower.startswith('pending') or lower.startswith('tmp'):
        return False
    return lower.endswith(('.jpg', '.jpeg', '.png'))


def snapshot_existing_screenshots():
    """Scan existing screenshots on the phone into SEEN_SCREENSHOTS so historical photos are never mis-captured."""
    global BASELINE_INITIALIZED
    shell_cmd = (
        'if [ -d /sdcard/DCIM ] || [ -d /sdcard/Pictures ]; then '
        'echo __ADB_STORAGE_READY__; '
        'ls -1 /sdcard/DCIM/Screenshots /sdcard/Pictures/Screenshots 2>/dev/null; '
        'true; '
        'fi'
    )
    res = _run_adb(['shell', shell_cmd], timeout=6)
    if not res or res.returncode != 0 or not res.stdout:
        return False

    text = res.stdout.decode('utf-8', errors='replace')
    if '__ADB_STORAGE_READY__' not in text:
        return False

    existing = set()
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line == '__ADB_STORAGE_READY__' or line.endswith(':'):
            continue
        lower = line.lower()
        if lower.endswith(('.png', '.jpg', '.jpeg')):
            existing.add(line)

    with WATCHER_LOCK:
        SEEN_SCREENSHOTS.update(existing)
        was_initialized = BASELINE_INITIALIZED
        BASELINE_INITIALIZED = True
        total_seen = len(SEEN_SCREENSHOTS)

    if not was_initialized:
        print(f'[BackTap Watcher] Baseline initialized ({total_seen} historical screenshots isolated).', flush=True)
    else:
        print(f'[BackTap Watcher] Baseline refreshed ({total_seen} historical screenshots isolated).', flush=True)
    return True


def _pull_screenshot_bytes(remote_dir, fname):
    """Pull raw screenshot bytes via adb exec-out cat with retry if still flushing."""
    remote_path = f'{remote_dir}/{fname}'
    cat_arg = f'cat "{remote_path}"'
    res = _run_adb(['exec-out', cat_arg], timeout=10)
    img_bytes = res.stdout if (res and res.returncode == 0 and res.stdout) else b''

    if len(img_bytes) < 5000:
        time.sleep(0.4)
        res2 = _run_adb(['exec-out', cat_arg], timeout=10)
        if res2 and res2.returncode == 0 and res2.stdout:
            img_bytes = res2.stdout

    if not img_bytes or len(img_bytes) < 1000 or img_bytes.startswith(b'cat:'):
        return None
    return img_bytes


def screenshot_watcher_loop():
    """Background daemon loop polling newest screenshots every 1.2s for Xiaomi 14 back-tap capture."""
    # Attempt initial baseline snapshot at startup (safe no-op if phone is currently unplugged)
    try:
        snapshot_existing_screenshots()
    except Exception as e:
        print(f'[BackTap Watcher] Initial snapshot deferred: {e}', flush=True)

    list_cmd = (
        'if [ -d /sdcard/DCIM ] || [ -d /sdcard/Pictures ]; then '
        'echo __DIR__:/sdcard/DCIM/Screenshots; '
        'ls -t /sdcard/DCIM/Screenshots 2>/dev/null | head -n 5; '
        'echo __DIR__:/sdcard/Pictures/Screenshots; '
        'ls -t /sdcard/Pictures/Screenshots 2>/dev/null | head -n 5; '
        'true; '
        'fi'
    )

    while True:
        try:
            if not WATCH_SCREENSHOTS_ENABLED:
                time.sleep(1.2)
                continue

            # Critical safeguard: if phone was plugged in mid-session before baseline existed,
            # take baseline snapshot ONLY first and skip capture on this tick!
            if not BASELINE_INITIALIZED:
                snapshot_existing_screenshots()
                time.sleep(1.2)
                continue

            res = _run_adb(['shell', list_cmd], timeout=6)
            if not res or res.returncode != 0 or not res.stdout:
                time.sleep(1.2)
                continue

            text = res.stdout.decode('utf-8', errors='replace')
            if '__DIR__:' not in text:
                time.sleep(1.2)
                continue

            dir_candidates = {}
            current_dir = '/sdcard/DCIM/Screenshots'
            for raw_line in text.splitlines():
                line = raw_line.strip()
                if not line:
                    continue
                if line.startswith('__DIR__:'):
                    current_dir = line.split('__DIR__:', 1)[1].strip()
                    dir_candidates.setdefault(current_dir, [])
                    continue
                bucket = dir_candidates.setdefault(current_dir, [])
                if len(bucket) < 5:
                    bucket.append(line)

            new_targets = []
            with WATCHER_LOCK:
                for rdir in SCREENSHOT_DIRS:
                    for fname in dir_candidates.get(rdir, []):
                        if not _is_valid_screenshot_file(fname):
                            continue
                        if fname not in SEEN_SCREENSHOTS:
                            SEEN_SCREENSHOTS.add(fname)
                            new_targets.append((rdir, fname))

            # Process in chronological order if multiple new screenshots appeared in one tick
            for rdir, fname in reversed(new_targets):
                if not WATCH_SCREENSHOTS_ENABLED:
                    break

                # Wait for HyperOS screenshot service to finish flushing image bytes to disk
                time.sleep(0.35)
                img_bytes = _pull_screenshot_bytes(rdir, fname)
                if not img_bytes:
                    print(f'[BackTap Watcher] Skipped incomplete/unreadable screenshot: {fname}', flush=True)
                    continue

                mime = 'image/png' if fname.lower().endswith('.png') else 'image/jpeg'
                b64 = base64.b64encode(img_bytes).decode('ascii')
                data_url = f'data:{mime};base64,{b64}'

                item = {
                    'id': f'backtap_{int(time.time() * 1000)}',
                    'dataUrl': data_url,
                    'timestamp': time.time(),
                    'source': 'backtap-screenshot',
                    'filename': fname
                }
                with QUEUE_LOCK:
                    SHORTCUT_QUEUE.append(item)

                print(f'[BackTap Watcher] Captured new screenshot: {fname}', flush=True)

                # 识后即删 / 零相册污染：提取完毕后自动从相册清理该截屏，防止手机相册垃圾图片堆积
                if AUTO_CLEAN_SCREENSHOTS:
                    time.sleep(0.15)
                    remote_file = f'{rdir}/{fname}'
                    _run_adb(['shell', f'rm -f "{remote_file}"'], timeout=4)
                    _run_adb(['shell', f'am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d "file://{remote_file}"'], timeout=4)
                    print(f'[BackTap Watcher] Auto-cleaned screenshot from gallery: {fname} (Zero album pollution)', flush=True)
        except Exception as err:
            print(f'[BackTap Watcher] Loop error: {err}', flush=True)

        time.sleep(1.2)

class ProxyHTTPRequestHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        # Prevent duplicate Access-Control-Allow-Origin headers
        has_cors = False
        for h in getattr(self, '_headers_buffer', []):
            try:
                line = h.decode('latin1') if isinstance(h, bytes) else str(h)
                if line.lower().startswith('access-control-allow-origin'):
                    has_cors = True
                    break
            except Exception:
                pass
        if not has_cors:
            self.send_header('Access-Control-Allow-Origin', '*')

        # Disable all caching for instant hot-reload on real phones
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0')
        self.send_header('Pragma', 'no-cache')
        self.send_header('Expires', '0')
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.send_header('Access-Control-Max-Age', '86400')
        super().end_headers()

    def do_GET(self):
        if self.path.startswith('/api/shortcut/adb-capture'):
            self.handle_shortcut_adb_capture()
        elif self.path.startswith('/api/shortcut/poll'):
            self.handle_shortcut_poll()
        elif self.path.startswith('/api/shortcut/watcher-status'):
            self.handle_shortcut_watcher_status_get()
        else:
            super().do_GET()

    def do_POST(self):
        if self.path == '/api/proxy' or self.path.startswith('/api/proxy?'):
            self.handle_proxy()
        elif self.path.startswith('/api/shortcut/adb-capture'):
            self.handle_shortcut_adb_capture()
        elif self.path.startswith('/api/shortcut/ingest'):
            self.handle_shortcut_ingest()
        elif self.path.startswith('/api/shortcut/watcher-status'):
            self.handle_shortcut_watcher_status_post()
        else:
            super().do_POST()

    def handle_shortcut_watcher_status_get(self):
        with QUEUE_LOCK:
            queue_count = len(SHORTCUT_QUEUE)
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({
            'status': 'ok',
            'enabled': WATCH_SCREENSHOTS_ENABLED,
            'baselineInitialized': BASELINE_INITIALIZED,
            'queueCount': queue_count
        }).encode('utf-8'))

    def handle_shortcut_watcher_status_post(self):
        global WATCH_SCREENSHOTS_ENABLED
        content_len = int(self.headers.get('Content-Length', 0))
        raw_body = self.rfile.read(content_len) if content_len > 0 else b'{}'
        try:
            payload = json.loads(raw_body.decode('utf-8')) if raw_body else {}
        except Exception as e:
            self.send_response(400)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'error', 'error': f'Invalid JSON: {e}'}).encode('utf-8'))
            return

        if not isinstance(payload, dict) or 'enabled' not in payload:
            self.send_response(400)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"status": "error", "error": "Missing enabled boolean field"}')
            return

        was_enabled = WATCH_SCREENSHOTS_ENABLED
        WATCH_SCREENSHOTS_ENABLED = bool(payload['enabled'])

        # If re-enabled from disabled (or baseline not yet initialized), refresh baseline
        # so screenshots taken while paused are ignored.
        if WATCH_SCREENSHOTS_ENABLED and (not was_enabled or not BASELINE_INITIALIZED):
            try:
                snapshot_existing_screenshots()
            except Exception as e:
                print(f'[BackTap Watcher] Baseline refresh error on enable: {e}', flush=True)

        print(f'[BackTap Watcher] Status toggled: enabled={WATCH_SCREENSHOTS_ENABLED}', flush=True)

        with QUEUE_LOCK:
            queue_count = len(SHORTCUT_QUEUE)
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({
            'status': 'ok',
            'enabled': WATCH_SCREENSHOTS_ENABLED,
            'baselineInitialized': BASELINE_INITIALIZED,
            'queueCount': queue_count
        }).encode('utf-8'))

    def handle_shortcut_adb_capture(self):
        parsed = urllib.parse.urlparse(self.path)
        qs = urllib.parse.parse_qs(parsed.query)
        delay_str = qs.get('delay', ['0'])[0]
        try:
            delay = float(delay_str)
        except Exception:
            delay = 0.0

        if delay > 0:
            time.sleep(delay)

        res = _run_adb(['exec-out', 'screencap', '-p'], timeout=10)
        img_bytes = res.stdout if res else None

        if not img_bytes or len(img_bytes) < 1000:
            self.send_response(500)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"error": "Failed to capture valid screenshot bytes from ADB"}')
            return

        b64_data = base64.b64encode(img_bytes).decode('ascii')
        data_url = f"data:image/png;base64,{b64_data}"
        
        item = {
            'id': f'cap_{int(time.time() * 1000)}',
            'dataUrl': data_url,
            'timestamp': time.time(),
            'source': 'adb-capture'
        }
        with QUEUE_LOCK:
            SHORTCUT_QUEUE.append(item)
            queue_count = len(SHORTCUT_QUEUE)

        accept = self.headers.get('Accept', '')
        if 'text/html' in accept and self.command == 'GET':
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.end_headers()
            html = """<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>SingWallet 抓屏成功</title>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>body{background:#020617;color:#fff;font-family:sans-serif;display:flex;flex-direction:column;align-items:center;justify-content:center;height:100vh;margin:0;padding:20px;box-sizing:border-box;text-align:center;}h2{color:#818cf8;margin-bottom:8px;}p{color:#94a3b8;font-size:14px;}a{color:#38bdf8;margin-top:16px;text-decoration:none;font-weight:bold;}</style>
</head>
<body>
<h2>⚡ 抓屏成功！</h2>
<p>已抓取当前手机账单快照，SingWallet 正在后台自动由大模型识别入账中。</p>
<p>您可以直接切回微信/支付宝，或点击下方返回账本查看：</p>
<a href="/singwallet_preview.html">返回 SingWallet 账本</a>
</body>
</html>"""
            self.wfile.write(html.encode('utf-8'))
        else:
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({
                'status': 'ok',
                'message': '已抓取当前手机屏幕快照并推入后台大模型识别队列',
                'id': item['id'],
                'count': queue_count
            }).encode('utf-8'))

    def handle_shortcut_ingest(self):
        content_len = int(self.headers.get('Content-Length', 0))
        raw_body = self.rfile.read(content_len)
        content_type = self.headers.get('Content-Type', '')

        data_url = None
        if 'application/json' in content_type:
            try:
                payload = json.loads(raw_body.decode('utf-8'))
                data_url = payload.get('image') or payload.get('dataUrl') or payload.get('data')
            except Exception as e:
                self.send_response(400)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({'error': f'Invalid JSON: {e}'}).encode('utf-8'))
                return
        elif 'image/' in content_type:
            mime = content_type.split(';')[0].strip()
            b64 = base64.b64encode(raw_body).decode('ascii')
            data_url = f"data:{mime};base64,{b64}"

        if not data_url:
            self.send_response(400)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"error": "Missing image data in request"}')
            return

        item = {
            'id': f'ingest_{int(time.time() * 1000)}',
            'dataUrl': data_url,
            'timestamp': time.time(),
            'source': 'shortcut-ingest'
        }
        with QUEUE_LOCK:
            SHORTCUT_QUEUE.append(item)
            queue_count = len(SHORTCUT_QUEUE)

        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({
            'status': 'ok',
            'message': '已接收快捷指令图片并推入后台识别队列',
            'id': item['id'],
            'count': queue_count
        }).encode('utf-8'))

    def handle_shortcut_poll(self):
        with QUEUE_LOCK:
            items = list(SHORTCUT_QUEUE)
            SHORTCUT_QUEUE.clear()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({'status': 'ok', 'items': items}).encode('utf-8'))

    def handle_proxy(self):
        content_len = int(self.headers.get('Content-Length', 0))
        raw_body = self.rfile.read(content_len)
        try:
            payload = json.loads(raw_body.decode('utf-8'))
        except Exception as e:
            self.send_response(400)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'error': {'message': f'Invalid proxy payload: {e}'}}).encode('utf-8'))
            return

        target_url = payload.get('url', '')
        target_method = payload.get('method', 'GET').upper()
        target_headers = payload.get('headers', {})
        target_body = payload.get('body', None)

        if not target_url:
            self.send_response(400)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"error": {"message": "Missing target url"}}')
            return

        body_bytes = None
        if target_body is not None:
            if isinstance(target_body, (dict, list)):
                body_bytes = json.dumps(target_body).encode('utf-8')
            elif isinstance(target_body, str):
                body_bytes = target_body.encode('utf-8')
            elif isinstance(target_body, bytes):
                body_bytes = target_body

        req = urllib.request.Request(target_url, data=body_bytes, method=target_method)
        for k, v in target_headers.items():
            if k.lower() not in ['host', 'content-length', 'accept-encoding']:
                req.add_header(k, str(v))

        ssl_ctx = ssl.create_default_context()
        ssl_ctx.check_hostname = False
        ssl_ctx.verify_mode = ssl.CERT_NONE

        try:
            with urllib.request.urlopen(req, context=ssl_ctx, timeout=30) as upstream_resp:
                status_code = upstream_resp.status
                resp_data = upstream_resp.read()
                content_type = upstream_resp.headers.get('Content-Type', 'application/json')

                self.send_response(status_code)
                self.send_header('Content-Type', content_type)
                self.end_headers()
                self.wfile.write(resp_data)
        except urllib.error.HTTPError as http_err:
            status_code = http_err.code
            err_data = http_err.read()
            content_type = http_err.headers.get('Content-Type', 'application/json')

            self.send_response(status_code)
            self.send_header('Content-Type', content_type)
            self.end_headers()
            self.wfile.write(err_data)
        except Exception as conn_err:
            self.send_response(502)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'error': {'message': f'Upstream connection failed: {conn_err}'}}).encode('utf-8'))

class ScreenshotWatcher(threading.Thread):
    def __init__(self):
        super().__init__(name='ScreenshotWatcher', daemon=True)

    def run(self):
        screenshot_watcher_loop()


def run_server(port=8765):
    # Back-tap screenshot watcher thread is intentionally NOT started by default.
    # Only two capture entry points are retained:
    # 1. Control Center "Lightning Record" Quick Settings Tile
    # 2. In-app "+ Add Record" button
    if WATCH_SCREENSHOTS_ENABLED:
        watcher = ScreenshotWatcher()
        watcher.start()

    server_address = ('0.0.0.0', port)
    httpd = ThreadingHTTPServer(server_address, ProxyHTTPRequestHandler)
    print(f'SingWallet preview server with /api/proxy running on http://0.0.0.0:{port} (auto album watcher disabled)', flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    run_server(port)

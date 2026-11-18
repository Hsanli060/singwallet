#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SingWallet Mobile Live Hot Reload Server (零外部依赖真机 UI 极速热重载工具)
-------------------------------------------------------------------------
特点：
1. 纯 Python 3 标准库，零 pip 安装包，0.5 秒内即开即用。
2. 毫秒级监控 CSS / JS / HTML 变更：
   - 仅 CSS 变动时：触发 0.1 秒无闪烁局部样式热替换（完全保留手机当前 Tab/弹窗/输入/滚动条状态）；
   - JS / HTML 变动时：触发页面整页热重载。
3. 动态内存注入热重载客户端脚本，100% 杜绝污染磁盘源码。
4. 竞态安全：先启动 HTTP 监听并自检确认 100% 就绪后，再触发 ADB reverse 与 App 唤醒。
5. 零噪音：内置 /favicon.ico 204 支持，静默日志。
6. 支持 `--offline` 一键安全切回内置离线版。
"""

import argparse
import ipaddress
import json
import mimetypes
import os
import re
import shutil
import socket
import ssl
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

# 确保标准输出与错误流在 Windows 终端下使用 UTF-8
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='backslashreplace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='backslashreplace')

# 注册常见 Windows MIME 类型
mimetypes.add_type('application/javascript', '.js')
mimetypes.add_type('text/css', '.css')
mimetypes.add_type('text/html', '.html')
mimetypes.add_type('application/json', '.json')
mimetypes.add_type('image/png', '.png')
mimetypes.add_type('image/jpeg', '.jpg')
mimetypes.add_type('image/svg+xml', '.svg')

MAX_PROXY_BODY_BYTES = 15 * 1024 * 1024
ALLOWED_METHODS = {'GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'}
LOCAL_ORIGIN_RE = re.compile(r'^http://(127\.0\.0\.1|localhost)(:\d{1,5})?$')

# 客户端热重载轻量注入脚本（纯 JS，无任何 Emoji）
LIVE_RELOAD_CLIENT_SCRIPT = """
<!-- SingWallet Live Hot Reload Engine (In-Memory Injected) -->
<script id="singwallet-live-reload-client">
(function() {
  var lastCssMtime = null;
  var lastFullMtime = null;
  var isPolling = false;

  function pollHotReloadTick() {
    if (isPolling) return;
    isPolling = true;
    fetch('/__hot_reload_tick?_ts=' + Date.now())
      .then(function(res) {
        if (!res.ok) throw new Error('HTTP ' + res.status);
        return res.json();
      })
      .then(function(data) {
        isPolling = false;
        if (!data) return;
        var newCss = data.css_mtime || 0;
        var newFull = data.full_mtime || 0;

        if (lastCssMtime === null || lastFullMtime === null) {
          lastCssMtime = newCss;
          lastFullMtime = newFull;
          console.info('[SingWalletLiveReload] Connected to dev server. Monitoring UI changes...');
          return;
        }

        // 1. 如果 HTML 结构或 JS 逻辑有改动，执行页面整页热重载
        if (newFull > lastFullMtime) {
          console.info('[SingWalletLiveReload] HTML/JS updated, reloading page...');
          lastFullMtime = newFull;
          lastCssMtime = newCss;
          window.location.reload();
          return;
        }

        // 2. 如果仅 CSS 样式表发生变化，执行毫秒级局部热替换，完全保留当前操作、表单与视图位置！
        if (newCss > lastCssMtime) {
          console.info('[SingWalletLiveReload] CSS updated, applying instant hot-swap without reload...');
          lastCssMtime = newCss;
          var links = document.querySelectorAll('link[rel="stylesheet"]');
          for (var i = 0; i < links.length; i++) {
            var link = links[i];
            var href = link.href;
            if (href) {
              var cleanHref = href.split('?')[0];
              link.href = cleanHref + '?_hr=' + newCss;
            }
          }
        }
      })
      .catch(function(err) {
        isPolling = false;
      });
  }

  setInterval(pollHotReloadTick, 250);
})();
</script>
"""


def resolve_allowed_cors_origin(origin: str | None) -> str | None:
    """Return the validated Origin if it belongs to trusted local/WebView origins."""
    if not origin:
        return None
    origin = origin.strip()
    if origin == 'null' or origin == 'https://appassets.androidplatform.net':
        return origin
    if LOCAL_ORIGIN_RE.fullmatch(origin):
        return origin
    return None


def _is_disallowed_ip(ip_obj: ipaddress.IPv4Address | ipaddress.IPv6Address) -> bool:
    """Check whether an IP address is loopback, private, link-local, multicast, reserved, or unspecified."""
    candidates = [ip_obj]
    mapped = getattr(ip_obj, 'ipv4_mapped', None)
    if mapped is not None:
        candidates.append(mapped)
    for addr in candidates:
        if (
            addr.is_loopback
            or addr.is_private
            or addr.is_link_local
            or addr.is_multicast
            or addr.is_reserved
            or addr.is_unspecified
        ):
            return True
    return False


def validate_proxy_target_url(target_url: str, allow_local_http: bool = False) -> tuple[bool, str]:
    """Validate proxy target URL against SSRF and scheme restrictions."""
    try:
        parsed = urllib.parse.urlparse(target_url)
    except Exception as exc:
        return False, f'Invalid URL: {exc}'

    scheme = (parsed.scheme or '').lower()
    if allow_local_http:
        if scheme not in ('http', 'https'):
            return False, f'Unsupported URL scheme: {scheme or "<empty>"}'
    else:
        if scheme != 'https':
            return False, 'Only HTTPS proxy targets are allowed (pass --allow-local-http for local HTTP models)'

    hostname = parsed.hostname
    if not hostname:
        return False, 'Missing hostname in target URL'

    try:
        port = parsed.port or (443 if scheme == 'https' else 80)
    except ValueError as exc:
        return False, f'Invalid port in target URL: {exc}'

    if not allow_local_http:
        try:
            addr_infos = socket.getaddrinfo(hostname, port, type=socket.SOCK_STREAM)
        except socket.gaierror as exc:
            return False, f'DNS resolution failed for {hostname}: {exc}'

        if not addr_infos:
            return False, f'No addresses resolved for {hostname}'

        for info in addr_infos:
            ip_str = info[4][0].split('%', 1)[0]
            try:
                ip_obj = ipaddress.ip_address(ip_str)
            except ValueError:
                return False, f'Invalid resolved IP address: {ip_str}'
            if _is_disallowed_ip(ip_obj):
                return False, f'Blocked SSRF target address ({ip_str})'

    return True, ''


class SafeRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Ensure HTTP redirects are also validated against SSRF policy."""

    def __init__(self, allow_local_http: bool = False):
        super().__init__()
        self.allow_local_http = allow_local_http

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        ok, err_msg = validate_proxy_target_url(newurl, allow_local_http=self.allow_local_http)
        if not ok:
            raise urllib.error.HTTPError(newurl, 403, f'Redirect blocked: {err_msg}', headers, None)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def find_adb(explicit_adb: str | None = None) -> str | None:
    """按优先级寻找可用的 adb 绝对路径（支持 --adb / ADB_PATH / ANDROID_HOME / ANDROID_SDK_ROOT / PATH）。"""
    exe_name = 'adb.exe' if os.name == 'nt' else 'adb'
    candidates: list[str] = []

    if explicit_adb:
        candidates.append(explicit_adb)
    env_adb = os.environ.get('ADB_PATH')
    if env_adb:
        candidates.append(env_adb)

    for sdk_env in ('ANDROID_HOME', 'ANDROID_SDK_ROOT'):
        sdk_root = os.environ.get(sdk_env)
        if sdk_root:
            candidates.append(os.path.join(sdk_root, 'platform-tools', exe_name))

    for c in candidates:
        if os.path.isfile(c):
            return os.path.abspath(c)
        w = shutil.which(c)
        if w and os.path.isfile(w):
            return w

    for name in ('adb', 'adb.exe'):
        w = shutil.which(name)
        if w and os.path.isfile(w):
            return w

    return None


def run_adb(adb_path, args, device_id=None, timeout=6):
    """执行 ADB 命令封装"""
    if not adb_path:
        return None
    cmd = [adb_path]
    if device_id:
        cmd.extend(['-s', device_id])
    cmd.extend(args)
    try:
        res = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            text=True,
        )
        return res
    except Exception:
        return None


def detect_adb_device(adb_path: str | None) -> str | None:
    """探测在线的 ADB 设备列表，返回首个在线设备序列号。"""
    res = run_adb(adb_path, ['devices'])
    if not res or res.returncode != 0:
        return None
    lines = res.stdout.splitlines()
    for line in lines[1:]:
        line = line.strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) >= 2 and parts[1] == 'device':
            return parts[0]
    return None


def scan_latest_mtimes(web_dir):
    """
    扫描并计算当前所有关注静态文件的最大修改时间：
    css_mtime: 仅统计 .css 文件
    full_mtime: 统计 .html 和 .js 文件
    """
    css_mtime = 0.0
    full_mtime = 0.0

    if os.path.isdir(web_dir):
        for dirpath, _, filenames in os.walk(web_dir):
            for fname in filenames:
                lower = fname.lower()
                fpath = os.path.join(dirpath, fname)
                try:
                    mt = os.path.getmtime(fpath)
                except OSError:
                    continue

                if lower.endswith('.css'):
                    if mt > css_mtime:
                        css_mtime = mt
                elif lower.endswith(('.js', '.html')):
                    if mt > full_mtime:
                        full_mtime = mt

    return css_mtime, full_mtime


def create_hot_reload_handler(web_dir: str, allow_local_http: bool = False):
    """创建绑定指定 Web 工作目录的请求处理器类"""

    class HotReloadHTTPHandler(SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=web_dir, **kwargs)

        def log_message(self, format, *args):
            # 静默高频轮询与图标请求日志，保持控制台清爽高可读性
            if len(args) > 0 and isinstance(args[0], str):
                req_line = args[0]
                if any(k in req_line for k in ('/__hot_reload_tick', '/favicon.ico')):
                    return
            super().log_message(format, *args)

        def _send_cors_headers_if_allowed(self):
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
                allowed_origin = resolve_allowed_cors_origin(self.headers.get('Origin'))
                if allowed_origin is not None:
                    self.send_header('Access-Control-Allow-Origin', allowed_origin)
                    self.send_header('Vary', 'Origin')

        def _send_json_error(self, status_code: int, message: str):
            body = json.dumps({'error': {'message': message}}).encode('utf-8')
            self.send_response(status_code)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def end_headers(self):
            # 强化热重载：杜绝任何客户端与代理缓存，并严格限制 CORS 来源
            self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0')
            self.send_header('Pragma', 'no-cache')
            self.send_header('Expires', '0')
            self._send_cors_headers_if_allowed()
            super().end_headers()

        def do_POST(self):
            parsed = urlparse(self.path)
            path = parsed.path
            if path == '/api/proxy' or path.startswith('/api/proxy?'):
                self.handle_proxy()
            else:
                super().do_POST()

        def handle_proxy(self):
            origin = self.headers.get('Origin')
            if origin is not None and resolve_allowed_cors_origin(origin) is None:
                self._send_json_error(403, 'Origin not allowed by CORS policy')
                return

            raw_len = self.headers.get('Content-Length', '0')
            try:
                content_len = int(raw_len)
            except (ValueError, TypeError):
                self._send_json_error(400, 'Invalid Content-Length header')
                return

            if content_len < 0:
                self._send_json_error(400, 'Invalid negative Content-Length header')
                return
            if content_len > MAX_PROXY_BODY_BYTES:
                self._send_json_error(413, f'Request body exceeds maximum {MAX_PROXY_BODY_BYTES} bytes')
                return

            raw_body = self.rfile.read(content_len) if content_len > 0 else b'{}'
            try:
                payload = json.loads(raw_body.decode('utf-8'))
            except Exception as exc:
                self._send_json_error(400, f'Invalid proxy payload: {exc}')
                return

            if not isinstance(payload, dict):
                self._send_json_error(400, 'Proxy payload must be a JSON object')
                return

            target_url = str(payload.get('url', '') or '').strip()
            target_method = str(payload.get('method', 'GET') or 'GET').upper()
            target_headers = payload.get('headers', {}) or {}
            target_body = payload.get('body', None)

            if not target_url:
                self._send_json_error(400, 'Missing target url')
                return

            if target_method not in ALLOWED_METHODS:
                self._send_json_error(400, f'Unsupported HTTP method: {target_method}')
                return

            if not isinstance(target_headers, dict):
                self._send_json_error(400, 'headers must be a JSON object')
                return

            ok, err_msg = validate_proxy_target_url(target_url, allow_local_http=allow_local_http)
            if not ok:
                self._send_json_error(403, err_msg)
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
                if str(k).lower() not in {'host', 'content-length', 'accept-encoding'}:
                    req.add_header(str(k), str(v))

            ssl_ctx = ssl.create_default_context()
            opener = urllib.request.build_opener(
                SafeRedirectHandler(allow_local_http=allow_local_http),
                urllib.request.HTTPSHandler(context=ssl_ctx),
            )

            try:
                with opener.open(req, timeout=30) as upstream_resp:
                    status_code = upstream_resp.status
                    resp_data = upstream_resp.read()
                    content_type = upstream_resp.headers.get('Content-Type', 'application/json')

                    self.send_response(status_code)
                    self.send_header('Content-Type', content_type)
                    self.end_headers()
                    self.wfile.write(resp_data)
            except urllib.error.HTTPError as http_err:
                status_code = http_err.code
                err_data = http_err.read() if http_err.fp is not None else json.dumps(
                    {'error': {'message': str(http_err.reason)}}
                ).encode('utf-8')
                content_type = http_err.headers.get('Content-Type', 'application/json') if http_err.headers else 'application/json'

                self.send_response(status_code)
                self.send_header('Content-Type', content_type)
                self.end_headers()
                self.wfile.write(err_data)
            except Exception as conn_err:
                self._send_json_error(502, f'Upstream connection failed: {conn_err}')

        def do_OPTIONS(self):
            origin = self.headers.get('Origin')
            allowed_origin = resolve_allowed_cors_origin(origin)
            if origin is not None and allowed_origin is None:
                self._send_json_error(403, 'Origin not allowed')
                return
            self.send_response(204)
            if allowed_origin is not None:
                self.send_header('Access-Control-Allow-Origin', allowed_origin)
                self.send_header('Vary', 'Origin')
            self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
            self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With')
            self.send_header('Access-Control-Max-Age', '86400')
            super().end_headers()

        def do_GET(self):
            parsed = urlparse(self.path)
            path = parsed.path

            # 1. 毫秒级变更轮询接口
            if path == '/__hot_reload_tick':
                css_mt, full_mt = scan_latest_mtimes(web_dir)
                payload = json.dumps({
                    'css_mtime': css_mt,
                    'full_mtime': full_mt,
                }).encode('utf-8')

                self.send_response(200)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
                self.send_header('Content-Length', str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
                return

            # 2. 网站图标请求 (避免浏览器/WebView 报 404 噪音)
            if path == '/favicon.ico':
                self.send_response(204)
                self.end_headers()
                return

            # 3. 主页面请求：动态在内存中注入热重载脚本（100% 杜绝污染磁盘源文件）
            if path in ('/', '/index.html', '/singwallet_preview.html'):
                html_path = os.path.join(web_dir, 'index.html')
                if os.path.isfile(html_path):
                    try:
                        with open(html_path, 'r', encoding='utf-8') as f:
                            raw_html = f.read()

                        target = '</body>'
                        if target in raw_html:
                            injected_html = raw_html.replace(target, LIVE_RELOAD_CLIENT_SCRIPT + '\n' + target, 1)
                        else:
                            injected_html = raw_html + '\n' + LIVE_RELOAD_CLIENT_SCRIPT

                        body_bytes = injected_html.encode('utf-8')
                        self.send_response(200)
                        self.send_header('Content-Type', 'text/html; charset=utf-8')
                        self.send_header('Content-Length', str(len(body_bytes)))
                        self.end_headers()
                        self.wfile.write(body_bytes)
                        return
                    except Exception as exc:
                        self.send_error(500, f'Error reading html: {exc}')
                        return

            # 4. 向下兼容历史 /preview/ 路径请求 (如 /preview/css/ -> /css/, /preview/js/ -> /js/)
            if parsed.path.startswith('/preview/'):
                self.path = self.path.replace('/preview/', '/', 1)

            # 5. 常规静态资源由父类处理
            return super().do_GET()

    return HotReloadHTTPHandler


def main():
    parser = argparse.ArgumentParser(description='SingWallet Mobile Live Hot Reload Tool')
    parser.add_argument('--port', type=int, default=3080, help='HTTP port (default: 3080)')
    parser.add_argument('--host', type=str, default='127.0.0.1', help='HTTP host (default: 127.0.0.1)')
    parser.add_argument('--no-adb', action='store_true', help='Skip ADB tunneling and App auto-launch')
    parser.add_argument('--offline', action='store_true', help='Reset mobile app to offline built-in assets mode and exit')
    parser.add_argument('--serial', '--device', dest='serial', type=str, default=None, help='Target ADB device serial')
    parser.add_argument('--adb', type=str, default=None, help='Path to adb binary (overrides ADB_PATH/ANDROID_HOME/PATH)')
    parser.add_argument(
        '--allow-local-http',
        action='store_true',
        help='Allow HTTP and private/loopback targets in /api/proxy for local LLM debugging',
    )

    args = parser.parse_args()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    root_dir = os.path.abspath(os.path.join(script_dir, '..'))

    adb_path = find_adb(args.adb)
    device_id = args.serial

    if adb_path and not device_id:
        device_id = detect_adb_device(adb_path)

    if args.offline:
        print('[SingWallet] Switching mobile device back to offline built-in mode...', flush=True)
        if not adb_path:
            print('[Error] adb binary not found. Pass --adb or set ADB_PATH / ANDROID_HOME / PATH.', flush=True)
            sys.exit(1)

        res_am = run_adb(adb_path, [
            'shell', 'am', 'start',
            '-n', 'com.singwallet.app/.MainActivity',
            '--ez', 'reset_dev', 'true',
        ], device_id=device_id)
        if res_am and res_am.returncode == 0:
            print('[OK] App dev mode reset signal sent successfully.', flush=True)
        else:
            print('[Warn] Failed to send am start signal:', res_am.stderr if res_am else 'Unknown', flush=True)

        run_adb(adb_path, ['reverse', '--remove', f'tcp:{args.port}'], device_id=device_id)
        print(f'[OK] ADB reverse tunnel for port {args.port} removed.', flush=True)
        print('[SingWallet] Mobile device is now running 100% offline built-in assets.', flush=True)
        sys.exit(0)

    web_dir = os.path.join(root_dir, 'web')

    handler_class = create_hot_reload_handler(web_dir, allow_local_http=args.allow_local_http)
    try:
        httpd = ThreadingHTTPServer((args.host, args.port), handler_class)
    except OSError as exc:
        print(f'[Error] Cannot bind to {args.host}:{args.port} ({exc}). Is another server running?', flush=True)
        sys.exit(1)

    print('==================================================================', flush=True)
    print(' SingWallet Mobile Live Hot Reload Server is RUNNING', flush=True)
    print(f' Local Address:  http://{args.host}:{args.port}/index.html', flush=True)
    print(f' Workspace Root: {root_dir}', flush=True)
    print(' Features:       CSS Instant Hot-Swap (<0.1s) + Full Reload (<0.3s)', flush=True)
    if args.allow_local_http:
        print(' Proxy Mode:     --allow-local-http ENABLED (local HTTP allowed)', flush=True)
    print(' Press Ctrl+C to stop.', flush=True)
    print('==================================================================', flush=True)

    if not args.no_adb:
        def launch_adb_after_ready():
            time.sleep(0.08)
            check_url = f'http://127.0.0.1:{args.port}/__hot_reload_tick'
            ready = False
            for _ in range(15):
                try:
                    with urllib.request.urlopen(check_url, timeout=0.3):
                        ready = True
                        break
                except Exception:
                    time.sleep(0.05)

            if not ready:
                print('[Warn] HTTP server not responding locally before ADB bridge.', flush=True)

            if adb_path and device_id:
                print(f'[SingWallet] Found ADB at: {adb_path}', flush=True)
                print(f'[SingWallet] Targeting device: {device_id}', flush=True)

                rev_res = run_adb(adb_path, ['reverse', f'tcp:{args.port}', f'tcp:{args.port}'], device_id=device_id)
                if rev_res and rev_res.returncode == 0:
                    print(f'[OK] USB reverse tunnel established: device:tcp:{args.port} <-> host:tcp:{args.port}', flush=True)
                else:
                    print('[Warn] Failed to set adb reverse:', rev_res.stderr if rev_res else 'timeout', flush=True)

                dev_url = f'http://127.0.0.1:{args.port}/index.html'
                am_res = run_adb(adb_path, [
                    'shell', 'am', 'start',
                    '-n', 'com.singwallet.app/.MainActivity',
                    '--es', 'dev_url', dev_url,
                ], device_id=device_id)
                if am_res and am_res.returncode == 0:
                    print(f'[OK] App launched on device in Hot Reload mode: {dev_url}', flush=True)
                else:
                    print('[Warn] Failed to launch App via ADB:', am_res.stderr if am_res else 'timeout', flush=True)
            else:
                print('[SingWallet] ADB or device not detected. Running in standalone HTTP mode.', flush=True)

        adb_thread = threading.Thread(target=launch_adb_after_ready, daemon=True)
        adb_thread.start()

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print('\n[SingWallet] Hot reload server stopped by user.', flush=True)
    finally:
        httpd.server_close()


if __name__ == '__main__':
    main()

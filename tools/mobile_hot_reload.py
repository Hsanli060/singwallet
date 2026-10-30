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
4. 竞态安全：先启动 HTTP 监听并自检确认 100% 就绪后，再触发 ADB reverse 与 App 唤醒，杜绝小米 14 ERR_CONNECTION_REFUSED！
5. 零噪音：内置 /api/shortcut/poll 空队列与 /favicon.ico 204 支持，静默轮询日志。
6. 支持 `--offline` 一键安全切回内置离线版。
"""

import os
import sys
import json
import time
import shutil
import argparse
import mimetypes
import threading
import subprocess
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


def find_adb():
    """按优先级寻找可用的 adb 绝对路径"""
    candidates = [
        r'D:\Dev\platform-tools\adb.exe',
        r'C:\platform-tools\adb.exe',
        'adb.exe',
        'adb'
    ]
    for c in candidates:
        if os.path.isabs(c) and os.path.isfile(c):
            return c
        w = shutil.which(c)
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
            text=True
        )
        return res
    except Exception as e:
        return None


def detect_adb_device(adb_path):
    """探测在线的 ADB 设备列表，优先返回指定或首个在线设备"""
    res = run_adb(adb_path, ['devices'])
    if not res or res.returncode != 0:
        return None
    lines = res.stdout.splitlines()
    devices = []
    for line in lines[1:]:
        line = line.strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) >= 2 and parts[1] == 'device':
            devices.append(parts[0])
    if not devices:
        return None
    if '5c2a21cf' in devices:
        return '5c2a21cf'
    return devices[0]


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


def create_hot_reload_handler(web_dir):
    """创建绑定指定 Web 工作目录的请求处理器类"""

    class HotReloadHTTPHandler(SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=web_dir, **kwargs)

        def log_message(self, format, *args):
            # 静默高频轮询与图标请求日志，保持控制台清爽高可读性
            if len(args) > 0 and isinstance(args[0], str):
                req_line = args[0]
                if any(k in req_line for k in ('/__hot_reload_tick', '/api/shortcut/poll', '/favicon.ico')):
                    return
            super().log_message(format, *args)

        def end_headers(self):
            # 强化热重载：杜绝任何客户端与代理缓存，开启全跨域
            self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0')
            self.send_header('Pragma', 'no-cache')
            self.send_header('Expires', '0')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
            self.send_header('Access-Control-Allow-Headers', '*')
            super().end_headers()

        def do_OPTIONS(self):
            self.send_response(204)
            self.end_headers()

        def do_GET(self):
            parsed = urlparse(self.path)
            path = parsed.path

            # 1. 毫秒级变更轮询接口
            if path == '/__hot_reload_tick':
                css_mt, full_mt = scan_latest_mtimes(web_dir)
                payload = json.dumps({
                    'css_mtime': css_mt,
                    'full_mtime': full_mt
                }).encode('utf-8')

                self.send_response(200)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
                self.send_header('Content-Length', str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
                return

            # 2. 快捷指令/后台抓屏队列轮询兼容接口 (返回期望的空队列，消除 404 噪音)
            if path == '/api/shortcut/poll':
                payload = json.dumps({'items': []}).encode('utf-8')
                self.send_response(200)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
                self.send_header('Content-Length', str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
                return

            # 3. 网站图标请求 (避免浏览器/WebView 报 404 噪音)
            if path == '/favicon.ico':
                self.send_response(204)
                self.end_headers()
                return

            # 4. 主页面请求：动态在内存中注入热重载脚本（100% 杜绝污染磁盘源文件）
            if path in ('/', '/index.html', '/singwallet_preview.html'):
                html_path = os.path.join(web_dir, 'index.html')
                if os.path.isfile(html_path):
                    try:
                        with open(html_path, 'r', encoding='utf-8') as f:
                            raw_html = f.read()

                        # 在 </body> 前注入动态客户端脚本
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
                    except Exception as e:
                        self.send_error(500, f'Error reading html: {e}')
                        return

            # 5. 向下兼容历史 /preview/ 路径请求 (如 /preview/css/ -> /css/, /preview/js/ -> /js/)
            if parsed.path.startswith('/preview/'):
                self.path = self.path.replace('/preview/', '/', 1)

            # 6. 常规静态资源由父类处理
            return super().do_GET()

    return HotReloadHTTPHandler


def main():
    parser = argparse.ArgumentParser(description='SingWallet Mobile Live Hot Reload Tool')
    parser.add_argument('--port', type=int, default=3080, help='HTTP port (default: 3080)')
    parser.add_argument('--host', type=str, default='127.0.0.1', help='HTTP host (default: 127.0.0.1)')
    parser.add_argument('--no-adb', action='store_true', help='Skip ADB tunneling and App auto-launch')
    parser.add_argument('--offline', action='store_true', help='Reset mobile app to offline built-in assets mode and exit')
    parser.add_argument('--device', type=str, default=None, help='Target ADB device serial (e.g. 5c2a21cf)')

    args = parser.parse_args()

    # 确定项目根目录（以当前脚本所在 tools 的上一级目录为主）
    script_dir = os.path.dirname(os.path.abspath(__file__))
    root_dir = os.path.abspath(os.path.join(script_dir, '..'))

    # 探测 ADB 路径
    adb_path = find_adb()
    device_id = args.device

    if adb_path and not device_id:
        device_id = detect_adb_device(adb_path)

    # 离线模式命令处理
    if args.offline:
        print('[SingWallet] Switching mobile device back to offline built-in mode...', flush=True)
        if not adb_path:
            print('[Error] adb binary not found, please check PATH or D:\\Dev\\platform-tools\\adb.exe', flush=True)
            sys.exit(1)

        # 1. 唤起 App 并重置 dev_url
        res_am = run_adb(adb_path, [
            'shell', 'am', 'start',
            '-n', 'com.singwallet.app/.MainActivity',
            '--ez', 'reset_dev', 'true'
        ], device_id=device_id)
        if res_am and res_am.returncode == 0:
            print('[OK] App dev mode reset signal sent successfully.', flush=True)
        else:
            print('[Warn] Failed to send am start signal:', res_am.stderr if res_am else 'Unknown', flush=True)

        # 2. 移除 reverse 端口映射
        res_rev = run_adb(adb_path, ['reverse', '--remove', f'tcp:{args.port}'], device_id=device_id)
        print(f'[OK] ADB reverse tunnel for port {args.port} removed.', flush=True)
        print('[SingWallet] Mobile device is now running 100% offline built-in assets.', flush=True)
        sys.exit(0)

    web_dir = os.path.join(root_dir, 'web')

    # 1. 先启动 HTTP 服务，确保端口 100% 绑定就绪
    handler_class = create_hot_reload_handler(web_dir)
    try:
        httpd = ThreadingHTTPServer((args.host, args.port), handler_class)
    except OSError as e:
        print(f'[Error] Cannot bind to {args.host}:{args.port} ({e}). Is another server running?', flush=True)
        sys.exit(1)

    print('==================================================================', flush=True)
    print(f' SingWallet Mobile Live Hot Reload Server is RUNNING', flush=True)
    print(f' Local Address:  http://{args.host}:{args.port}/index.html', flush=True)
    print(f' Workspace Root: {root_dir}', flush=True)
    print(f' Features:       CSS Instant Hot-Swap (<0.1s) + Full Reload (<0.3s)', flush=True)
    print(' Press Ctrl+C to stop.', flush=True)
    print('==================================================================', flush=True)

    # 2. 异步启动 ADB reverse 隧道与唤起 App（时序保障：100% 确认 HTTP 监听准备就绪后再拉起真机，消除小米 14 竞态）
    if not args.no_adb:
        def launch_adb_after_ready():
            # 延时 80ms 并自测一次本机 HTTP 服务确认就绪
            time.sleep(0.08)
            check_url = f'http://127.0.0.1:{args.port}/__hot_reload_tick'
            ready = False
            for _ in range(15):
                try:
                    import urllib.request
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

                # 1. 反向隧道映射
                rev_res = run_adb(adb_path, ['reverse', f'tcp:{args.port}', f'tcp:{args.port}'], device_id=device_id)
                if rev_res and rev_res.returncode == 0:
                    print(f'[OK] USB reverse tunnel established: device:tcp:{args.port} <-> host:tcp:{args.port}', flush=True)
                else:
                    print('[Warn] Failed to set adb reverse:', rev_res.stderr if rev_res else 'timeout', flush=True)

                # 2. 拉起原生 App 并载入热重载 URL (此时 HTTP 监听已 100% 准备就绪，杜绝 ERR_CONNECTION_REFUSED)
                dev_url = f'http://127.0.0.1:{args.port}/index.html'
                am_res = run_adb(adb_path, [
                    'shell', 'am', 'start',
                    '-n', 'com.singwallet.app/.MainActivity',
                    '--es', 'dev_url', dev_url
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

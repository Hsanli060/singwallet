import sys
import json
import ssl
import time
import base64
import mimetypes
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

# In-memory queue for shortcut capture / ingest
SHORTCUT_QUEUE = []

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
        else:
            super().do_GET()

    def do_POST(self):
        if self.path == '/api/proxy' or self.path.startswith('/api/proxy?'):
            self.handle_proxy()
        elif self.path.startswith('/api/shortcut/adb-capture'):
            self.handle_shortcut_adb_capture()
        elif self.path.startswith('/api/shortcut/ingest'):
            self.handle_shortcut_ingest()
        else:
            super().do_POST()

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

        adb_path = r'D:\Dev\platform-tools\adb.exe'
        device_id = '5c2a21cf'
        cmd = [adb_path, '-s', device_id, 'exec-out', 'screencap', '-p']
        img_bytes = None
        try:
            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
            img_bytes = res.stdout
            if not img_bytes or len(img_bytes) < 1000:
                cmd_fallback = [adb_path, 'exec-out', 'screencap', '-p']
                res2 = subprocess.run(cmd_fallback, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
                img_bytes = res2.stdout
        except Exception as e:
            self.send_response(500)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'error': f'ADB capture failed: {e}'}).encode('utf-8'))
            return

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
        SHORTCUT_QUEUE.append(item)

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
                'count': len(SHORTCUT_QUEUE)
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
        SHORTCUT_QUEUE.append(item)

        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({
            'status': 'ok',
            'message': '已接收快捷指令图片并推入后台识别队列',
            'id': item['id'],
            'count': len(SHORTCUT_QUEUE)
        }).encode('utf-8'))

    def handle_shortcut_poll(self):
        global SHORTCUT_QUEUE
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

def run_server(port=8765):
    server_address = ('0.0.0.0', port)
    httpd = ThreadingHTTPServer(server_address, ProxyHTTPRequestHandler)
    print(f'SingWallet preview server with /api/proxy running on http://0.0.0.0:{port}')
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    run_server(port)

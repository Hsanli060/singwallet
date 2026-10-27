import sys
import json
import ssl
import mimetypes
import urllib.request
import urllib.error
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

# Windows MIME types registration
mimetypes.add_type('application/javascript', '.js')
mimetypes.add_type('text/css', '.css')
mimetypes.add_type('text/html', '.html')
mimetypes.add_type('application/json', '.json')

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
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.send_header('Access-Control-Max-Age', '86400')
        super().end_headers()

    def do_POST(self):
        if self.path == '/api/proxy' or self.path.startswith('/api/proxy?'):
            self.handle_proxy()
        else:
            super().do_POST()

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
        # Copy headers, skip host, content-length, accept-encoding
        for k, v in target_headers.items():
            if k.lower() not in ['host', 'content-length', 'accept-encoding']:
                req.add_header(k, str(v))

        # SSL context ignoring verification for custom domains/ports
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
    server_address = ('127.0.0.1', port)
    httpd = ThreadingHTTPServer(server_address, ProxyHTTPRequestHandler)
    print(f'SingWallet preview server with /api/proxy running on http://127.0.0.1:{port}')
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    run_server(port)

import http.server
import socketserver
import urllib.request
import urllib.parse
import ssl
import json
import os
import sys

PORT = 8088
DIRECTORY = os.path.dirname(os.path.abspath(__file__))

class DualProxyHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS, PUT, DELETE')
        self.send_header('Access-Control-Allow-Headers', '*')
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()

    def do_POST(self):
        if self.path.startswith('/api/proxy'):
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length)
            try:
                payload = json.loads(post_data.decode('utf-8'))
                target_url = payload.get('url')
                headers = payload.get('headers', {})
                body_data = payload.get('body', {})

                ctx = ssl.create_default_context()
                ctx.check_hostname = False
                ctx.verify_mode = ssl.CERT_NONE

                if isinstance(body_data, (dict, list)):
                    req_bytes = json.dumps(body_data).encode('utf-8')
                elif isinstance(body_data, str):
                    req_bytes = body_data.encode('utf-8')
                else:
                    req_bytes = None

                req = urllib.request.Request(
                    target_url,
                    data=req_bytes,
                    headers=headers,
                    method='POST'
                )

                try:
                    with urllib.request.urlopen(req, timeout=30, context=ctx) as resp:
                        resp_data = resp.read()
                        self.send_response(resp.status)
                        self.send_header('Content-Type', resp.headers.get('Content-Type', 'application/json'))
                        self.end_headers()
                        self.wfile.write(resp_data)
                except urllib.error.HTTPError as e:
                    err_bytes = e.read()
                    self.send_response(e.code)
                    self.send_header('Content-Type', e.headers.get('Content-Type', 'application/json'))
                    self.end_headers()
                    self.wfile.write(err_bytes)
            except Exception as e:
                self.send_response(500)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({'error': str(e)}).encode('utf-8'))
        else:
            super().do_POST()

if __name__ == '__main__':
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("", PORT), DualProxyHTTPRequestHandler) as httpd:
        print(f"Serving HTTP on port {PORT} with /api/proxy support...")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down server.")

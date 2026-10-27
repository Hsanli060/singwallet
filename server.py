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

def get_adaptive_candidates(raw_url):
    u = (raw_url or '').strip().rstrip('/')
    if not u:
        return []
    if ':generateContent' in u or 'googleapis.com' in u:
        return [u]
    if u.endswith('/chat/completions'):
        return [u]
    if u.endswith('/v1'):
        return [f'{u}/chat/completions', u.replace('/v1', '/chat/completions'), u]
    return [f'{u}/v1/chat/completions', f'{u}/chat/completions', f'{u}/v1', u]

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
                target_url = payload.get('url', '')
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

                candidates = get_adaptive_candidates(target_url)
                last_error_resp = None
                success = False

                for cand in candidates:
                    try:
                        req = urllib.request.Request(
                            cand,
                            data=req_bytes,
                            headers=headers,
                            method='POST'
                        )
                        with urllib.request.urlopen(req, timeout=30, context=ctx) as resp:
                            resp_data = resp.read()
                            self.send_response(resp.status)
                            self.send_header('Content-Type', resp.headers.get('Content-Type', 'application/json'))
                            self.send_header('X-Resolved-Endpoint', cand)
                            self.end_headers()
                            self.wfile.write(resp_data)
                            success = True
                            break
                    except urllib.error.HTTPError as e:
                        err_bytes = e.read()
                        # If 404 and there are more candidates, try next candidate
                        if e.code == 404 and cand != candidates[-1]:
                            continue
                        last_error_resp = (e.code, e.headers.get('Content-Type', 'application/json'), err_bytes)
                        # If 401 or other client error that is not 404, break immediately
                        if e.code != 404:
                            break
                    except Exception as e:
                        if cand != candidates[-1]:
                            continue
                        raise e

                if not success and last_error_resp:
                    code, ctype, err_bytes = last_error_resp
                    self.send_response(code)
                    self.send_header('Content-Type', ctype)
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
        print(f"Serving HTTP on port {PORT} with adaptive /api/proxy support...")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down server.")

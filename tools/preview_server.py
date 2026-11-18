import argparse
import ipaddress
import json
import mimetypes
import os
import re
import socket
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEB_DIR = os.path.join(REPO_ROOT, 'web')
MAX_PROXY_BODY_BYTES = 15 * 1024 * 1024
ALLOWED_METHODS = {'GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'}
LOCAL_ORIGIN_RE = re.compile(r'^http://(127\.0\.0\.1|localhost)(:\d{1,5})?$')

# Windows MIME types registration
mimetypes.add_type('application/javascript', '.js')
mimetypes.add_type('text/css', '.css')
mimetypes.add_type('text/html', '.html')
mimetypes.add_type('application/json', '.json')


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


def create_proxy_handler(allow_local_http: bool = False):
    """Create a ProxyHTTPRequestHandler class configured with the given SSRF policy."""

    class ProxyHTTPRequestHandler(SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=WEB_DIR, **kwargs)

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
            self._send_cors_headers_if_allowed()
            # Disable all caching for instant hot-reload
            self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0')
            self.send_header('Pragma', 'no-cache')
            self.send_header('Expires', '0')
            super().end_headers()

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
            self.send_header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
            self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With')
            self.send_header('Access-Control-Max-Age', '86400')
            super().end_headers()

        def do_GET(self):
            if self.path in ('/', '/singwallet_preview.html'):
                self.path = '/index.html'
            super().do_GET()

        def do_POST(self):
            if self.path == '/api/proxy' or self.path.startswith('/api/proxy?'):
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

    return ProxyHTTPRequestHandler


def run_server(host: str = '127.0.0.1', port: int = 8765, allow_local_http: bool = False):
    handler_cls = create_proxy_handler(allow_local_http=allow_local_http)
    httpd = ThreadingHTTPServer((host, port), handler_cls)
    print(f'SingWallet preview server with /api/proxy running on http://{host}:{port}', flush=True)
    if allow_local_http:
        print('[WARN] --allow-local-http is enabled: local/private HTTP targets are permitted.', flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()


def main():
    parser = argparse.ArgumentParser(description='SingWallet Local Preview & Secure Proxy Server')
    parser.add_argument('legacy_port', nargs='?', type=int, default=None, help=argparse.SUPPRESS)
    parser.add_argument('--host', type=str, default='127.0.0.1', help='Bind host (default: 127.0.0.1)')
    parser.add_argument('--port', type=int, default=8765, help='Bind port (default: 8765)')
    parser.add_argument(
        '--allow-local-http',
        action='store_true',
        help='Allow HTTP and private/loopback targets in /api/proxy for local LLM debugging',
    )
    args = parser.parse_args()
    port = args.legacy_port if args.legacy_port is not None else args.port
    run_server(host=args.host, port=port, allow_local_http=args.allow_local_http)


if __name__ == '__main__':
    main()

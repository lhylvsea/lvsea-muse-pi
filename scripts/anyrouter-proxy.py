#!/usr/bin/env python3
"""AnyRouter 本地反向代理：把 pi 的 OpenAI 兼容请求转发到 AnyRouter。

监听 127.0.0.1:3426，路径映射：
    /v1/chat/completions -> https://anyrouter.dev/api/v1/chat/completions
    /v1/models           -> https://anyrouter.dev/api/v1/models

认证：每个转发请求现场向 authd 要一个 hsurr: surrogate，
放在 Authorization: Bearer 头里；Sentinel 在出口处换成真实 key。
key 本身不落地、不进环境变量、不进日志。

用法：
    python3 anyrouter-proxy.py [--port 3426]
由 ~/workspace/bin/pi-reason.sh 按需拉起（仿照 magpie 网关）。
"""
from __future__ import annotations

import argparse
import sys
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, "/opt/muse/skills/custom-connector-setup/bin")
from dynamic_credentials import (
    DynamicCredentialError,
    add_surrogate_to_request,
    read_response_body,
)

UPSTREAM = "https://anyrouter.dev/api"
CREDENTIAL = "custom.anyrouter"
ALLOWED_HOSTS = ["anyrouter.dev"]

HOP_BY_HOP = {
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "trailer", "transfer-encoding", "upgrade",
}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args):
        raise RuntimeError("redirect refused, verify the endpoint")


def build_upstream_request(path: str, method: str, in_headers, body: bytes | None):
    if not path.startswith("/v1/"):
        raise ValueError(f"refusing non-/v1 path: {path}")
    url = UPSTREAM + path  # /v1/chat/completions -> https://anyrouter.dev/api/v1/chat/completions
    req = urllib.request.Request(url, data=body, method=method)
    ctype = in_headers.get("Content-Type")
    if ctype:
        req.add_header("Content-Type", ctype)
    accept = in_headers.get("Accept")
    if accept:
        req.add_header("Accept", accept)
    # 现场取 surrogate，替换掉调用方可能自带的 Authorization
    add_surrogate_to_request(req, CREDENTIAL, allowed_hosts=ALLOWED_HOSTS)
    return req


class Handler(BaseHTTPRequestHandler):
    server_version = "AnyRouterProxy/1.0"

    def log_message(self, fmt, *args):
        sys.stderr.write("anyrouter-proxy: " + fmt % args + "\n")

    def _proxy(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length > 0 else None
        try:
            req = build_upstream_request(self.path, self.command, self.headers, body)
        except (ValueError, DynamicCredentialError) as exc:
            self.send_error(502, str(exc))
            return
        try:
            opener = urllib.request.build_opener(NoRedirect())
            resp = opener.open(req, timeout=300)
        except Exception as exc:  # noqa: BLE001 - 转成 502 给调用方
            self.send_error(502, f"upstream error: {exc}")
            return
        try:
            self.send_response(resp.status)
            for key, value in resp.getheaders():
                if key.lower() in HOP_BY_HOP or key.lower() == "content-length":
                    continue
                self.send_header(key, value)
            self.end_headers()
            # 流式透传（SSE / 普通 JSON 都适用）
            while True:
                chunk = resp.read(65536)
                if not chunk:
                    break
                self.wfile.write(chunk)
                self.wfile.flush()
        finally:
            resp.close()

    do_GET = _proxy
    do_POST = _proxy
    do_PUT = _proxy
    do_DELETE = _proxy


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=3426)
    args = ap.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    sys.stderr.write(f"anyrouter-proxy: listening on 127.0.0.1:{args.port}\n")
    server.serve_forever()


if __name__ == "__main__":
    main()

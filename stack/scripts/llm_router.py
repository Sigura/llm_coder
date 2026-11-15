"""OpenAI-compatible router: one model id ("auto") in front of several llama.cpp servers, picked by prompt size.

Each --tier is NAME=URL,MODEL,KEY_FILE,MAX_PROMPT_TOKENS (the last tier has no limit: use 0). A chat request goes to
the first tier whose limit fits the estimated prompt. A conversation never moves back to a smaller tier, so the
bigger server's prefix cache stays valid; a conversation is identified by a hash of its messages up to the first user
message (system prompt + first request).
"""
import argparse
import hashlib
import json
import sys
import threading
import time
import urllib.error
import urllib.request
from collections import OrderedDict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# Code and JSON tokenize at ~3.2-3.6 chars/token with Qwen/DeepSeek vocabularies; 3.0 overestimates on purpose so
# a request switches to the bigger tier a little early instead of overflowing the smaller one.
CHARS_PER_TOKEN = 3.0
STICKY_MAX = 4096


class Tier:
    def __init__(self, spec: str):
        name, rest = spec.split("=", 1)
        url, model, key_file, limit = rest.split(",")
        self.name, self.url, self.model, self.limit = name, url.rstrip("/"), model, int(limit)
        with open(key_file) as f:
            self.key = f.read().strip()


def estimate_tokens(body: dict) -> int:
    chars = len(json.dumps(body.get("messages", []), ensure_ascii=False))
    chars += len(json.dumps(body.get("tools", []), ensure_ascii=False))
    return int(chars / CHARS_PER_TOKEN)


def conversation_key(body: dict) -> str:
    msgs = body.get("messages", [])
    first_user = next((i for i, m in enumerate(msgs) if m.get("role") == "user"), len(msgs) - 1)
    head = json.dumps(msgs[:first_user + 1], ensure_ascii=False, sort_keys=True)
    return hashlib.sha1(head.encode()).hexdigest()


class Router:
    def __init__(self, tiers: list[Tier], key: str, model_id: str, context: int):
        self.tiers, self.key, self.model_id, self.context = tiers, key, model_id, context
        self.sticky: OrderedDict[str, int] = OrderedDict()
        self.lock = threading.Lock()

    def pick(self, body: dict) -> tuple[Tier, int]:
        tokens = estimate_tokens(body)
        need = next((i for i, t in enumerate(self.tiers) if t.limit == 0 or tokens <= t.limit), len(self.tiers) - 1)
        conv = conversation_key(body)
        with self.lock:
            idx = max(need, self.sticky.get(conv, 0))
            self.sticky[conv] = idx
            self.sticky.move_to_end(conv)
            while len(self.sticky) > STICKY_MAX:
                self.sticky.popitem(last=False)
        return self.tiers[idx], tokens


def make_handler(router: Router):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.0"

        def log_message(self, fmt, *args):
            sys.stderr.write(f"{time.strftime('%H:%M:%S')} {fmt % args}\n")

        def send_json(self, code: int, obj: dict):
            data = json.dumps(obj).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def authorized(self) -> bool:
            if self.headers.get("Authorization", "") == f"Bearer {router.key}":
                return True
            self.send_json(401, {"error": {"code": 401, "message": "invalid API key"}})
            return False

        def do_GET(self):
            if self.path == "/health":
                return self.send_json(200, {"status": "ok"})
            if not self.authorized():
                return
            if self.path == "/v1/models":
                return self.send_json(200, {"object": "list", "data": [
                    {"id": router.model_id, "object": "model", "owned_by": "llm-router",
                     "meta": {"n_ctx": router.context, "tiers": [t.name for t in router.tiers]}}]})
            self.send_json(404, {"error": {"code": 404, "message": "not found"}})

        def do_POST(self):
            if not self.authorized():
                return
            if self.path != "/v1/chat/completions":
                return self.send_json(404, {"error": {"code": 404, "message": "only /v1/chat/completions"}})
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
            tier, tokens = router.pick(body)
            body["model"] = tier.model
            self.log_message("~%d prompt tokens -> %s", tokens, tier.name)
            req = urllib.request.Request(f"{tier.url}/v1/chat/completions", json.dumps(body).encode(),
                                         {"Content-Type": "application/json", "Authorization": f"Bearer {tier.key}"})
            try:
                resp = urllib.request.urlopen(req, timeout=3600)
            except urllib.error.HTTPError as e:
                resp = e
            self.send_response(resp.status)
            for k in ("Content-Type", "Cache-Control"):
                if resp.headers.get(k):
                    self.send_header(k, resp.headers[k])
            self.send_header("X-Router-Tier", tier.name)
            self.end_headers()
            while chunk := resp.read1(65536):
                self.wfile.write(chunk)
                self.wfile.flush()

    return Handler


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, required=True)
    p.add_argument("--key-file", required=True, help="API key clients must send")
    p.add_argument("--model-id", default="auto")
    p.add_argument("--context", type=int, required=True, help="context size reported to clients (the last tier's)")
    p.add_argument("--tier", action="append", required=True, help="NAME=URL,MODEL,KEY_FILE,MAX_PROMPT_TOKENS")
    args = p.parse_args()
    with open(args.key_file) as f:
        key = f.read().strip()
    router = Router([Tier(s) for s in args.tier], key, args.model_id, args.context)
    for t in router.tiers:
        print(f"tier {t.name}: {t.url} model {t.model}, prompt <= {t.limit or 'any'}", file=sys.stderr)
    print(f"listening on http://{args.host}:{args.port}", file=sys.stderr)
    ThreadingHTTPServer((args.host, args.port), make_handler(router)).serve_forever()


if __name__ == "__main__":
    main()

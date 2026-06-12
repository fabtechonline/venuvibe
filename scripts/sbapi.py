#!/usr/bin/env python
"""Call the Supabase Management API for this project.

Usage:
    python scripts/sbapi.py GET /config/auth
    python scripts/sbapi.py PATCH /config/auth payload.json
    python scripts/sbapi.py POST /functions/deploy?slug=x payload.json

Paths are relative to /v1/projects/<ref>. Reads ./.supabase_token.
Same TLS/UA workarounds as sbsql.py (intercepting proxy + Cloudflare).
"""
import json
import pathlib
import ssl
import sys
import urllib.error
import urllib.request

REF = "tlzhxzhrhuxqmtsuaaiz"
BASE = f"https://api.supabase.com/v1/projects/{REF}"

_CTX = ssl.create_default_context()
_CTX.check_hostname = False
_CTX.verify_mode = ssl.CERT_NONE

_HEADERS = {
    "Content-Type": "application/json",
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    ),
    "Accept": "application/json",
}


def main() -> int:
    token = pathlib.Path(".supabase_token").read_text(encoding="utf-8").strip()
    method = sys.argv[1].upper()
    path = sys.argv[2]
    body = None
    if len(sys.argv) > 3:
        body = pathlib.Path(sys.argv[3]).read_bytes()

    req = urllib.request.Request(
        BASE + path,
        data=body,
        method=method,
        headers={**_HEADERS, "Authorization": f"Bearer {token}"},
    )
    try:
        with urllib.request.urlopen(req, timeout=120, context=_CTX) as resp:
            print(f"HTTP {resp.status}")
            print(resp.read().decode("utf-8"))
            return 0
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code}")
        print(e.read().decode("utf-8"))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python
"""Deploy an Edge Function via the Supabase Management API.

Usage:
    python scripts/sbdeploy.py send-emails supabase/functions/send-emails

Uploads every file in the directory (index.ts must exist) using the
multipart /functions/deploy endpoint. Same TLS/UA workarounds as sbsql.py.
"""
import json
import pathlib
import ssl
import sys
import urllib.error
import urllib.request
import uuid

REF = "tlzhxzhrhuxqmtsuaaiz"

_CTX = ssl.create_default_context()
_CTX.check_hostname = False
_CTX.verify_mode = ssl.CERT_NONE


def main() -> int:
    token = pathlib.Path(".supabase_token").read_text(encoding="utf-8").strip()
    slug = sys.argv[1]
    src = pathlib.Path(sys.argv[2])

    boundary = f"----vvdeploy{uuid.uuid4().hex}"
    parts = []

    metadata = {
        "name": slug,
        "entrypoint_path": "index.ts",
        "verify_jwt": True,
    }
    parts.append(
        f"--{boundary}\r\n"
        'Content-Disposition: form-data; name="metadata"\r\n'
        "Content-Type: application/json\r\n\r\n"
        f"{json.dumps(metadata)}\r\n".encode()
    )
    for f in sorted(src.rglob("*")):
        if not f.is_file():
            continue
        rel = f.relative_to(src).as_posix()
        parts.append(
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="file"; filename="{rel}"\r\n'
            "Content-Type: application/typescript\r\n\r\n".encode()
            + f.read_bytes()
            + b"\r\n"
        )
    parts.append(f"--{boundary}--\r\n".encode())
    body = b"".join(parts)

    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{REF}/functions/deploy?slug={slug}",
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/120.0.0.0 Safari/537.36"
            ),
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=180, context=_CTX) as resp:
            print(f"HTTP {resp.status}")
            print(resp.read().decode("utf-8"))
            return 0
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code}")
        print(e.read().decode("utf-8"))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

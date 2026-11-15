#!/usr/bin/env python3
"""Download the Wii U title database and turn it into native_lib/db.go.

The download is retried on transient network failures, validated, and written
atomically so a failed run can never leave a partial or empty db.go behind.
TLS certificate verification stays enabled.
"""
import http.client
import os
import sys
import tempfile
import time
import urllib.error
import urllib.request

URL = "https://napi.v10lator.de/db?t=go"
MARKER = "var titleEntry"
DEST_PATH = "db.go"
TIMEOUT_SECONDS = 30
MAX_ATTEMPTS = 5
BACKOFF_SECONDS = 3  # waits 3, 6, 12, 24 between attempts

HEADER = 'package main\nimport wiiudownloader "github.com/Xpl0itU/WiiUDownloader"\n'


def is_retryable(exc):
    if isinstance(exc, urllib.error.HTTPError):
        # Retry server-side problems and rate limiting, not client errors.
        return exc.code >= 500 or exc.code in (408, 429)
    return isinstance(
        exc,
        (urllib.error.URLError, http.client.HTTPException, ConnectionError, TimeoutError, OSError),
    )


def fetch_database():
    request = urllib.request.Request(URL, headers={"User-Agent": "NUSspliBuilder/2.1"})
    last_error = None
    for attempt in range(1, MAX_ATTEMPTS + 1):
        try:
            print(f"Downloading db.go (attempt {attempt}/{MAX_ATTEMPTS})...")
            with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
                content = response.read().decode("utf-8")
            if not content.strip():
                raise ValueError("server returned an empty response")
            if MARKER not in content:
                raise ValueError(f"response does not contain {MARKER!r}")
            return content
        except Exception as exc:  # noqa: BLE001 - classified below
            last_error = exc
            retryable = is_retryable(exc) or isinstance(exc, (ValueError, UnicodeDecodeError))
            print(f"Attempt {attempt} failed: {exc!r}", file=sys.stderr)
            if not retryable or attempt == MAX_ATTEMPTS:
                break
            delay = BACKOFF_SECONDS * (2 ** (attempt - 1))
            print(f"Retrying in {delay}s...", file=sys.stderr)
            time.sleep(delay)
    raise RuntimeError(f"Could not download the title database: {last_error!r}")


def transform(content):
    _, sep, after = content.partition(MARKER)
    content = HEADER + sep + after
    return content.replace("[]TitleEntry{", "[]wiiudownloader.TitleEntry{")


def write_atomically(path, content):
    directory = os.path.dirname(os.path.abspath(path))
    fd, tmp_path = tempfile.mkstemp(prefix=".db.go.", suffix=".tmp", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_path, path)  # atomic on the same filesystem
    except BaseException:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)
        raise


def main():
    content = transform(fetch_database())
    write_atomically(DEST_PATH, content)
    print(f"Database saved to {DEST_PATH}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)

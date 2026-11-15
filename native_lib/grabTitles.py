#!/usr/bin/env python3
import os
import ssl
import time
import urllib.error
import urllib.request

URL = "https://napi.v10lator.de/db?t=go"
MAX_RETRIES = 5
TIMEOUT_SECONDS = 30


def checkAndDeleteFile(file):
    if os.path.exists(file):
        print(f"Deleting {file}")
        os.remove(file)


def fetch_database():
    ssl_context = ssl.create_default_context()
    ssl_context.check_hostname = False
    ssl_context.verify_mode = ssl.CERT_NONE

    opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=ssl_context))
    opener.addheaders = [("User-agent", "NUSspliBuilder/2.1")]

    for attempt in range(1, MAX_RETRIES + 1):
        try:
            with opener.open(URL, timeout=TIMEOUT_SECONDS) as response:
                content_bytes = response.read()

            if not content_bytes:
                raise ValueError("Downloaded database was empty")

            content = content_bytes.decode("utf-8")
            if "var titleEntry" not in content:
                raise ValueError("Downloaded database does not contain 'var titleEntry'")

            return content
        except (urllib.error.URLError, TimeoutError, ValueError, OSError) as exc:
            print(f"Download attempt {attempt}/{MAX_RETRIES} failed: {exc}")
            if attempt == MAX_RETRIES:
                raise
            time.sleep(2 ** attempt)

    raise RuntimeError("Failed to download database")


def main():
    dest_path = "db.go"
    checkAndDeleteFile(dest_path)

    print("Downloading db.go...")
    content = fetch_database()

    before, sep, after = content.partition("var titleEntry")
    if not sep:
        raise ValueError("Could not locate titleEntry data in downloaded database")

    content = "package main\nimport wiiudownloader \"github.com/Xpl0itU/WiiUDownloader\"\n" + sep + after
    content = content.replace("[]TitleEntry{", "[]wiiudownloader.TitleEntry{")

    with open(dest_path, "w", encoding="utf-8") as f:
        f.write(content)

    print(f"Database saved to {dest_path}")


if __name__ == "__main__":
    main()

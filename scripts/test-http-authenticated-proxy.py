#!/usr/bin/env python3
"""Exercise VLC Neo's saved HTTP proxy credentials against a 407 challenge.

VLC 3.0.20 and 3.0.24 send the configured Basic credentials after the
challenge, then fail to seek the authenticated stream. Keep this check so a
future core fix is recognized as playback instead of the known error.
"""

from __future__ import annotations

import base64
import http.server
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time


ROOT = Path(__file__).resolve().parents[1]
BUILD_DIR = Path(os.environ.get("NEO_BUILD_DIR", ROOT / "build"))
PASSWORD = "neo-auth-proxy-regression"
USERNAME = "neo-proxy-user"
EXPECTED_AUTH = "Basic " + base64.b64encode((USERNAME + ":" + PASSWORD).encode()).decode()


def vlc_version() -> tuple[int, int, int]:
    command = os.environ.get("SYSTEM_VLC", "/usr/bin/vlc")
    output = subprocess.run([command, "--version"], check=True, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT).stdout
    match = re.search(r"VLC version (\d+)\.(\d+)\.(\d+)", output)
    if not match:
        raise RuntimeError(f"Could not parse VLC version from: {output.splitlines()[0]}")
    return tuple(map(int, match.groups()))


def main() -> int:
    if not shutil.which("ffmpeg"):
        print("SKIP: ffmpeg is required to create the tiny local fixture")
        return 0

    version = vlc_version()
    with tempfile.TemporaryDirectory(prefix="neo-auth-proxy-") as temp:
        work = Path(temp)
        media_path = work / "fixture.mp4"
        subprocess.run([
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "color=c=red:s=160x90:r=10",
            "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=44100",
            "-t", "12", "-c:v", "mpeg4", "-q:v", "6", "-c:a", "aac",
            "-movflags", "+faststart", str(media_path),
        ], check=True)
        media = media_path.read_bytes()
        stats = {"unauthenticated": 0, "authenticated": 0, "bad_auth": 0, "ranges": 0}

        class Proxy(http.server.BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def do_GET(self) -> None:
                auth = self.headers.get("Proxy-Authorization", "")
                if auth != EXPECTED_AUTH:
                    if auth:
                        stats["bad_auth"] += 1
                    else:
                        stats["unauthenticated"] += 1
                    self.send_response(407, "Proxy Authentication Required")
                    self.send_header("Proxy-Authenticate", 'Basic realm="VLC Neo test"')
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return

                stats["authenticated"] += 1
                byte_range = self.headers.get("Range")
                if byte_range:
                    stats["ranges"] += 1
                    match = re.fullmatch(r"bytes=(\d+)-(\d*)", byte_range)
                    if not match:
                        self.send_response(416)
                        self.send_header("Content-Range", f"bytes */{len(media)}")
                        self.send_header("Content-Length", "0")
                        self.end_headers()
                        return
                    start = int(match.group(1))
                    end = min(int(match.group(2)) if match.group(2) else len(media) - 1,
                              len(media) - 1)
                    if start >= len(media) or end < start:
                        self.send_response(416)
                        self.send_header("Content-Range", f"bytes */{len(media)}")
                        self.send_header("Content-Length", "0")
                        self.end_headers()
                        return
                    body = media[start:end + 1]
                    self.send_response(206)
                    self.send_header("Content-Range", f"bytes {start}-{end}/{len(media)}")
                else:
                    body = media
                    self.send_response(200)
                self.send_header("Content-Type", "video/mp4")
                self.send_header("Accept-Ranges", "bytes")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                try:
                    self.wfile.write(body)
                except (BrokenPipeError, ConnectionResetError):
                    pass

            def log_message(self, *_args: object) -> None:
                pass

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Proxy)
        server.daemon_threads = True
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        port = server.server_address[1]
        sandbox = work / "sandbox"
        env = os.environ.copy()
        env.update({
            "NEO_BUILD_DIR": str(BUILD_DIR),
            "NEO_SANDBOX": str(sandbox),
            "NEO_TIMEOUT": "18",
            "http_proxy": "",
            "https_proxy": "",
            "HTTP_PROXY": "",
            "HTTPS_PROXY": "",
            "no_proxy": "",
            "NO_PROXY": "",
        })
        steps = (
            f"100:player.setConfig('http-proxy','http://{USERNAME}@127.0.0.1:{port}'); "
            f"player.setConfig('http-proxy-pwd','{PASSWORD}'); "
            "player.openLocation('http://neo-auth-proxy.invalid/fixture.mp4', true)"
            "|+5000:'authProxyPlayback=' + (player.state === 2 && player.hasVideo && player.length > 0)"
            "|+100:quit"
        )
        try:
            command = [str(ROOT / "scripts/run-offscreen.sh"), steps]
            if shutil.which("dbus-run-session"):
                command = ["dbus-run-session", "--", *command]
            completed = subprocess.run(
                command, cwd=ROOT, env=env, text=True, stdout=subprocess.PIPE,
               stderr=subprocess.STDOUT, timeout=25)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

        output = completed.stdout
        print(output, end="" if output.endswith("\n") else "\n")
        print(f"VLC {'.'.join(map(str, version))}; proxy requests: {stats}")
        if stats["authenticated"] == 0 or stats["bad_auth"]:
            print("FAIL: VLC did not complete the 407 challenge with the configured credentials",
                  file=sys.stderr)
            return 1
        if stats["unauthenticated"] == 0:
            print("FAIL: the fixture did not observe an initial unauthenticated request",
                  file=sys.stderr)
            return 1

        played = "authProxyPlayback=true" in output
        if played:
            print("PASS: authenticated proxy playback works")
        elif "cannot seek (to offset 0)" in output:
            print("KNOWN VLC CORE LIMITATION: credentials are accepted, but HTTP 407 playback cannot seek")
        else:
            print("FAIL: VLC failed for an unexpected reason after the authenticated proxy response",
                  file=sys.stderr)
            return 1
        return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.TimeoutExpired as error:
        print(f"FAIL: VLC proxy integration timed out after {error.timeout}s", file=sys.stderr)
        raise SystemExit(1)

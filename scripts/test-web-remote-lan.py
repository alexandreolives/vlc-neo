#!/usr/bin/env python3
"""Exercise VLC's persisted Web Remote through the host's LAN address."""

from __future__ import annotations

import base64
import os
import pathlib
import re
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request


HERE = pathlib.Path(__file__).resolve().parent.parent
BUILD_DIR = pathlib.Path(os.environ.get("NEO_BUILD_DIR", HERE / "build"))
PASSWORD = "vlc-neo-lan-test"


def lan_ipv4() -> str:
    route = subprocess.run(
        ["ip", "-o", "-4", "route", "get", "1.1.1.1"],
        check=False,
        capture_output=True,
        text=True,
    )
    match = re.search(r"\bsrc\s+(\d+\.\d+\.\d+\.\d+)", route.stdout)
    if match:
        return match.group(1)
    raise RuntimeError("No IPv4 address is available on the default network route")


def request(opener: urllib.request.OpenerDirector, url: str, password: str | None) -> tuple[int, bytes]:
    headers = {}
    if password is not None:
        encoded = base64.b64encode((":" + password).encode()).decode()
        headers["Authorization"] = "Basic " + encoded
    req = urllib.request.Request(url, headers=headers)
    try:
        with opener.open(req, timeout=1.0) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def main() -> None:
    address = lan_ipv4()
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]

    with tempfile.TemporaryDirectory(prefix="vlc-neo-web-remote-") as temp:
        work = pathlib.Path(temp)
        sandbox = work / "sandbox"
        for folder in ("config", "data", "cache"):
            (sandbox / folder).mkdir(parents=True, exist_ok=True)

        env = os.environ.copy()
        env.update(
            NEO_BUILD_DIR=str(BUILD_DIR),
            NEO_SANDBOX=str(sandbox),
            NEO_TIMEOUT="15",
            QT_QPA_PLATFORM="offscreen",
            XDG_CONFIG_HOME=str(sandbox / "config"),
            XDG_DATA_HOME=str(sandbox / "data"),
            XDG_CACHE_HOME=str(sandbox / "cache"),
        )
        steps = (
            "100:player.setConfig('extraintf','http'); "
            "player.setConfig('http-host','0.0.0.0'); "
            f"player.setConfig('http-port',{port}); "
            f"player.setConfig('http-password','{PASSWORD}'); "
            "'webRemoteConfig=' + (String(player.config('extraintf')).includes('http') "
            "&& player.config('http-host') === '0.0.0.0' "
            f"&& Number(player.config('http-port')) === {port} "
            f"&& player.config('http-password') === '{PASSWORD}')|+100:quit"
        )
        configured = subprocess.run(
            [str(HERE / "scripts/run-offscreen.sh"), steps],
            cwd=HERE,
            env=env,
            capture_output=True,
            text=True,
            timeout=20,
        )
        configured_output = configured.stdout + configured.stderr
        if configured.returncode != 0 or "webRemoteConfig=true" not in configured_output:
            raise RuntimeError(
                f"Neo Web Remote setup exited with code {configured.returncode} or did not save the expected options:\n"
                + configured_output
            )

        env.pop("VLC_PLUGIN_PATH", None)
        log = (work / "vlc-http.log").open("w")
        vlc = subprocess.Popen(
            [
                "/usr/bin/vlc",
                "--no-one-instance",
                "--intf",
                "dummy",
                "--no-video",
                "--no-audio",
            ],
            cwd=HERE,
            env=env,
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        endpoint = f"http://{address}:{port}/requests/status.xml"
        unauthenticated = None
        try:
            for _ in range(100):
                if vlc.poll() is not None:
                    raise RuntimeError(
                        f"VLC exited before serving the Web Remote:\n{(work / 'vlc-http.log').read_text()}"
                    )
                try:
                    unauthenticated, _ = request(opener, endpoint, None)
                    break
                except (OSError, TimeoutError):
                    time.sleep(0.1)
            if unauthenticated is None:
                raise RuntimeError(
                    "VLC did not answer at its LAN address:\n"
                    + (work / "vlc-http.log").read_text(errors="replace")
                )
            authenticated, body = request(opener, endpoint, PASSWORD)
            if unauthenticated != 401 or authenticated != 200 or b"<root" not in body:
                raise RuntimeError(
                    f"Unexpected LAN auth results: without password HTTP {unauthenticated}, "
                    f"with password HTTP {authenticated}"
                )
            print(
                f"PASS: VLC Neo's persisted Web Remote answers at {address}:{port}; "
                "unauthenticated request is HTTP 401 and authenticated status is HTTP 200."
            )
        finally:
            vlc.terminate()
            try:
                vlc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                vlc.kill()
                vlc.wait(timeout=5)
            log.close()


if __name__ == "__main__":
    main()

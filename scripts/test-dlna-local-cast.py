#!/usr/bin/env python3
"""Exercise VLC Neo's DLNA local-file relay with a small simulated renderer.

Run after building the Neo plugin:
    NEO_BUILD_DIR=build-fidelity2 python3 scripts/test-dlna-local-cast.py

This uses real VLC Neo and IPv4 SSDP multicast on the local network, but does
not require a physical TV. It only creates a short temporary video fixture.
"""

from __future__ import annotations

import hashlib
import http.server
import os
import socket
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path


GROUP = "239.255.255.250"
SSDP_PORT = 1900
SERVICE = "urn:schemas-upnp-org:service:AVTransport:1"


def route_ipv4() -> str:
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect((GROUP, SSDP_PORT))
        address = probe.getsockname()[0]
        if not address or address.startswith("127."):
            raise RuntimeError("No non-loopback IPv4 route is available for SSDP")
        return address
    finally:
        probe.close()


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


class FakeRenderer:
    def __init__(self, interface: str):
        self.interface = interface
        self.lock = threading.Lock()
        self.actions: list[str] = []
        self.transport_uri = ""
        self.transport_state = "STOPPED"
        self.position = "00:00:00"
        self.media_status: list[tuple[int, bytes, bytes]] = []
        self.media_errors: list[str] = []
        self.stop_event = threading.Event()
        self.http = self._create_http_server()
        self.http_thread = threading.Thread(target=self.http.serve_forever, daemon=True)
        self.http_thread.start()
        self.http_port = self.http.server_address[1]
        self.location = f"http://{interface}:{self.http_port}/device.xml"
        self.dial_location = f"http://{interface}:{self.http_port}/dial.xml"
        self.ssdp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
        self.ssdp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            self.ssdp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
        except (AttributeError, OSError):
            pass
        self.ssdp.bind(("", SSDP_PORT))
        membership = socket.inet_aton(GROUP) + socket.inet_aton(interface)
        self.ssdp.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, membership)
        self.ssdp.settimeout(0.25)
        self.ssdp_thread = threading.Thread(target=self._serve_ssdp, daemon=True)
        self.ssdp_thread.start()

    def _create_http_server(self):
        owner = self

        class Handler(http.server.BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, _format, *_args):
                return

            def _send(self, status: int, body: bytes, content_type: str = "text/xml; charset=utf-8"):
                self.send_response(status)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(body)

            def do_GET(self):
                if self.path == "/dial.xml":
                    body = b'''<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <device><deviceType>urn:schemas-upnp-org:device:tvdevice:1</deviceType>
    <friendlyName>Neo Integration DIAL TV</friendlyName><UDN>uuid:neo-integration-test-dial</UDN>
    <serviceList><service>
      <serviceType>urn:dial-multiscreen-org:service:dial:1</serviceType>
      <serviceId>urn:dial-multiscreen-org:serviceId:dial</serviceId>
      <controlURL>/apps</controlURL>
    </service></serviceList>
  </device>
</root>'''
                    self._send(200, body)
                    return
                if self.path != "/device.xml":
                    self._send(404, b"", "text/plain")
                    return
                body = f'''<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <device><deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
    <friendlyName>Neo Integration Test TV</friendlyName><UDN>uuid:neo-integration-test-renderer</UDN>
    <serviceList><service>
      <serviceType>{SERVICE}</serviceType><serviceId>urn:upnp-org:serviceId:AVTransport</serviceId>
      <controlURL>/upnp/avtransport</controlURL><eventSubURL>/upnp/event</eventSubURL>
      <SCPDURL>/upnp/avtransport.xml</SCPDURL>
    </service></serviceList>
  </device>
</root>'''.encode()
                self._send(200, body)

            def do_POST(self):
                length = int(self.headers.get("Content-Length", "0"))
                payload = self.rfile.read(length)
                action_header = self.headers.get("SOAPAction", "")
                action = action_header.strip('"').rsplit("#", 1)[-1]
                try:
                    xml = ET.fromstring(payload)
                    fields = {local_name(element.tag): (element.text or "")
                              for element in xml.iter() if list(element) == []}
                except ET.ParseError as error:
                    owner.media_errors.append(f"invalid SOAP request for {action}: {error}")
                    self._send(400, b"bad SOAP", "text/plain")
                    return

                with owner.lock:
                    owner.actions.append(action)
                    if action == "SetAVTransportURI":
                        owner.transport_uri = fields.get("CurrentURI", "")
                        owner.transport_state = "STOPPED"
                    elif action == "Play":
                        owner.transport_state = "PLAYING"
                    elif action == "Pause":
                        owner.transport_state = "PAUSED_PLAYBACK"
                    elif action == "Stop":
                        owner.transport_state = "STOPPED"
                    elif action == "Seek":
                        owner.position = fields.get("Target", "00:00:00")
                    uri = owner.transport_uri
                    current_state = owner.transport_state
                    current_position = owner.position

                if action == "SetAVTransportURI" and uri:
                    threading.Thread(target=owner._fetch_media, args=(uri,), daemon=True).start()

                if action == "GetPositionInfo":
                    track_uri = f"<TrackURI>{uri}</TrackURI>"
                    body_fields = (
                        f"<TrackDuration>00:01:00</TrackDuration>"
                        f"<RelTime>{current_position}</RelTime>{track_uri}"
                    )
                elif action == "GetTransportInfo":
                    body_fields = (
                        f"<CurrentTransportState>{current_state}</CurrentTransportState>"
                        "<CurrentTransportStatus>OK</CurrentTransportStatus>"
                    )
                else:
                    body_fields = ""
                response = f'''<?xml version="1.0"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body><u:{action}Response xmlns:u="{SERVICE}">{body_fields}</u:{action}Response></s:Body>
</s:Envelope>'''.encode()
                self._send(200, response)

        return http.server.ThreadingHTTPServer((self.interface, 0), Handler)

    def _serve_ssdp(self):
        while not self.stop_event.is_set():
            try:
                packet, source = self.ssdp.recvfrom(8192)
            except socket.timeout:
                continue
            except OSError:
                return
            if b"M-SEARCH" not in packet or b"ssdp:discover" not in packet.lower():
                continue
            responses = (
                (
                "HTTP/1.1 200 OK\r\n"
                "CACHE-CONTROL: max-age=120\r\n"
                "EXT:\r\n"
                f"LOCATION: {self.location}\r\n"
                "SERVER: VLC Neo Test/1.0 UPnP/1.0\r\n"
                "ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n"
                "USN: uuid:neo-integration-test-renderer::urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n"
                ),
                (
                "HTTP/1.1 200 OK\r\n"
                "CACHE-CONTROL: max-age=120\r\n"
                "EXT:\r\n"
                f"LOCATION: {self.dial_location}\r\n"
                "SERVER: VLC Neo Test/1.0 UPnP/1.0\r\n"
                "ST: urn:dial-multiscreen-org:service:dial:1\r\n"
                "USN: uuid:neo-integration-test-dial::urn:dial-multiscreen-org:service:dial:1\r\n\r\n"
                ),
            )
            for response in responses:
                self.ssdp.sendto(response.encode(), source)

    def _fetch_media(self, uri: str):
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        try:
            with opener.open(uri, timeout=5) as response:
                status = response.status
                body = response.read()
            range_request = urllib.request.Request(uri, headers={"Range": "bytes=0-127"})
            with opener.open(range_request, timeout=5) as response:
                range_status = response.status
                range_body = response.read()
            with self.lock:
                self.media_status.append((status, body, bytes((range_status,)) + range_body))
        except Exception as error:  # captured and asserted after VLC exits
            with self.lock:
                self.media_errors.append(str(error))

    def close(self):
        self.stop_event.set()
        try:
            self.ssdp.close()
        except OSError:
            pass
        self.http.shutdown()
        self.http.server_close()


def main() -> int:
    repository = Path(__file__).resolve().parents[1]
    build_dir = Path(os.environ.get("NEO_BUILD_DIR", repository / "build")).resolve()
    plugin = build_dir / "libneo_plugin.so"
    if not plugin.is_file():
        raise SystemExit(f"VLC Neo plugin is missing: {plugin}; build it first")

    try:
        interface = route_ipv4()
    except (OSError, RuntimeError) as error:
        raise SystemExit(f"Cannot run the local SSDP integration test: {error}")

    with tempfile.TemporaryDirectory(prefix="neo-dlna-test-") as temporary:
        media = Path(temporary) / "local-cast-fixture.mp4"
        subprocess.run([
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            # Keep media alive through SSDP discovery and the cast dialog's
            # polling interval. A three-second clip can end before selection.
            "-f", "lavfi", "-i", "testsrc2=size=160x90:rate=12:duration=60",
            "-an", "-c:v", "mpeg4", "-q:v", "5", "-pix_fmt", "yuv420p", str(media),
        ], check=True)
        expected = media.read_bytes()
        expected_hash = hashlib.sha256(expected).hexdigest()
        renderer = FakeRenderer(interface)
        sandbox = Path(temporary) / "profile"
        steps = (
            f"400:onboarding.close(); player.openLocation('{media}', true)"
            "|+1400:'localMediaReady=' + (player.hasVideo && String(player.mediaUrl).includes('local-cast-fixture.mp4'))"
            "|+200:castDialog.open()"
            "|+2200:'fakeRendererVisible=' + player.rendererDevices.some(device => device.name === 'Neo Integration Test TV')"
            "|+100:'fakeDialVisible=' + player.rendererDevices.some(device => device.id === 'dial:uuid:neo-integration-test-dial' && device.protocol === 'DIAL')"
            "|+100:'dialHasNoDirectPlayback=' + (() => { const d=player.rendererDevices.find(device => device.id === 'dial:uuid:neo-integration-test-dial'); return !!d && d.available === false && !d.selected })()"
            "|+100:'fakeRendererSelected=' + (() => { const d=player.rendererDevices.find(device => device.name === 'Neo Integration Test TV'); return !!d && player.setRenderer(d.id) })()"
            "|+1400:'remoteVideoPlaying=' + (player.playing && player.hasVideo)"
            "|+100:player.seek(0.5)"
            "|+500:'remoteSeekState=' + player.seekable"
            "|+100:player.togglePause()"
            "|+500:'remotePaused=' + !player.playing"
            "|+100:player.togglePause()"
            "|+500:'remoteResumed=' + player.playing"
            "|+100:player.setRenderer('')"
            "|+300:'rendererDisconnected=' + !player.rendererDevices.some(device => device.selected)"
            "|+100:castDialog.close()"
            "|+100:castDialog.open()"
            "|+700:'dialRediscoveredAfterDialogReopen=' + player.rendererDevices.some(device => device.id === 'dial:uuid:neo-integration-test-dial')"
            "|+100:castDialog.close()"
            "|+100:quit"
        )
        environment = os.environ.copy()
        environment["NEO_BUILD_DIR"] = str(build_dir)
        environment["NEO_SANDBOX"] = str(sandbox)
        environment["NEO_TIMEOUT"] = "40"
        environment["NEO_TEST_STEPS"] = steps
        environment["VLC_PLUGIN_PATH"] = str(build_dir)
        environment["QT_QPA_PLATFORM"] = "offscreen"
        environment["QT_FORCE_STDERR_LOGGING"] = "1"
        environment["XDG_CONFIG_HOME"] = str(sandbox / "config")
        environment["XDG_DATA_HOME"] = str(sandbox / "data")
        environment["XDG_CACHE_HOME"] = str(sandbox / "cache")
        vlc = environment.get("SYSTEM_VLC", "/usr/bin/vlc")
        command = [vlc, "--no-plugins-cache", "-I", "neo", "--no-qt-privacy-ask",
                   "--aout=dummy", str(media)]
        try:
            process = subprocess.run(command, cwd=repository, env=environment,
                                     text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                     timeout=45, check=False)
            time.sleep(0.2)
        finally:
            renderer.close()

        output = process.stdout
        print(output)
        with renderer.lock:
            actions = list(renderer.actions)
            media_status = list(renderer.media_status)
            media_errors = list(renderer.media_errors)
            transport_uri = renderer.transport_uri
        failures = []
        required_output = (
            "localMediaReady=true",
            "fakeRendererVisible=true",
            "fakeDialVisible=true",
            "dialHasNoDirectPlayback=true",
            "fakeRendererSelected=true",
            "remoteVideoPlaying=true",
            "remoteSeekState=true",
            "remotePaused=true",
            "remoteResumed=true",
            "rendererDisconnected=true",
            "dialRediscoveredAfterDialogReopen=true",
        )
        failures.extend(label for label in required_output if label not in output)
        expected_action_counts = {
            "SetAVTransportURI": 1,
            "Play": 2,  # initial start plus the one explicit resume
            "Seek": 2,  # initial position plus the one explicit seek
            "Pause": 1,
            "Stop": 1,
        }
        for action, expected_count in expected_action_counts.items():
            actual_count = actions.count(action)
            if actual_count != expected_count:
                failures.append(
                    f"renderer received {action} {actual_count} times; expected {expected_count}"
                )
        if not transport_uri.startswith(f"http://{interface}:") or "127.0.0.1" in transport_uri:
            failures.append(f"TV received a non-routable media URL: {transport_uri!r}")
        if not media_status:
            failures.append("renderer did not fetch the local media and a byte range")
        else:
            status, body, range_payload = media_status[0]
            if status != 200 or hashlib.sha256(body).hexdigest() != expected_hash:
                failures.append("renderer GET did not receive the exact VLC source file")
            if not range_payload or range_payload[0] != 206 or range_payload[1:] != expected[:128]:
                failures.append("renderer Range request did not receive HTTP 206 and the requested bytes")
        failures.extend(f"renderer HTTP error: {error}" for error in media_errors)
        if process.returncode != 0:
            failures.append(f"VLC exited with status {process.returncode}")
        if failures:
            raise SystemExit("DLNA integration test failed:\n- " + "\n- ".join(failures))
        print(f"PASS local DLNA cast from VLC over {interface}: full file, seek, pause/resume, disconnect")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())

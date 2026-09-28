#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Minecraft-сеть: пинг серверов, поиск LAN-игр и сканирование подсети.
Один файл, зависимостей нет (только стандартная библиотека).

  python3 mcping.py ping <host> [port]        # Server List Ping (Java)
  python3 mcping.py bedrock <host> [port]     # RakNet ping (Bedrock, UDP 19132)
  python3 mcping.py scan <prefix> [port]      # перебор .1-.254 в подсети
  python3 mcping.py listen [seconds]          # ловить «Открыть для сети» (мультикаст)
  python3 mcping.py join <host> <port>        # просто проверить, что это Minecraft

Вывод машинно-читаемый: строки KEY=VALUE, плюс строка HUMAN для человека.
"""
import json
import socket
import struct
import sys
import threading
import time

MULTICAST = ("224.0.2.60", 4445)


# ------------------------- Java Edition (SLP) -------------------------
def _varint(n: int) -> bytes:
    out = b""
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out += bytes([b | 0x80])
        else:
            out += bytes([b])
            return out


def _read_varint(sock) -> int:
    num = 0
    shift = 0
    while True:
        raw = sock.recv(1)
        if not raw:
            raise EOFError("соединение закрыто")
        num |= (raw[0] & 0x7F) << shift
        if not raw[0] & 0x80:
            return num
        shift += 7
        if shift > 35:
            raise ValueError("varint слишком длинный")


def _motd_text(desc) -> str:
    if isinstance(desc, str):
        return desc
    if isinstance(desc, dict):
        parts = []
        if "text" in desc:
            parts.append(str(desc["text"]))
        for extra in desc.get("extra", []) or []:
            parts.append(_motd_text(extra))
        return "".join(parts)
    return str(desc)


def ping_java(host: str, port: int = 25565, timeout: float = 3.0):
    """Возвращает dict с данными сервера или None."""
    sock = socket.create_connection((host, port), timeout=timeout)
    sock.settimeout(timeout)
    try:
        host_b = host.encode("utf-8")
        payload = (
            b"\x00"
            + _varint(0xFFFFFFFF)                      # protocol -1: «любой»
            + _varint(len(host_b)) + host_b
            + port.to_bytes(2, "big")
            + b"\x01"                                   # next state: status
        )
        sock.sendall(_varint(len(payload)) + payload)
        sock.sendall(b"\x01\x00")                       # Status Request
        length = _read_varint(sock)
        data = b""
        while len(data) < length:
            chunk = sock.recv(length - len(data))
            if not chunk:
                break
            data += chunk
        txt = data.decode("utf-8", "replace")
        start = txt.find("{")
        end = txt.rfind("}")
        if start < 0 or end <= start:
            return None
        obj = json.loads(txt[start:end + 1])
    finally:
        sock.close()

    ver = obj.get("version", {}) or {}
    players = obj.get("players", {}) or {}
    sample = players.get("sample") or []
    return {
        "motd": _motd_text(obj.get("description", "")).replace("§", "").strip(),
        "version": ver.get("name", ""),
        "protocol": ver.get("protocol", ""),
        "online": players.get("online", 0),
        "max": players.get("max", 0),
        "who": ", ".join(p.get("name", "") for p in sample),
    }


# ------------------------- Bedrock (RakNet) -------------------------
def ping_bedrock(host: str, port: int = 19132, timeout: float = 3.0):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout)
    try:
        magic = b"\x00\xff\xff\x00\xfe\xfe\xfe\xfe\xfd\xfd\xfd\xfd\x12\x34\x56\x78"
        payload = b"\x01" + struct.pack(">q", int(time.time())) + magic + struct.pack(">q", 0)
        sock.sendto(payload, (host, port))
        data, _ = sock.recvfrom(4096)
    except (socket.timeout, OSError):
        return None
    finally:
        sock.close()
    if len(data) < 35:
        return None
    try:
        offset = 35
        name_len = struct.unpack(">H", data[offset + 1:offset + 3])[0]
        name = data[offset + 3:offset + 3 + name_len].decode("utf-8", "replace")
        p = offset + 3 + name_len
        p += 2 + 2 + 1 + 1 + 1 + 1 + 1  # protocol/version/players/max/id/motd/perm
        motd_len = struct.unpack(">H", data[p:p + 2])[0]
        motd = data[p + 2:p + 2 + motd_len].decode("utf-8", "replace")
    except Exception:
        name, motd = "", ""
    return {"name": name, "motd": motd, "version": "", "online": 0, "max": 0, "raw_len": len(data)}


# ------------------------- вывод -------------------------
def show(host, port, info, kind="Java"):
    if not info:
        print("OK=no")
        return 1
    print("OK=yes")
    print(f"HOST={host}")
    print(f"PORT={port}")
    print(f"KIND={kind}")
    print(f"MOTD={info.get('motd') or info.get('name')}")
    print(f"VERSION={info.get('version') or ''}")
    print(f"PLAYERS={info.get('online', 0)}/{info.get('max', 0)}")
    if info.get("who"):
        print(f"WHO={info['who']}")
    label = info.get("motd") or info.get("name") or ""
    print(f"HUMAN={host}:{port}  {kind}  {info.get('version') or ''}  "
          f"{info.get('online', 0)}/{info.get('max', 0)}  {label}")
    return 0


def cmd_ping(host, port):
    try:
        info = ping_java(host, int(port))
    except Exception:
        info = None
    return show(host, port, info, "Java")


def cmd_bedrock(host, port):
    info = ping_bedrock(host, int(port))
    return show(host, port, info, "Bedrock")


def cmd_scan(prefix, port):
    port = int(port)
    hits = []

    def probe(i):
        ip = f"{prefix}.{i}"
        try:
            s = socket.create_connection((ip, port), timeout=0.4)
            s.close()
            hits.append(ip)
        except OSError:
            pass

    threads = [threading.Thread(target=probe, args=(i,)) for i in range(1, 255)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    print(f"SCAN_DONE={prefix}.0/24 port {port} found={len(hits)}")
    for ip in sorted(hits, key=lambda x: int(x.split('.')[-1])):
        cmd_ping(ip, port)
    return 0


def cmd_listen(seconds=6):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    except (AttributeError, OSError):
        pass
    sock.bind(("", MULTICAST[1]))
    for ip in _local_ips():
        try:
            sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP,
                            socket.inet_aton(MULTICAST[0]) + socket.inet_aton(ip))
        except OSError:
            pass
    sock.settimeout(1.0)
    deadline = time.time() + float(seconds)
    seen = 0
    while time.time() < deadline:
        try:
            data, addr = sock.recvfrom(4096)
        except socket.timeout:
            continue
        txt = data.decode("utf-8", "replace")
        motd, port = "", "?"
        if "[MOTD]" in txt:
            motd = txt.split("[MOTD]")[1].split("[/MOTD]")[0]
        if "[AD]" in txt:
            port = txt.split("[AD]")[1].split("[/AD]")[0]
        seen += 1
        print(f"LAN_FOUND={addr[0]}:{port}")
        print(f"HUMAN={addr[0]}:{port}  {motd}")
    if not seen:
        print("HUMAN=Объявлений LAN не слышно (хост не открыл игру или сеть режет мультикаст)")
    print(f"LISTEN_DONE={seen}")
    return 0


def _local_ips():
    ips = []
    try:
        for res in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = res[4][0]
            if ip not in ips and not ip.startswith("127."):
                ips.append(ip)
    except OSError:
        pass
    try:
        probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        probe.connect(("8.8.8.8", 80))
        ips.append(probe.getsockname()[0])
        probe.close()
    except OSError:
        pass
    return ips


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    cmd = argv[1]
    if cmd == "ping":
        return cmd_ping(argv[2], argv[3] if len(argv) > 3 else 25565)
    if cmd == "join":
        return cmd_ping(argv[2], argv[3] if len(argv) > 3 else 25565)
    if cmd == "bedrock":
        return cmd_bedrock(argv[2], argv[3] if len(argv) > 3 else 19132)
    if cmd == "scan":
        return cmd_scan(argv[2], argv[3] if len(argv) > 3 else 25565)
    if cmd == "listen":
        return cmd_listen(argv[2] if len(argv) > 2 else 6)
    print(f"неизвестная команда: {cmd}")
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))

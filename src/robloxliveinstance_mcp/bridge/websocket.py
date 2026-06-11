from __future__ import annotations

import asyncio
import base64
import hashlib
import json
import struct
from typing import Any

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
MAX_FRAME_BYTES = 64 * 1024 * 1024


def accept_key(client_key: str) -> str:
    digest = hashlib.sha1((client_key + GUID).encode("ascii")).digest()
    return base64.b64encode(digest).decode("ascii")


async def read_frame(reader: asyncio.StreamReader) -> tuple[bool, int, bytes]:
    header = await reader.readexactly(2)
    final = bool(header[0] & 0x80)
    opcode = header[0] & 0x0F
    masked = bool(header[1] & 0x80)
    length = header[1] & 0x7F
    if length == 126:
        length = struct.unpack("!H", await reader.readexactly(2))[0]
    elif length == 127:
        length = struct.unpack("!Q", await reader.readexactly(8))[0]
    if length > MAX_FRAME_BYTES:
        raise ValueError("WebSocket frame exceeds 64 MiB")
    mask = await reader.readexactly(4) if masked else b""
    payload = await reader.readexactly(length)
    if masked:
        payload = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))
    return final, opcode, payload


async def send_frame(
    writer: asyncio.StreamWriter, payload: bytes, opcode: int = 1
) -> None:
    length = len(payload)
    header = bytearray([0x80 | opcode])
    if length < 126:
        header.append(length)
    elif length < 65536:
        header.append(126)
        header.extend(struct.pack("!H", length))
    else:
        header.append(127)
        header.extend(struct.pack("!Q", length))
    writer.write(bytes(header) + payload)
    await writer.drain()


async def send_json(writer: asyncio.StreamWriter, value: dict[str, Any]) -> None:
    await send_frame(writer, json.dumps(value, separators=(",", ":")).encode())

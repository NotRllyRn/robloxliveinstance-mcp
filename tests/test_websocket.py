import asyncio
import base64
import hashlib
import struct
import unittest

from robloxliveinstance_mcp.bridge.websocket import GUID, read_frame, send_frame


class WebSocketTests(unittest.IsolatedAsyncioTestCase):
    def test_accept_key_reference_value(self) -> None:
        from robloxliveinstance_mcp.bridge.websocket import accept_key

        key = "dGhlIHNhbXBsZSBub25jZQ=="
        expected = base64.b64encode(
            hashlib.sha1((key + GUID).encode()).digest()
        ).decode()
        self.assertEqual(accept_key(key), expected)

    async def test_reads_masked_text_frame(self) -> None:
        reader = asyncio.StreamReader()
        payload = b'{"type":"hello"}'
        mask = b"\x01\x02\x03\x04"
        encoded = bytes(byte ^ mask[i % 4] for i, byte in enumerate(payload))
        reader.feed_data(bytes([0x81, 0x80 | len(payload)]) + mask + encoded)
        reader.feed_eof()

        final, opcode, decoded = await read_frame(reader)
        self.assertTrue(final)
        self.assertEqual(opcode, 1)
        self.assertEqual(decoded, payload)

    async def test_writes_extended_length_frame(self) -> None:
        class Writer:
            def __init__(self) -> None:
                self.data = b""

            def write(self, data: bytes) -> None:
                self.data += data

            async def drain(self) -> None:
                return None

        writer = Writer()
        payload = b"x" * 130
        await send_frame(writer, payload)
        self.assertEqual(writer.data[:2], b"\x81\x7e")
        self.assertEqual(struct.unpack("!H", writer.data[2:4])[0], 130)
        self.assertEqual(writer.data[4:], payload)

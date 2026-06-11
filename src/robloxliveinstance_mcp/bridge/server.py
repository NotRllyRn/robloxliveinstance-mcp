from __future__ import annotations

import asyncio
import json
import logging
from http import HTTPStatus
from typing import Any
from urllib.parse import parse_qs, urlsplit

from ..config import Config
from ..protocol import BridgeError
from .registry import SessionRegistry
from .websocket import accept_key, read_frame, send_frame, send_json

LOG = logging.getLogger(__name__)


class BridgeServer:
    def __init__(self, config: Config, registry: SessionRegistry):
        self.config = config
        self.registry = registry
        self._server: asyncio.Server | None = None
        self._cleanup_task: asyncio.Task[None] | None = None
        self._http_queues: dict[str, asyncio.Queue[dict[str, Any]]] = {}

    async def start(self) -> None:
        self._server = await asyncio.start_server(
            self._handle_connection, self.config.host, self.config.port
        )
        self._cleanup_task = asyncio.create_task(self._cleanup_loop())

    async def close(self) -> None:
        if self._cleanup_task:
            self._cleanup_task.cancel()
        if self._server:
            self._server.close()
            await self._server.wait_closed()

    @property
    def bound_port(self) -> int | None:
        if not self._server or not self._server.sockets:
            return None
        return int(self._server.sockets[0].getsockname()[1])

    async def _cleanup_loop(self) -> None:
        while True:
            await asyncio.sleep(10)
            await self.registry.cleanup_stale()

    async def _handle_connection(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        try:
            request_line = (await reader.readline()).decode("latin-1").strip()
            if not request_line:
                return
            method, target, _ = request_line.split(" ", 2)
            headers = await self._read_headers(reader)
            parsed = urlsplit(target)
            query = parse_qs(parsed.query)

            if (
                parsed.path == "/bridge/ws"
                and headers.get("upgrade", "").lower() == "websocket"
            ):
                await self._handle_websocket(reader, writer, headers, query)
                return

            content_length = int(headers.get("content-length", "0"))
            body = await reader.readexactly(content_length) if content_length else b""
            payload = json.loads(body or b"{}")
            await self._handle_http(writer, method, parsed.path, headers, query, payload)
        except BridgeError as exc:
            status = (
                HTTPStatus.UNAUTHORIZED
                if exc.code == "unauthorized"
                else HTTPStatus.FORBIDDEN
                if exc.code in {"place_not_allowed", "user_not_allowed"}
                else HTTPStatus.BAD_REQUEST
            )
            await self._write_json(writer, status, exc.as_dict())
        except (ValueError, json.JSONDecodeError) as exc:
            await self._write_json(
                writer, HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)}
            )
        except Exception:
            LOG.exception("Bridge connection failed")
            if not writer.is_closing():
                await self._write_json(
                    writer,
                    HTTPStatus.INTERNAL_SERVER_ERROR,
                    {"ok": False, "error": "internal_error"},
                )
        finally:
            if not writer.is_closing():
                writer.close()
                await writer.wait_closed()

    async def _handle_websocket(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
        headers: dict[str, str],
        query: dict[str, list[str]],
    ) -> None:
        self._require_token(headers, query, {})
        key = headers.get("sec-websocket-key")
        if not key:
            raise ValueError("Missing Sec-WebSocket-Key")
        writer.write(
            (
                "HTTP/1.1 101 Switching Protocols\r\n"
                "Upgrade: websocket\r\n"
                "Connection: Upgrade\r\n"
                f"Sec-WebSocket-Accept: {accept_key(key)}\r\n\r\n"
            ).encode("ascii")
        )
        await writer.drain()

        session_id: str | None = None
        fragmented_opcode: int | None = None
        fragments: list[bytes] = []

        async def send(message: dict[str, Any]) -> None:
            await send_json(writer, message)

        try:
            while True:
                final, opcode, data = await read_frame(reader)
                if opcode == 8:
                    break
                if opcode == 9:
                    await send_frame(writer, data, opcode=10)
                    continue
                if opcode in (1, 2) and not final:
                    fragmented_opcode = opcode
                    fragments = [data]
                    continue
                if opcode == 0 and fragmented_opcode is not None:
                    fragments.append(data)
                    if not final:
                        continue
                    opcode = fragmented_opcode
                    data = b"".join(fragments)
                    fragmented_opcode = None
                    fragments = []
                if opcode != 1:
                    continue
                message = json.loads(data)
                message_type = message.get("type")
                if message_type == "hello":
                    metadata = self._validate_metadata(message.get("metadata", {}))
                    session = await self.registry.register(
                        metadata, "websocket", send, message.get("session_id")
                    )
                    session_id = session.session_id
                    await send(
                        {
                            "type": "hello_ack",
                            "session_id": session_id,
                            "heartbeat_seconds": 15,
                        }
                    )
                elif message_type == "response":
                    self.registry.complete(
                        str(message.get("request_id")), message.get("payload")
                    )
                elif message_type == "heartbeat" and session_id:
                    await self.registry.touch(session_id)
        except (asyncio.IncompleteReadError, ConnectionError):
            pass
        finally:
            if session_id:
                await self.registry.remove(session_id)

    async def _handle_http(
        self,
        writer: asyncio.StreamWriter,
        method: str,
        path: str,
        headers: dict[str, str],
        query: dict[str, list[str]],
        payload: dict[str, Any],
    ) -> None:
        if path == "/health" and method == "GET":
            await self._write_json(
                writer,
                HTTPStatus.OK,
                {"ok": True, "sessions": self.registry.list_public()},
            )
            return

        self._require_token(headers, query, payload)
        if path == "/bridge/hello" and method == "POST":
            queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue()

            async def send(message: dict[str, Any]) -> None:
                await queue.put(message)

            metadata = self._validate_metadata(payload.get("metadata", {}))
            session = await self.registry.register(
                metadata, "http-poll", send, payload.get("session_id")
            )
            self._http_queues[session.session_id] = queue
            await self._write_json(
                writer,
                HTTPStatus.OK,
                {"ok": True, "session_id": session.session_id},
            )
            return

        session_id = str(payload.get("session_id", ""))
        if path == "/bridge/poll" and method == "POST":
            self.registry.resolve(session_id)
            await self.registry.touch(session_id)
            queue = self._http_queues.get(session_id)
            if not queue:
                raise BridgeError("unknown_session", "HTTP session queue not found.")
            try:
                message = await asyncio.wait_for(queue.get(), timeout=20)
            except TimeoutError:
                message = {"type": "idle"}
            await self._write_json(writer, HTTPStatus.OK, message)
            return

        if path == "/bridge/respond" and method == "POST":
            await self.registry.touch(session_id)
            self.registry.complete(
                str(payload.get("request_id")), payload.get("payload")
            )
            await self._write_json(writer, HTTPStatus.OK, {"ok": True})
            return

        await self._write_json(
            writer, HTTPStatus.NOT_FOUND, {"ok": False, "error": "not_found"}
        )

    def _require_token(
        self,
        headers: dict[str, str],
        query: dict[str, list[str]],
        payload: dict[str, Any],
    ) -> None:
        authorization = headers.get("authorization", "")
        bearer = authorization[7:] if authorization.startswith("Bearer ") else ""
        supplied = bearer or (query.get("token") or [""])[0] or payload.get("token", "")
        if supplied != self.config.token:
            raise BridgeError("unauthorized", "Invalid bridge token.")

    def _validate_metadata(self, metadata: dict[str, Any]) -> dict[str, Any]:
        place_id = int(metadata.get("place_id", 0))
        if self.config.allowed_place_ids and place_id not in self.config.allowed_place_ids:
            raise BridgeError(
                "place_not_allowed",
                f"Place {place_id} is not in ROBLOX_LIVE_MCP_PLACE_IDS.",
            )
        user_id = int(metadata.get("user_id", 0))
        if self.config.allowed_user_ids and user_id not in self.config.allowed_user_ids:
            raise BridgeError(
                "user_not_allowed",
                f"User {user_id} is not in ROBLOX_LIVE_MCP_USER_IDS.",
            )
        return {str(key): value for key, value in metadata.items()}

    @staticmethod
    async def _read_headers(reader: asyncio.StreamReader) -> dict[str, str]:
        headers: dict[str, str] = {}
        while True:
            line = (await reader.readline()).decode("latin-1")
            if line in ("\r\n", "\n", ""):
                return headers
            name, value = line.split(":", 1)
            headers[name.strip().lower()] = value.strip()

    @staticmethod
    async def _write_json(
        writer: asyncio.StreamWriter, status: HTTPStatus, payload: Any
    ) -> None:
        body = json.dumps(payload, separators=(",", ":")).encode()
        writer.write(
            (
                f"HTTP/1.1 {status.value} {status.phrase}\r\n"
                "Content-Type: application/json\r\n"
                f"Content-Length: {len(body)}\r\n"
                "Connection: close\r\n\r\n"
            ).encode("ascii")
            + body
        )
        await writer.drain()

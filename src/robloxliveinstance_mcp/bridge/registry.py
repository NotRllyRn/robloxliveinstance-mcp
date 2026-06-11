from __future__ import annotations

import asyncio
import time
import uuid
from typing import Any

from ..protocol import BridgeError
from .session import SendMessage, Session


class SessionRegistry:
    def __init__(self, request_timeout: float = 30, stale_after: float = 45):
        self.request_timeout = request_timeout
        self.stale_after = stale_after
        self._sessions: dict[str, Session] = {}
        self._pending: dict[str, asyncio.Future[Any]] = {}
        self._lock = asyncio.Lock()

    async def register(
        self,
        metadata: dict[str, Any],
        transport: str,
        send_message: SendMessage,
        session_id: str | None = None,
    ) -> Session:
        session_id = session_id or str(uuid.uuid4())
        if session_id in self._sessions:
            session_id = str(uuid.uuid4())
        session = Session(session_id, metadata, transport, send_message)
        async with self._lock:
            self._sessions[session_id] = session
        return session

    async def remove(self, session_id: str) -> None:
        async with self._lock:
            self._sessions.pop(session_id, None)

    async def touch(self, session_id: str) -> None:
        session = self._sessions.get(session_id)
        if session:
            session.last_seen = time.time()

    def list_public(self) -> list[dict[str, Any]]:
        return [session.public() for session in self._sessions.values()]

    def resolve(self, session_id: str | None = None) -> Session:
        if session_id:
            session = self._sessions.get(session_id)
            if not session:
                raise BridgeError(
                    "unknown_session",
                    f'No live Roblox session has id "{session_id}".',
                    {"sessions": self.list_public()},
                )
            return session

        sessions = list(self._sessions.values())
        if not sessions:
            raise BridgeError(
                "no_live_sessions",
                "No Roblox client is connected to the local bridge.",
            )
        if len(sessions) > 1:
            raise BridgeError(
                "ambiguous_session",
                "Multiple Roblox clients are connected; pass session_id.",
                {"sessions": self.list_public()},
            )
        return sessions[0]

    async def request(
        self,
        action: str,
        params: dict[str, Any] | None = None,
        session_id: str | None = None,
    ) -> Any:
        session = self.resolve(session_id)
        request_id = str(uuid.uuid4())
        future = asyncio.get_running_loop().create_future()
        self._pending[request_id] = future
        message = {
            "type": "request",
            "request_id": request_id,
            "action": action,
            "params": params or {},
        }

        lock = session.execution_lock if action == "execute_luau" else _NullLock()
        try:
            async with lock:
                await session.send_message(message)
                return await asyncio.wait_for(
                    future, timeout=self.request_timeout
                )
        except TimeoutError as exc:
            raise BridgeError(
                "request_timeout",
                f'Roblox did not answer "{action}" within '
                f"{self.request_timeout:g} seconds.",
                {"session_id": session.session_id, "action": action},
            ) from exc
        finally:
            self._pending.pop(request_id, None)

    def complete(self, request_id: str, payload: Any) -> None:
        future = self._pending.get(request_id)
        if future and not future.done():
            future.set_result(payload)

    async def cleanup_stale(self) -> None:
        cutoff = time.time() - self.stale_after
        stale = [
            session_id
            for session_id, session in self._sessions.items()
            if session.last_seen < cutoff
        ]
        for session_id in stale:
            await self.remove(session_id)


class _NullLock:
    async def __aenter__(self) -> None:
        return None

    async def __aexit__(self, *_: object) -> None:
        return None

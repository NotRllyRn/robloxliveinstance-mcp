from __future__ import annotations

import asyncio
import time
from dataclasses import dataclass, field
from typing import Any, Awaitable, Callable

SendMessage = Callable[[dict[str, Any]], Awaitable[None]]


@dataclass(slots=True)
class Session:
    session_id: str
    metadata: dict[str, Any]
    transport: str
    send_message: SendMessage
    connected_at: float = field(default_factory=time.time)
    last_seen: float = field(default_factory=time.time)
    execution_lock: asyncio.Lock = field(default_factory=asyncio.Lock)

    def public(self) -> dict[str, Any]:
        return {
            "session_id": self.session_id,
            "transport": self.transport,
            "connected_at": self.connected_at,
            "last_seen": self.last_seen,
            **self.metadata,
        }

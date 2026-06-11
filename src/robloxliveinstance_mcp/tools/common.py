from __future__ import annotations

from typing import Any

from ..bridge import SessionRegistry
from ..protocol import BridgeError, success


async def call(
    registry: SessionRegistry,
    action: str,
    params: dict[str, Any] | None = None,
    session_id: str | None = None,
) -> dict[str, Any]:
    try:
        payload = await registry.request(action, params, session_id)
        if isinstance(payload, dict) and "ok" in payload:
            return payload
        return success(payload)
    except BridgeError as exc:
        return exc.as_dict()

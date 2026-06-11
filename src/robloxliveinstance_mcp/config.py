from __future__ import annotations

import os
import secrets
from dataclasses import dataclass


def _csv_ints(value: str) -> frozenset[int]:
    return frozenset(int(item.strip()) for item in value.split(",") if item.strip())


@dataclass(frozen=True, slots=True)
class Config:
    host: str
    port: int
    token: str
    allowed_place_ids: frozenset[int]
    allowed_user_ids: frozenset[int]
    request_timeout_seconds: float
    session_stale_seconds: float

    @classmethod
    def from_env(cls) -> "Config":
        return cls(
            host=os.getenv("ROBLOX_LIVE_MCP_HOST", "127.0.0.1"),
            port=int(os.getenv("ROBLOX_LIVE_MCP_PORT", "8766")),
            token=os.getenv("ROBLOX_LIVE_MCP_TOKEN") or secrets.token_urlsafe(24),
            allowed_place_ids=_csv_ints(os.getenv("ROBLOX_LIVE_MCP_PLACE_IDS", "")),
            allowed_user_ids=_csv_ints(os.getenv("ROBLOX_LIVE_MCP_USER_IDS", "")),
            request_timeout_seconds=float(
                os.getenv("ROBLOX_LIVE_MCP_REQUEST_TIMEOUT", "30")
            ),
            session_stale_seconds=float(
                os.getenv("ROBLOX_LIVE_MCP_SESSION_STALE", "45")
            ),
        )

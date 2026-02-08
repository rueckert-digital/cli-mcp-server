from __future__ import annotations

import os
from contextlib import asynccontextmanager

import uvicorn
from starlette.applications import Starlette
from starlette.responses import PlainTextResponse
from starlette.routing import Route

from mcp.server.streamable_http_manager import StreamableHTTPSessionManager

from .server import server


def _env_int(name: str, default: int) -> int:
    value = os.getenv(name, str(default))
    try:
        return int(value)
    except ValueError as exc:
        raise ValueError(f"{name} must be an integer, got {value!r}") from exc


def _env_str(name: str, default: str) -> str:
    return os.getenv(name, default)


def create_app(streamable_path: str = "/mcp") -> Starlette:
    session_manager = StreamableHTTPSessionManager(
        server,
        json_response=True,  # Streamable HTTP JSON responses (no SSE framing).
        stateless=False,
    )

    class StreamableHTTPEndpoint:
        def __init__(self, manager: StreamableHTTPSessionManager):
            self._manager = manager

        async def __call__(self, scope, receive, send) -> None:
            await self._manager.handle_request(scope, receive, send)

    async def healthcheck(_: object) -> PlainTextResponse:
        return PlainTextResponse("ok")

    @asynccontextmanager
    async def lifespan(_: Starlette):
        async with session_manager.run():
            yield

    routes = [
        Route(
            streamable_path,
            StreamableHTTPEndpoint(session_manager),
            methods=["POST", "GET", "DELETE"],
        ),
        Route("/healthz", healthcheck, methods=["GET"]),
    ]
    return Starlette(routes=routes, lifespan=lifespan)


def main() -> None:
    host = _env_str("MCP_HTTP_HOST", "127.0.0.1")
    port = _env_int("MCP_HTTP_PORT", 8084)
    path = _env_str("MCP_HTTP_PATH", "/mcp")
    app = create_app(path)
    uvicorn.run(app, host=host, port=port, log_level="info")


__all__ = ["create_app", "main"]


if __name__ == "__main__":
    main()

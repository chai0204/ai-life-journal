"""Ollama embedding client."""

from __future__ import annotations

import httpx

from .config import OLLAMA_MODEL, OLLAMA_URL


class OllamaConnectionError(Exception):
    """Raised when Ollama is unreachable."""

    def __init__(self, url: str, cause: Exception | None = None) -> None:
        self.url = url
        self.cause = cause
        super().__init__(f"Cannot connect to Ollama at {url}")


class Embedder:
    """Client for generating embeddings via Ollama API."""

    def __init__(
        self,
        url: str | None = None,
        model: str | None = None,
    ) -> None:
        self.url = url or OLLAMA_URL
        self.model = model or OLLAMA_MODEL
        self._sync_client: httpx.Client | None = None
        self._async_client: httpx.AsyncClient | None = None

    @property
    def sync_client(self) -> httpx.Client:
        if self._sync_client is None:
            self._sync_client = httpx.Client(timeout=120.0)
        return self._sync_client

    @property
    def async_client(self) -> httpx.AsyncClient:
        if self._async_client is None:
            self._async_client = httpx.AsyncClient(timeout=120.0)
        return self._async_client

    def embed(self, text: str) -> list[float]:
        """Generate embedding for a single text (synchronous)."""
        try:
            resp = self.sync_client.post(
                f"{self.url}/api/embed",
                json={"model": self.model, "input": text},
            )
            resp.raise_for_status()
        except (httpx.ConnectError, httpx.ConnectTimeout) as e:
            raise OllamaConnectionError(self.url, e) from e
        data = resp.json()
        return data["embeddings"][0]

    async def aembed(self, text: str) -> list[float]:
        """Generate embedding for a single text (async)."""
        try:
            resp = await self.async_client.post(
                f"{self.url}/api/embed",
                json={"model": self.model, "input": text},
            )
            resp.raise_for_status()
        except (httpx.ConnectError, httpx.ConnectTimeout) as e:
            raise OllamaConnectionError(self.url, e) from e
        data = resp.json()
        return data["embeddings"][0]

    def embed_batch(self, texts: list[str]) -> list[list[float]]:
        """Generate embeddings for multiple texts (synchronous).

        Uses the Ollama batch API which accepts multiple inputs.
        """
        try:
            resp = self.sync_client.post(
                f"{self.url}/api/embed",
                json={"model": self.model, "input": texts},
            )
            resp.raise_for_status()
        except (httpx.ConnectError, httpx.ConnectTimeout) as e:
            raise OllamaConnectionError(self.url, e) from e
        data = resp.json()
        return data["embeddings"]

    def close(self) -> None:
        if self._sync_client is not None:
            self._sync_client.close()
            self._sync_client = None
        if self._async_client is not None:
            # Can't await in sync close, but httpx handles it
            pass

"""Tests for embedder module (mocked HTTP)."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from life_rag_mcp.embedder import Embedder


FAKE_EMBEDDING = [0.1] * 1024


@pytest.fixture
def embedder():
    return Embedder(url="http://localhost:11434", model="bge-m3")


def _mock_response(embeddings: list[list[float]]) -> MagicMock:
    mock = MagicMock()
    mock.raise_for_status = MagicMock()
    mock.json.return_value = {"embeddings": embeddings}
    return mock


def test_embed_single(embedder: Embedder):
    with patch.object(embedder, "_sync_client", create=True) as mock_client:
        mock_client.post.return_value = _mock_response([FAKE_EMBEDDING])
        embedder._sync_client = mock_client

        result = embedder.embed("test text")
        assert len(result) == 1024
        mock_client.post.assert_called_once()
        call_args = mock_client.post.call_args
        assert call_args[1]["json"]["input"] == "test text"
        assert call_args[1]["json"]["model"] == "bge-m3"


def test_embed_batch(embedder: Embedder):
    with patch.object(embedder, "_sync_client", create=True) as mock_client:
        mock_client.post.return_value = _mock_response([FAKE_EMBEDDING, FAKE_EMBEDDING])
        embedder._sync_client = mock_client

        result = embedder.embed_batch(["text1", "text2"])
        assert len(result) == 2
        assert len(result[0]) == 1024
        call_args = mock_client.post.call_args
        assert call_args[1]["json"]["input"] == ["text1", "text2"]


@pytest.mark.asyncio
async def test_aembed(embedder: Embedder):
    mock_client = MagicMock()
    mock_resp = _mock_response([FAKE_EMBEDDING])

    async def mock_post(*args, **kwargs):
        return mock_resp

    mock_client.post = mock_post
    embedder._async_client = mock_client

    result = await embedder.aembed("async test")
    assert len(result) == 1024

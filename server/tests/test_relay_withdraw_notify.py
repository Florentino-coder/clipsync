"""PC withdraw_notify fans out to all subscribed phones (typed, not clip)."""

from __future__ import annotations

import asyncio

import pytest

import relay_server
from relay_server import create_app


@pytest.fixture
async def client(aiohttp_client):
    return await aiohttp_client(create_app())


@pytest.fixture(autouse=True)
def reset_relay_globals():
    relay_server.pcs.clear()
    relay_server.phones.clear()
    relay_server.connections.clear()
    yield
    relay_server.pcs.clear()
    relay_server.phones.clear()
    relay_server.connections.clear()


ORDER = {
    "order_id": "W-1001",
    "amount": "100.00",
    "account": "4774090171",
    "bank": "KBANK",
    "account_name": "สมชาย ใจดี",
    "ts": 1720000000,
}


async def test_withdraw_notify_fanout_to_all_phones(client):
    async with client.ws_connect("/") as pc_ws:
        await pc_ws.send_json({"action": "register", "id": "123456789"})
        await pc_ws.receive_json()

        async with client.ws_connect("/") as phone_a:
            await phone_a.send_json({"action": "subscribe", "target": "123456789"})
            await phone_a.receive_json()
            await pc_ws.receive_json()  # phone_joined

            async with client.ws_connect("/") as phone_b:
                await phone_b.send_json({"action": "subscribe", "target": "123456789"})
                await phone_b.receive_json()
                await pc_ws.receive_json()

                await pc_ws.send_json({"action": "withdraw_notify", **ORDER})

                for phone in (phone_a, phone_b):
                    msg = await phone.receive_json()
                    assert msg["type"] == "withdraw_notify"
                    assert msg["order_id"] == "W-1001"
                    assert msg["amount"] == "100.00"
                    assert msg["account"] == "4774090171"
                    assert msg["bank"] == "KBANK"
                    assert msg["account_name"] == "สมชาย ใจดี"
                    assert msg["ts"] == 1720000000


async def test_withdraw_notify_requires_registered_pc(client):
    async with client.ws_connect("/") as phone_ws:
        await phone_ws.send_json({"action": "subscribe", "target": "123456789"})
        await phone_ws.receive_json()

        async with client.ws_connect("/") as rogue:
            await rogue.send_json({"action": "withdraw_notify", **ORDER})
            with pytest.raises(asyncio.TimeoutError):
                await asyncio.wait_for(phone_ws.receive_json(), timeout=0.2)


async def test_withdraw_notify_rejects_missing_order_id(client):
    async with client.ws_connect("/") as pc_ws:
        await pc_ws.send_json({"action": "register", "id": "123456789"})
        await pc_ws.receive_json()

        async with client.ws_connect("/") as phone_ws:
            await phone_ws.send_json({"action": "subscribe", "target": "123456789"})
            await phone_ws.receive_json()
            await pc_ws.receive_json()

            bad = {**ORDER, "order_id": ""}
            await pc_ws.send_json({"action": "withdraw_notify", **bad})
            with pytest.raises(asyncio.TimeoutError):
                await asyncio.wait_for(phone_ws.receive_json(), timeout=0.2)


async def test_withdraw_notify_does_not_use_clip_type(client):
    """Guard: withdraw must never arrive as type=clip."""
    async with client.ws_connect("/") as pc_ws:
        await pc_ws.send_json({"action": "register", "id": "123456789"})
        await pc_ws.receive_json()
        async with client.ws_connect("/") as phone_ws:
            await phone_ws.send_json({"action": "subscribe", "target": "123456789"})
            await phone_ws.receive_json()
            await pc_ws.receive_json()
            await pc_ws.send_json({"action": "withdraw_notify", **ORDER})
            msg = await phone_ws.receive_json()
            assert msg.get("type") != "clip"
            assert "text" not in msg or msg["type"] == "withdraw_notify"

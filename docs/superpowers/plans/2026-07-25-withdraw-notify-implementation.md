# Withdraw Notify Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Phase A complete (typed `withdraw_notify` → all online phones → local notify + copy amount/full account + inbox + bank logos), then wire Phase B `slip_status` with Safety S1–S3 (hide copy after slip, remove on success, loud fail / no silent re-queue).

**Architecture:** Jinbao scrape → Chrome extension `pending_orders` → PC `_normalize_order` (keep full `account` + `account_name` + `order_id`) → PC emits typed relay action → relay fans out to every subscribed phone for that PC → Flutter queue + `flutter_local_notifications` + in-app inbox. After slip: PC orchestrator stage changes → typed `slip_status` → phone updates slip notify **and** withdraw-queue copy/safety state. Do **not** stuff JSON into `clip`. No FCM, no bubble.

**Tech Stack:** aiohttp relay (`server/relay_server.py`), PC Python (`pc/clipsync/orchestrator.py`, `legacy.py` ClipSyncClient), Chrome extension (`engine.js` scrape), Flutter + `flutter_local_notifications` + existing FGS WebSocket (`mobile/lib/clip_service.dart`), pytest / flutter_test.

**Spec:** [`docs/superpowers/specs/2026-07-25-withdraw-notify-design.md`](../specs/2026-07-25-withdraw-notify-design.md)  
**High-level plan (context only):** [`2026-07-25-withdraw-notify.md`](./2026-07-25-withdraw-notify.md)  
**Worktree root:** `.worktrees/feat-slip-auto-confirm` (paths below are relative to that root)

**Ship order (locked):** finish Tasks 1–8 (Phase A) and ship before Tasks 9–13 (B + S1–S3).

**Versions:** bump touched surfaces in the same change — mobile `pubspec.yaml` + `kAppVersion` (must match), PC `APP_VERSION` + `ClipSyncPC.iss` + `release/version.json`, extension `manifest.json` + `release/version.json` when scrape changes, relay only if you introduce a versioned surface (today relay has none).

---

## File map

| Path | Responsibility |
|---|---|
| `server/relay_server.py` | Fan-out PC→phones for `withdraw_notify` and `slip_status` (mirror `clip` / `slip_ack` pattern) |
| `server/tests/test_relay_withdraw_notify.py` | Relay A1 tests |
| `server/tests/test_relay_slip_status.py` | Relay B1 tests |
| `pc/clipsync/orchestrator.py` | Extend `_normalize_order`; pending-order diff emit hook; emit `slip_status` on pipeline stages |
| `pc/clipsync/withdraw_notify.py` | Pure helpers: format amount, build withdraw payload, detect new order ids vs previous snapshot |
| `pc/clipsync/legacy.py` | `ClipSyncClient.send_withdraw_notify` / `send_slip_status` (JSON over existing PC WS) |
| `pc/clipsync/bootstrap.py` | Wire emit callbacks from pending_orders + orchestrator decisions → client send |
| `pc/tests/test_withdraw_notify.py` | Normalize + diff + payload unit tests |
| `pc/tests/test_orchestrator.py` | Extend for normalize fields + slip_status emit hooks |
| `pc/chrome-extension/engine.js` | Ensure DOM scrape keeps full `account` + optional `name`/`account_name` |
| `pc/chrome-extension/tests/engine.test.js` | Scrape field assertions |
| `pc/chrome-extension/manifest.json` | Bump when extension scrape changes |
| `mobile/lib/withdraw/withdraw_order.dart` | Immutable order model + parse from relay JSON |
| `mobile/lib/withdraw/withdraw_queue.dart` | Queue, active = newest pending, copy gating, safety states |
| `mobile/lib/withdraw/bank_logos.dart` | `bank` code → asset path + generic fallback |
| `mobile/lib/withdraw/withdraw_notify_service.dart` | Channel setup, detail+summary notify, actions, throttle |
| `mobile/lib/withdraw/slip_status_service.dart` | Phase B channel + in-place status notify |
| `mobile/lib/withdraw/withdraw_inbox_page.dart` | Inbox UI (newest first, per-row copy, set active) |
| `mobile/lib/clip_service.dart` | Handle `withdraw_notify` / `slip_status` in FGS WS listener; forward to main |
| `mobile/lib/home_screen.dart` | Open inbox entry; toast after copy; apply queue updates from FGS |
| `mobile/assets/banks/*.webp` (or png) | In-app bank logos (~100–400 KB total) |
| `mobile/pubspec.yaml` | Dep + assets + version bump |
| `mobile/test/withdraw_queue_test.dart` | Queue / active / safety unit tests |
| `mobile/test/withdraw_order_test.dart` | Payload parse tests |
| `mobile/test/bank_logos_test.dart` | Logo map fallback tests |
| `release/version.json` | android / pc / extension notes when shipping |
| `pc/clipsync/legacy.py` `APP_VERSION` + `pc/installer/ClipSyncPC.iss` | PC version string |

---

### Task 1: A1 — Relay `withdraw_notify` protocol

**Files:**
- Modify: `server/relay_server.py` (after `clip` handler ~266–297)
- Create: `server/tests/test_relay_withdraw_notify.py`

- [ ] **Step 1: Write the failing test**

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `server/`):

```bash
python -m pytest tests/test_relay_withdraw_notify.py -v
```

Expected: FAIL — `withdraw_notify` not handled / phones get no message (timeout) or assertion fails.

- [ ] **Step 3: Write minimal implementation**

In `server/relay_server.py`, after the `clip` handler block, add:

```python
            # PC → phones: pending withdraw notify (typed; do not use clip).
            elif action == "withdraw_notify":
                if not peer_id:
                    continue

                order_id = msg.get("order_id")
                if not order_id or not isinstance(order_id, str) or not order_id.strip():
                    continue

                amount = msg.get("amount", "")
                account = msg.get("account", "")
                bank = msg.get("bank", "")
                account_name = msg.get("account_name", msg.get("name", ""))
                ts = msg.get("ts", 0)
                try:
                    ts_i = int(ts)
                except (TypeError, ValueError):
                    ts_i = 0

                payload = json.dumps(
                    {
                        "type": "withdraw_notify",
                        "order_id": order_id.strip(),
                        "amount": str(amount) if amount is not None else "",
                        "account": str(account) if account is not None else "",
                        "bank": str(bank) if bank is not None else "",
                        "account_name": str(account_name) if account_name is not None else "",
                        "ts": ts_i,
                    },
                    ensure_ascii=False,
                )

                dead: set[Ws] = set()
                for ph in list(phones.get(peer_id, set())):
                    try:
                        await ph.send_str(payload)
                    except Exception:
                        dead.add(ph)
                phones[peer_id] -= dead
                log.info(
                    "WDRAW %s -> %s phone(s) order=%s",
                    fmt(peer_id),
                    len(phones.get(peer_id, set())),
                    order_id.strip()[:40],
                )
```

- [ ] **Step 4: Run test to verify it passes**

```bash
python -m pytest tests/test_relay_withdraw_notify.py -v
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add server/relay_server.py server/tests/test_relay_withdraw_notify.py
git commit -m "feat(relay): fan out withdraw_notify to all online phones"
```

---

### Task 2: A2 — PC normalize keeps full account + name

**Files:**
- Modify: `pc/clipsync/orchestrator.py` (`_normalize_order` ~61–89)
- Create: `pc/tests/test_withdraw_notify.py` (normalize section)

Today `_normalize_order` drops full digits to `account_last4` only. Matcher still needs `account_last4`; Phase A also needs `account` + `account_name`.

- [ ] **Step 1: Write the failing test**

```python
"""PC withdraw normalize + emit helpers."""

from __future__ import annotations

from clipsync.orchestrator import _normalize_order


def test_normalize_order_keeps_full_account_and_name():
    raw = {
        "order_id": "W-9",
        "amount": "1,464.00",
        "account": "4774090171",
        "bank": "KBANK",
        "name": "สมชาย ใจดี",
    }
    out = _normalize_order(raw)
    assert out["order_id"] == "W-9"
    assert out["account"] == "4774090171"
    assert out["account_last4"] == "0171"
    assert out["account_name"] == "สมชาย ใจดี"
    assert out["bank"] == "KBANK"
    assert out["amount"] == "1,464.00" or out["amount"] == "1464.00"


def test_normalize_order_account_name_aliases():
    out = _normalize_order(
        {
            "ref": "REF-22",
            "amount": 100,
            "member_bank_account": "1234567890",
            "account_name": "Alice",
            "bank_name_th": "กสิกร",
        }
    )
    assert out["account"] == "1234567890"
    assert out["account_last4"] == "7890"
    assert out["account_name"] == "Alice"
    assert out["bank"]


def test_normalize_order_empty_name_ok_when_missing():
    out = _normalize_order(
        {"order_id": "OID1", "amount": 50, "account": "9999888877", "bank": "SCB"}
    )
    assert out["account_name"] == ""
    assert out["account"] == "9999888877"
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd pc
python -m pytest tests/test_withdraw_notify.py::test_normalize_order_keeps_full_account_and_name -v
```

Expected: FAIL — KeyError `account` or missing `account_name`.

- [ ] **Step 3: Write minimal implementation**

Replace `_normalize_order` return payload (keep existing order_id / last4 / bank logic) so it also sets:

```python
def _normalize_order(order: Mapping[str, Any]) -> dict[str, Any]:
    order_id = order.get("order_id")
    if order_id is None:
        order_id = order.get("orderId")
    if order_id is None or str(order_id).strip() == "":
        order_id = order.get("ref")
    order_id_s = str(order_id).strip() if order_id is not None else ""
    if not is_reliable_order_id(order_id_s):
        order_id_s = ""

    acct_raw = order.get("member_bank_account") or order.get("account") or ""
    acct_digits = "".join(ch for ch in str(acct_raw) if ch.isdigit())

    last4 = order.get("account_last4")
    if last4 is None:
        last4 = order.get("accountLast4")
    if last4 is None:
        last4 = acct_digits[-4:] if len(acct_digits) >= 4 else ""
    else:
        digits = "".join(ch for ch in str(last4) if ch.isdigit())
        last4 = digits[-4:] if digits else ""

    # Prefer full digits from scrape; never invent digits beyond what scrape gave.
    account_full = acct_digits
    if not account_full and last4:
        account_full = str(last4)  # last-4 only — copy-account will be weak; do not pad

    bank = order.get("bank")
    if bank is None:
        bank = order.get("bank_name") or order.get("bank_name_th") or order.get("member_bank")

    name = order.get("account_name")
    if name is None:
        name = order.get("name") or order.get("username") or order.get("member_name") or ""

    amount = order.get("amount")

    return {
        "order_id": order_id_s,
        "amount": amount,
        "account": account_full,
        "account_last4": str(last4) if last4 else "",
        "account_name": str(name).strip() if name is not None else "",
        "bank": str(bank).strip() if bank is not None and str(bank).strip() else "",
    }
```

Ensure existing matcher tests still pass (they use `account_last4`).

- [ ] **Step 4: Run tests**

```bash
cd pc
python -m pytest tests/test_withdraw_notify.py tests/test_orchestrator.py tests/test_matcher.py -v
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add pc/clipsync/orchestrator.py pc/tests/test_withdraw_notify.py
git commit -m "feat(pc): keep full account and name in pending order normalize"
```

---

### Task 3: A2 — PC emit `withdraw_notify` on new pending orders

**Files:**
- Create: `pc/clipsync/withdraw_notify.py`
- Modify: `pc/clipsync/orchestrator.py` (`on_pending_orders`)
- Modify: `pc/clipsync/legacy.py` (`ClipSyncClient`)
- Modify: `pc/clipsync/bootstrap.py`
- Modify: `pc/tests/test_withdraw_notify.py`

- [ ] **Step 1: Write failing tests for pure helpers + emit**

Append to `pc/tests/test_withdraw_notify.py`:

```python
import time
from unittest.mock import MagicMock

from clipsync.withdraw_notify import (
    build_withdraw_notify_payload,
    format_amount_display,
    new_orders_since,
)


def test_format_amount_display():
    assert format_amount_display("100.00") == "100.00"
    assert format_amount_display(100) == "100.00"
    assert format_amount_display("1,464.50") == "1464.50"


def test_new_orders_since_returns_only_unseen_ids():
    prev = [{"order_id": "A", "amount": 1, "account": "1", "bank": "KBANK", "account_name": ""}]
    curr = [
        {"order_id": "A", "amount": 1, "account": "1", "bank": "KBANK", "account_name": ""},
        {"order_id": "B", "amount": 2, "account": "22", "bank": "SCB", "account_name": "Bob"},
    ]
    added = new_orders_since(prev, curr)
    assert [o["order_id"] for o in added] == ["B"]


def test_build_withdraw_notify_payload_fields():
    order = {
        "order_id": "W-1",
        "amount": 100,
        "account": "4774090171",
        "bank": "KBANK",
        "account_name": "A",
    }
    payload = build_withdraw_notify_payload(order, ts=1720000000)
    assert payload == {
        "action": "withdraw_notify",
        "order_id": "W-1",
        "amount": "100.00",
        "account": "4774090171",
        "bank": "KBANK",
        "account_name": "A",
        "ts": 1720000000,
    }


def test_on_pending_orders_emits_only_new(monkeypatch):
    from clipsync.orchestrator import SlipOrchestrator

    sent: list[dict] = []

    def fake_emit(payload: dict) -> None:
        sent.append(payload)

    orch = SlipOrchestrator(
        {
            "auto_confirm": {"enabled": True, "min_ocr_confidence": 0.9,
                             "require_manual_review": {"enabled": False, "amount_threshold": 99999}},
            "matching": {"require_account_last4_match": True, "prevent_duplicate_ref_number": True},
        },
        chrome_bridge=MagicMock(),
        shared_secret="x" * 32,
        send_withdraw_notify=fake_emit,
    )
    orch.on_pending_orders(
        {"orders": [{"order_id": "A", "amount": 10, "account": "1111222233", "bank": "KBANK"}]}
    )
    orch.on_pending_orders(
        {
            "orders": [
                {"order_id": "A", "amount": 10, "account": "1111222233", "bank": "KBANK"},
                {"order_id": "B", "amount": 20, "account": "4444555566", "bank": "SCB", "name": "B"},
            ]
        }
    )
    assert len(sent) == 2  # first snapshot all new + second only B
    assert sent[0]["order_id"] == "A"
    assert sent[1]["order_id"] == "B"
    assert sent[1]["account"] == "4444555566"
```

- [ ] **Step 2: Run to verify fail**

```bash
cd pc
python -m pytest tests/test_withdraw_notify.py -v
```

Expected: FAIL — `withdraw_notify` module / `send_withdraw_notify` missing.

- [ ] **Step 3: Minimal implementation**

`pc/clipsync/withdraw_notify.py`:

```python
from __future__ import annotations

import time
from typing import Any, Mapping, Sequence


def format_amount_display(amount: Any) -> str:
    if amount is None:
        return ""
    text = str(amount).strip().replace(",", "")
    try:
        return f"{float(text):.2f}"
    except (TypeError, ValueError):
        return str(amount).strip()


def new_orders_since(
    previous: Sequence[Mapping[str, Any]],
    current: Sequence[Mapping[str, Any]],
) -> list[dict[str, Any]]:
    prev_ids = {str(o.get("order_id") or "").strip() for o in previous}
    prev_ids.discard("")
    out: list[dict[str, Any]] = []
    for o in current:
        oid = str(o.get("order_id") or "").strip()
        if not oid or oid in prev_ids:
            continue
        out.append(dict(o))
    return out


def build_withdraw_notify_payload(
    order: Mapping[str, Any], *, ts: int | None = None
) -> dict[str, Any]:
    return {
        "action": "withdraw_notify",
        "order_id": str(order.get("order_id") or "").strip(),
        "amount": format_amount_display(order.get("amount")),
        "account": str(order.get("account") or "").strip(),
        "bank": str(order.get("bank") or "").strip(),
        "account_name": str(order.get("account_name") or order.get("name") or "").strip(),
        "ts": int(ts if ts is not None else time.time()),
    }
```

Wire `SlipOrchestrator.__init__` with optional `send_withdraw_notify: Callable[[dict], None] | None = None`. In `on_pending_orders`, after building `normalized`, compute `new_orders_since(self._pending_orders, normalized)`, assign `self._pending_orders = normalized`, then for each new order call `build_withdraw_notify_payload` + `send_withdraw_notify` (never raise — wrap in try/except like today).

`ClipSyncClient.send_withdraw_notify(self, payload: dict)` — `await self.ws.send(json.dumps(payload))` (thread-safe via `run_coroutine_threadsafe` if called from bridge thread; bootstrap should schedule on client loop the same way slip ack does).

Bootstrap: pass a callback that calls `app.client.send_withdraw_notify` / schedule send.

Skip emit when `order_id` empty or `account` empty (log once) — copy-account is unsafe without digits.

- [ ] **Step 4: Run tests**

```bash
cd pc
python -m pytest tests/test_withdraw_notify.py tests/test_orchestrator.py -v
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add pc/clipsync/withdraw_notify.py pc/clipsync/orchestrator.py pc/clipsync/legacy.py pc/clipsync/bootstrap.py pc/tests/test_withdraw_notify.py
git commit -m "feat(pc): emit withdraw_notify for newly scraped pending orders"
```

---

### Task 4: A2 — Extension scrape preserves full account + name

**Files:**
- Modify: `pc/chrome-extension/engine.js` (`scrapePendingOrders` ~277–284)
- Modify: `pc/chrome-extension/tests/engine.test.js`
- Modify: `pc/chrome-extension/manifest.json` (bump patch, e.g. `1.0.37` → `1.0.38`)

DOM scrape already emits `account` (full digits when found). Add `name` / `account_name` when a name-looking cell exists; keep API path `name` field.

- [ ] **Step 1: Write failing test**

In `engine.test.js`, add a case that builds a fake table row with amount + long account + Thai name and asserts:

```javascript
  it('scrapePendingOrders keeps full account digits and name when present', () => {
    document.body.innerHTML = `
      <table><tbody>
        <tr><td>WD-7788</td><td>กสิกร</td><td>สมชาย ใจดี</td><td>4774090171</td><td>100.00</td>
            <td><button>ยืนยัน</button></td></tr>
      </tbody></table>`;
    const profile = {
      profile_id: 'jinbao356_v1',
      selectors: { order_row: 'table tbody tr' },
    };
    const orders = global.ClipSyncEngine.scrapePendingOrders(profile);
    expect(orders.length).toBeGreaterThanOrEqual(1);
    const hit = orders.find((o) => String(o.account || '').includes('4774090171'));
    expect(hit).toBeTruthy();
    expect(hit.account).toBe('4774090171');
    expect(hit.account_last4).toBe('0171');
    // name may be empty if heuristic misses — prefer non-empty when "สมชาย" in row
    if (hit.name || hit.account_name) {
      expect(String(hit.name || hit.account_name)).toContain('สมชาย');
    }
  });
```

If current scrape cannot extract name without fragile heuristics, implement a conservative heuristic: longest Thai/letter token cell that is not amount/bank/account; else `name: ''`. Do **not** invent account digits.

- [ ] **Step 2: Run fail**

```bash
cd pc/chrome-extension
npm test -- --grep "keeps full account"
```

(or project’s existing node test command for `tests/engine.test.js`)

Expected: FAIL or weak name — then implement.

- [ ] **Step 3: Minimal scrape tweak**

In `orders.push({...})` add:

```javascript
        name: name || undefined,
        account_name: name || undefined,
```

Where `name` is derived from a non-digit cell (≥3 letters) that is not a known bank alias.

- [ ] **Step 4: Run tests + bump manifest**

```bash
npm test
```

Bump `manifest.json` `version` to next patch.

- [ ] **Step 5: Commit**

```bash
git add pc/chrome-extension/engine.js pc/chrome-extension/tests/engine.test.js pc/chrome-extension/manifest.json
git commit -m "feat(ext): preserve full account and name on pending scrape"
```

---

### Task 5: A3 — Mobile withdraw model + queue (pure Dart TDD)

**Files:**
- Create: `mobile/lib/withdraw/withdraw_order.dart`
- Create: `mobile/lib/withdraw/withdraw_queue.dart`
- Create: `mobile/test/withdraw_order_test.dart`
- Create: `mobile/test/withdraw_queue_test.dart`

- [ ] **Step 1: Write failing tests**

`mobile/test/withdraw_order_test.dart`:

```dart
import 'package:clipsync_app/withdraw/withdraw_order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromRelayJson parses withdraw_notify fields', () {
    final o = WithdrawOrder.fromRelayJson({
      'type': 'withdraw_notify',
      'order_id': 'W-1',
      'amount': '100.00',
      'account': '4774090171',
      'bank': 'KBANK',
      'account_name': 'สมชาย',
      'ts': 1720000000,
    });
    expect(o.orderId, 'W-1');
    expect(o.amount, '100.00');
    expect(o.account, '4774090171');
    expect(o.bank, 'KBANK');
    expect(o.accountName, 'สมชาย');
    expect(o.ts, 1720000000);
  });

  test('fromRelayJson rejects empty order_id', () {
    expect(
      () => WithdrawOrder.fromRelayJson({'order_id': '', 'amount': '1', 'account': '1'}),
      throwsA(isA<FormatException>()),
    );
  });
}
```

`mobile/test/withdraw_queue_test.dart`:

```dart
import 'package:clipsync_app/withdraw/withdraw_order.dart';
import 'package:clipsync_app/withdraw/withdraw_queue.dart';
import 'package:flutter_test/flutter_test.dart';

WithdrawOrder order(String id, {int ts = 1, String amount = '10.00'}) =>
    WithdrawOrder(
      orderId: id,
      amount: amount,
      account: '4774090171',
      bank: 'KBANK',
      accountName: '',
      ts: ts,
    );

void main() {
  test('active is newest pending by ts', () {
    final q = WithdrawQueue();
    q.upsert(order('A', ts: 1));
    q.upsert(order('B', ts: 2));
    expect(q.active?.orderId, 'B');
  });

  test('dedupe same order_id updates in place', () {
    final q = WithdrawQueue();
    q.upsert(order('A', ts: 1, amount: '10.00'));
    q.upsert(order('A', ts: 2, amount: '11.00'));
    expect(q.pending.length, 1);
    expect(q.active?.amount, '11.00');
  });

  test('copy targets active amount and account', () {
    final q = WithdrawQueue();
    q.upsert(order('A', ts: 1));
    q.upsert(order('B', ts: 2, amount: '99.00'));
    expect(q.copyAmountText(), '99.00');
    expect(q.copyAccountText(), '4774090171');
  });

  test('setActive changes copy target', () {
    final q = WithdrawQueue();
    q.upsert(order('A', ts: 1, amount: '10.00'));
    q.upsert(order('B', ts: 2, amount: '20.00'));
    q.setActive('A');
    expect(q.copyAmountText(), '10.00');
  });

  test('markProcessing hides copy for that order_id', () {
    final q = WithdrawQueue();
    q.upsert(order('A', ts: 1));
    q.markProcessing('A');
    expect(q.canCopy('A'), isFalse);
    expect(q.copyAmountText(), isNull);
  });

  test('markDone removes from queue', () {
    final q = WithdrawQueue();
    q.upsert(order('A', ts: 1));
    q.markDone('A');
    expect(q.pending, isEmpty);
  });

  test('markFailed keeps fail state and does not requeue as pending', () {
    final q = WithdrawQueue();
    q.upsert(order('A', ts: 1));
    q.markFailed('A', reason: 'timeout');
    expect(q.stateOf('A'), WithdrawItemState.failed);
    q.upsert(order('A', ts: 3)); // silent re-notify must not unlock copy
    expect(q.canCopy('A'), isFalse);
    expect(q.stateOf('A'), WithdrawItemState.failed);
  });
}
```

- [ ] **Step 2: Run fail**

```bash
cd mobile
flutter test test/withdraw_order_test.dart test/withdraw_queue_test.dart
```

Expected: FAIL — library not found.

- [ ] **Step 3: Minimal implementation**

`withdraw_order.dart` — immutable class with `fromRelayJson`.  
`withdraw_queue.dart` — list + map by `order_id`; states: `pending`, `processing`, `done`(removed), `failed`; `active` = explicit override or newest `pending` by `ts`; `canCopy` only for `pending` active.

- [ ] **Step 4: Run pass**

```bash
flutter test test/withdraw_order_test.dart test/withdraw_queue_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/withdraw/withdraw_order.dart mobile/lib/withdraw/withdraw_queue.dart mobile/test/withdraw_order_test.dart mobile/test/withdraw_queue_test.dart
git commit -m "feat(mobile): withdraw order model and queue with copy safety states"
```

---

### Task 6: A3 — Wire FGS WebSocket `withdraw_notify` → queue + main isolate

**Files:**
- Modify: `mobile/lib/clip_service.dart` (`ClipTaskHandler` switch ~150–199)
- Modify: `mobile/lib/home_screen.dart` (`_onData`)
- Create: `mobile/test/withdraw_ws_parse_test.dart` (optional pure parse already covered — prefer integration-style unit on a small helper)

Extract a tiny pure function so FGS stays thin:

```dart
// mobile/lib/withdraw/withdraw_ws.dart
bool handleWithdrawNotifyMessage(Map<String, dynamic> msg, WithdrawQueue queue) {
  if ((msg['type'] as String?) != 'withdraw_notify') return false;
  queue.upsert(WithdrawOrder.fromRelayJson(msg));
  return true;
}
```

- [ ] **Step 1: Failing test for helper**

```dart
import 'package:clipsync_app/withdraw/withdraw_queue.dart';
import 'package:clipsync_app/withdraw/withdraw_ws.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('handleWithdrawNotifyMessage upserts into queue', () {
    final q = WithdrawQueue();
    final ok = handleWithdrawNotifyMessage({
      'type': 'withdraw_notify',
      'order_id': 'W-1',
      'amount': '100.00',
      'account': '4774090171',
      'bank': 'KBANK',
      'account_name': '',
      'ts': 1,
    }, q);
    expect(ok, isTrue);
    expect(q.active?.orderId, 'W-1');
  });

  test('ignores clip messages', () {
    final q = WithdrawQueue();
    expect(handleWithdrawNotifyMessage({'type': 'clip', 'text': 'hi'}, q), isFalse);
    expect(q.pending, isEmpty);
  });
}
```

- [ ] **Step 2: Run fail → implement helper → pass**

- [ ] **Step 3: Wire `ClipTaskHandler`**

Hold a process-wide `WithdrawQueue` singleton (or recreate + persist later; v1 in-memory is OK while FGS alive). On `withdraw_notify`:

```dart
case 'withdraw_notify':
  handleWithdrawNotifyMessage(msg, WithdrawQueueStore.instance);
  FlutterForegroundTask.sendDataToMain({
    'type': 'withdraw_notify',
    ...msg,
  });
  // notification update happens in Task 7
  break;
```

In `home_screen.dart` `_onData`, on `withdraw_notify` upsert local mirror queue + `setState` if inbox open.

Do **not** write withdraw JSON into clipboard as `clip`.

- [ ] **Step 4: Run**

```bash
flutter test test/withdraw_ws_parse_test.dart test/withdraw_queue_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/withdraw/withdraw_ws.dart mobile/lib/clip_service.dart mobile/lib/home_screen.dart mobile/test/withdraw_ws_parse_test.dart
git commit -m "feat(mobile): handle withdraw_notify on foreground WebSocket"
```

---

### Task 7: A4 — Local notifications + copy actions + bank logos

**Files:**
- Modify: `mobile/pubspec.yaml` (add `flutter_local_notifications`, assets, bump version)
- Modify: `mobile/lib/clip_service.dart` `kAppVersion` (match pubspec)
- Create: `mobile/lib/withdraw/bank_logos.dart`
- Create: `mobile/lib/withdraw/withdraw_notify_service.dart`
- Create: `mobile/assets/banks/` (webp/png for KBANK, SCB, BBL, KTB, GSB, TTB, BAY + `generic`)
- Create: `mobile/test/bank_logos_test.dart`
- Modify: `mobile/android/app/src/main/AndroidManifest.xml` only if extra receiver/permissions needed by plugin docs
- Modify: `release/version.json` android notes when bumping

Channel: `withdraw_alerts`, `IMPORTANCE_HIGH`, separate from FGS `clipsync` LOW.

Notification ids: detail = stable `41001`; summary group = `41000` when `pending.length > 1`.

Actions: `copy_amount`, `copy_account` → write `Clipboard` + toast via main isolate / `FlutterForegroundTask.sendDataToMain`.

Heads-up throttle: full heads-up if queue was empty or last heads-up > 4s ago; else silent in-place update (`importance` / flag per plugin API).

- [ ] **Step 1: Bank logo failing test**

```dart
import 'package:clipsync_app/withdraw/bank_logos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps known bank codes to asset paths', () {
    expect(bankLogoAsset('KBANK'), contains('kbank'));
    expect(bankLogoAsset('scb'), contains('scb'));
  });

  test('unknown bank uses generic', () {
    expect(bankLogoAsset('NOPE'), contains('generic'));
    expect(bankLogoAsset(''), contains('generic'));
  });
}
```

- [ ] **Step 2: Implement map + placeholder assets (tiny PNG OK)**

```dart
String bankLogoAsset(String bank) {
  final key = bank.trim().toUpperCase();
  const map = {
    'KBANK': 'assets/banks/kbank.webp',
    'SCB': 'assets/banks/scb.webp',
    'BBL': 'assets/banks/bbl.webp',
    'KTB': 'assets/banks/ktb.webp',
    'GSB': 'assets/banks/gsb.webp',
    'TTB': 'assets/banks/ttb.webp',
    'BAY': 'assets/banks/bay.webp',
  };
  return map[key] ?? 'assets/banks/generic.webp';
}
```

Register under `flutter: assets:` in pubspec.

- [ ] **Step 3: `WithdrawNotifyService`**

- `init()` create channel `withdraw_alerts`
- `syncFromQueue(WithdrawQueue q, {required bool allowHeadsUp})` builds Thai title `รายการถอนใหม่` / body with amount, account, bank·name; attach logo via `largeIcon`/`BigPicture` if supported, else title-only + inbox logos
- Action callbacks call into a `CopyHandler` interface injectable for tests

Unit-test throttle helper without Android:

```dart
bool shouldHeadsUp({required bool wasEmpty, required DateTime? lastHeadsUp, required DateTime now}) {
  if (wasEmpty) return true;
  if (lastHeadsUp == null) return true;
  return now.difference(lastHeadsUp) >= const Duration(seconds: 4);
}
```

- [ ] **Step 4: Bump mobile version** (example from current `0.9.5+26` → `0.9.6+27`) in **both** `pubspec.yaml` and `kAppVersion`; update `release/version.json` android section notes: "Phase A withdraw notify + copy + logos".

- [ ] **Step 5: Run tests**

```bash
cd mobile
flutter test test/bank_logos_test.dart test/withdraw_queue_test.dart
flutter pub get
```

Manual smoke later: grant `POST_NOTIFICATIONS` on Android 13+.

- [ ] **Step 6: Commit**

```bash
git add mobile/pubspec.yaml mobile/lib/clip_service.dart mobile/lib/withdraw mobile/assets/banks release/version.json
git commit -m "feat(mobile): withdraw local notifications, copy actions, bank logos"
```

---

### Task 8: A5 — Inbox UI + Phase A ship gate

**Files:**
- Create: `mobile/lib/withdraw/withdraw_inbox_page.dart`
- Modify: `mobile/lib/home_screen.dart` (entry button / badge count)
- Modify: `mobile/lib/withdraw/withdraw_notify_service.dart` (tap notification → open inbox / set active)

Inbox requirements (spec §4.4 — **required before first ship**):

- List pending newest-first
- Show bank logo, amount, account, name, state
- Per-row: copy amount, copy account (disabled if not `canCopy`)
- Tap row → `setActive` + refresh notification
- Empty state Thai copy: `ไม่มีรายการถอนรอโอน`

- [ ] **Step 1: Widget test (smoke)**

```dart
import 'package:clipsync_app/withdraw/withdraw_inbox_page.dart';
import 'package:clipsync_app/withdraw/withdraw_order.dart';
import 'package:clipsync_app/withdraw/withdraw_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('inbox lists pending order', (tester) async {
    final q = WithdrawQueue();
    q.upsert(WithdrawOrder(
      orderId: 'W-1',
      amount: '100.00',
      account: '4774090171',
      bank: 'KBANK',
      accountName: 'สมชาย',
      ts: 1,
    ));
    await tester.pumpWidget(MaterialApp(home: WithdrawInboxPage(queue: q)));
    expect(find.textContaining('100.00'), findsWidgets);
    expect(find.textContaining('4774090171'), findsWidgets);
  });
}
```

- [ ] **Step 2: Implement page + navigate from home**

- [ ] **Step 3: Phase A acceptance checklist (manual, document in commit body)**

1. PC emit → two phones both notify  
2. Copy amount / full account match active  
3. Burst 10 orders / min → summary + throttle, no clip spam  
4. Inbox shows all; logos; unknown → generic  
5. No bubble / no FCM code paths added  

- [ ] **Step 4: Commit**

```bash
git add mobile/lib/withdraw/withdraw_inbox_page.dart mobile/lib/home_screen.dart mobile/test/withdraw_inbox_test.dart
git commit -m "feat(mobile): withdraw inbox UI for Phase A ship gate"
```

**STOP — Phase A ship here.** Do not start Task 9 until Phase A APK/PC/ext are accepted.

---

### Task 9: B1 — Relay `slip_status` protocol

**Files:**
- Modify: `server/relay_server.py`
- Create: `server/tests/test_relay_slip_status.py`

Mirror Task 1 with payload:

```json
{
  "action": "slip_status",
  "job_id": "evt-1",
  "order_id": "W-1",
  "amount": "1464.00",
  "stage": "processing",
  "message_th": "กำลังดำเนินการ — อย่าโอนซ้ำ",
  "reason": "",
  "ts": 0
}
```

Forward as `type: "slip_status"` to all phones. Require registered PC. Validate `stage` ∈ `received|processing|done|failed`. Require `job_id` or `order_id`.

- [ ] **Step 1: Failing tests** (fanout + invalid stage silent + not clip)

- [ ] **Step 2: Implement handler next to `withdraw_notify`**

- [ ] **Step 3: `pytest tests/test_relay_slip_status.py -v` PASS**

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(relay): fan out slip_status to all online phones"
```

---

### Task 10: B2 — PC emit `slip_status` from orchestrator stages

**Files:**
- Modify: `pc/clipsync/orchestrator.py` (`handle_slip_event` transitions)
- Modify: `pc/clipsync/legacy.py` (`send_slip_status`)
- Modify: `pc/clipsync/bootstrap.py`
- Modify: `pc/tests/test_orchestrator.py`

Stage map (spec §7 / high-level §11.3):

| When | `stage` | `message_th` |
|---|---|---|
| Slip accepted into match path (after dedupe/sig OK, before/at match) | `received` | `โอนเงินสำเร็จ` |
| Match found / confirm pushed / awaiting extension | `processing` | `กำลังดำเนินการ — อย่าโอนซ้ำ` |
| `auto_confirmed` | `done` | `ปิดงานเรียบร้อย` |
| `confirm_failed` / timeout / match miss terminal | `failed` | `ไม่สำเร็จ: {reason}` |

Coalesce: do not emit duplicate identical `stage` for same `job_id` within a short window; mid hops collapse to `processing`.

- [ ] **Step 1: Failing test**

```python
@pytest.mark.asyncio
async def test_orchestrator_emits_slip_status_stages(tmp_path):
    statuses: list[dict] = []
    bridge = MagicMock()
    bridge.push_confirm_order = AsyncMock(return_value=None)

    orch = SlipOrchestrator(
        CFG,
        chrome_bridge=bridge,
        shared_secret=SECRET,
        audit_path=tmp_path / "a.jsonl",
        seen_events_path=tmp_path / "seen.json",
        used_refs_path=tmp_path / "used.json",
        send_slip_status=lambda p: statuses.append(p),
    )
    orch.on_pending_orders(
        {"orders": [{"order_id": "1234", "amount": 350.0, "account": "11116789", "bank": "KBANK"}]}
    )

    # Drive happy path: mock confirm waiter completion — reuse existing auto_confirm test setup
    # Assert statuses stages include received/processing/done and order_id == matched id
    ...
```

Fill `...` by adapting the existing successful `auto_confirmed` test in `test_orchestrator.py` (same EVENT/ORDERS fixtures). Assert at least one `processing` and final `done`.

- [ ] **Step 2: Implement emit helper**

```python
def build_slip_status_payload(*, job_id, order_id, amount, stage, message_th, reason="", ts=None):
    return {
        "action": "slip_status",
        "job_id": job_id,
        "order_id": order_id or "",
        "amount": format_amount_display(amount),
        "stage": stage,
        "message_th": message_th,
        "reason": reason or "",
        "ts": int(ts if ts is not None else time.time()),
    }
```

Call from `handle_slip_event` at the mapped points; never include slip image bytes.

- [ ] **Step 3: Tests pass + bump PC version** (`APP_VERSION`, `ClipSyncPC.iss`, `release/version.json` pc notes)

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(pc): emit slip_status on slip pipeline stage changes"
```

---

### Task 11: B3 — Mobile slip status notifications

**Files:**
- Create: `mobile/lib/withdraw/slip_status_service.dart`
- Modify: `mobile/lib/clip_service.dart` / `withdraw_ws.dart`
- Create: `mobile/test/slip_status_test.dart`

Channel: `slip_status` (DEFAULT; HIGH on `done`/`failed`). Notification id = hash(`job_id` or `order_id`) — update in-place. Heads-up on `received` and terminal only.

- [ ] **Step 1: Failing unit test for stage → Thai message + coalesce**

```dart
test('coalesce keeps single status per job', () {
  final s = SlipStatusTracker();
  s.apply(jobId: 'j1', stage: 'received', messageTh: 'โอนเงินสำเร็จ');
  s.apply(jobId: 'j1', stage: 'processing', messageTh: 'กำลังดำเนินการ — อย่าโอนซ้ำ');
  expect(s.current('j1')?.stage, 'processing');
  expect(s.notificationCount, 1);
});
```

- [ ] **Step 2: Implement + wire WS `type == slip_status`**

- [ ] **Step 3: Commit**

```bash
git commit -m "feat(mobile): slip_status notification channel with in-place updates"
```

---

### Task 12: S1–S3 — Safety wire withdraw queue ↔ slip_status

**Files:**
- Modify: `mobile/lib/withdraw/withdraw_queue.dart` / `withdraw_ws.dart`
- Modify: `mobile/lib/withdraw/withdraw_notify_service.dart` (hide actions when `!canCopy(active)`)
- Modify: `mobile/test/withdraw_queue_test.dart`

Rules (spec §6):

| Event | Queue | Notify |
|---|---|---|
| `received` / `processing` for `order_id` X | `markProcessing(X)` — hide copy | Withdraw detail shows `อย่าโอนซ้ำ` / no copy actions for X |
| `done` for X | `markDone(X)` remove | Dismiss withdraw notify for X; slip shows `ปิดงานเรียบร้อย` |
| `failed` for X | `markFailed(X, reason)` — **not** pending | Loud red slip notify; withdraw must **not** become copyable if same `order_id` re-scraped |

- [ ] **Step 1: Extend failing tests** (already sketched in Task 5 — ensure WS path applies them)

```dart
test('slip_status processing hides copy', () {
  final q = WithdrawQueue();
  q.upsert(order('X', ts: 1));
  handleSlipStatusMessage({
    'type': 'slip_status',
    'job_id': 'j',
    'order_id': 'X',
    'stage': 'processing',
    'message_th': 'กำลังดำเนินการ — อย่าโอนซ้ำ',
    'ts': 2,
  }, q);
  expect(q.canCopy('X'), isFalse);
});

test('slip_status done removes order', () {
  final q = WithdrawQueue();
  q.upsert(order('X', ts: 1));
  handleSlipStatusMessage({
    'type': 'slip_status',
    'job_id': 'j',
    'order_id': 'X',
    'stage': 'done',
    'message_th': 'ปิดงานเรียบร้อย',
    'ts': 3,
  }, q);
  expect(q.pending.where((o) => o.orderId == 'X'), isEmpty);
});

test('failed then withdraw_notify does not unlock copy', () {
  final q = WithdrawQueue();
  q.upsert(order('X', ts: 1));
  handleSlipStatusMessage({
    'type': 'slip_status',
    'job_id': 'j',
    'order_id': 'X',
    'stage': 'failed',
    'message_th': 'ไม่สำเร็จ: timeout',
    'reason': 'timeout',
    'ts': 3,
  }, q);
  handleWithdrawNotifyMessage({
    'type': 'withdraw_notify',
    'order_id': 'X',
    'amount': '10.00',
    'account': '4774090171',
    'bank': 'KBANK',
    'account_name': '',
    'ts': 4,
  }, q);
  expect(q.canCopy('X'), isFalse);
  expect(q.stateOf('X'), WithdrawItemState.failed);
});
```

- [ ] **Step 2: Implement handlers + refresh notifications after state change**

- [ ] **Step 3: Run full mobile withdraw tests**

```bash
flutter test test/withdraw_queue_test.dart test/withdraw_order_test.dart test/bank_logos_test.dart test/slip_status_test.dart
```

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(mobile): wire S1-S3 safety hide-copy remove-on-done loud-fail"
```

---

### Task 13: B+S ship — versions + acceptance

**Files:**
- `mobile/pubspec.yaml` + `mobile/lib/clip_service.dart` `kAppVersion` (bump again if Task 7 already shipped A)
- `pc/clipsync/legacy.py` `APP_VERSION`, `pc/installer/ClipSyncPC.iss`
- `pc/chrome-extension/manifest.json` if needed
- `release/version.json` (android + pc + extension notes)

- [ ] **Step 1: Bump all touched surfaces; notes mention Phase B + S1–S3**

- [ ] **Step 2: Run regression suites**

```bash
cd server && python -m pytest tests/test_relay_withdraw_notify.py tests/test_relay_slip_status.py tests/test_relay.py tests/test_relay_slip.py -v
cd ../pc && python -m pytest tests/test_withdraw_notify.py tests/test_orchestrator.py tests/test_matcher.py -v
cd ../mobile && flutter test test/withdraw_queue_test.dart test/withdraw_order_test.dart test/bank_logos_test.dart test/slip_status_test.dart test/withdraw_inbox_test.dart
```

- [ ] **Step 3: Manual acceptance (spec §12)**

1. Stages Thai; one status notify per job  
2. After processing → copy hidden + อย่าโอนซ้ำ  
3. done → removed from inbox/withdraw notify  
4. failed → red + reason; not silent new withdraw  
5. No FCM / no bubble  

- [ ] **Step 4: Commit**

```bash
git commit -m "chore: bump versions for withdraw-notify Phase B and safety ship"
```

---

## Spec coverage self-check

| Spec requirement | Task(s) |
|---|---|
| Typed `withdraw_notify` to all online phones | 1, 3 |
| PC keep full account + name + order_id | 2, 4 |
| Mobile local notify + copy amount/account | 7 |
| Inbox required before Phase A ship | 8 |
| Bank logos in-app, generic fallback | 7, 8 |
| High-throughput summary + throttle | 7 |
| Active = newest pending | 5 |
| No clip-channel abuse / no FCM / no bubble | 1, 6, 9 (guards) |
| Phase A before B | Stop after Task 8 |
| `slip_status` stages Thai | 9–11 |
| S1 remove on success | 12 |
| S2 hide copy after slip | 12 |
| S3 loud fail / no silent re-queue | 5, 12 |
| Version bumps | 7, 10, 13 |

## Out of scope (do not implement in this plan)

- Bubble / FCM Phase C / S4 ack-before-unlock / S5 already-approved scrape suppress  
- Auto-paste into bank apps / iOS  
- Chrome Setup install track  
- Pixel-perfect OEM RemoteViews  

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-25-withdraw-notify-implementation.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks (`superpowers:subagent-driven-development`)
2. **Inline Execution** — same session with `superpowers:executing-plans`, batch with checkpoints

Which approach?

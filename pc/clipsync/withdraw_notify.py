"""Pure helpers for pending-order withdraw_notify payloads."""

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

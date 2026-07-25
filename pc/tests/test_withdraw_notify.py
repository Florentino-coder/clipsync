"""PC withdraw normalize + emit helpers."""

from __future__ import annotations

from clipsync.orchestrator import _normalize_order


def test_normalize_order_keeps_full_account_and_name():
    # order_id must be >=4 chars (is_reliable_order_id); plan's "W-9" is rejected.
    raw = {
        "order_id": "W-99",
        "amount": "1,464.00",
        "account": "4774090171",
        "bank": "KBANK",
        "name": "สมชาย ใจดี",
    }
    out = _normalize_order(raw)
    assert out["order_id"] == "W-99"
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

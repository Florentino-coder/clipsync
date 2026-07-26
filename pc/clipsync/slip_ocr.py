"""Fallback PC-side OCR to recover the payer ("จาก"/sender) account.

PRIMARY path is the mobile app (``mobile/lib/slip/parsers``) which now extracts
``sender_account_last4`` and sends it in ``slip_event``. This module is only a
dormant fallback for older APKs that predate that change: if the slip payload
lacks the payer account we try to read it from the slip thumbnail. It requires
Tesseract to be installed; when it is absent it returns ``None`` (never guesses).

Design goals:
- Pure, fully-testable text parser (``parse_sender_last4_from_text``) that has no
  OCR dependency.
- ``extract_sender_account_last4`` wraps Tesseract but degrades gracefully:
  if Pillow/pytesseract/tesseract are missing it returns ``None`` (caller then
  falls back to the fail-safe "missing_select_value" path — never a wrong pick).
"""

from __future__ import annotations

import io
import os
import re
import shutil
from typing import Any, Mapping, Optional

# Markers that introduce the payer line ("จาก" = from).
_FROM_MARKERS = ("จาก", "From", "FROM", "from")
# Markers that end the payer block (receiver / amount) — stop before these so we
# never grab the member (ไปยัง) account or the amount by mistake.
_STOP_MARKERS = (
    "ไปยัง",
    "ไปที่",
    "เข้าบัญชี",
    "ผู้รับ",
    "จำนวน",
    "จำนวนเงิน",
    "Amount",
    "amount",
    "To",
    "TO",
)

# Masking glyphs banks use for account numbers (x, X, *, bullet, times sign).
_MASK = r"xX\*\u2022\u00d7\u25cf\u2716"
# An account-ish token: starts with a digit or mask glyph, then digits/mask/sep.
_ACCOUNT_TOKEN = re.compile(rf"[0-9{_MASK}][0-9{_MASK}\-\s]{{4,}}")


def _last4_from_token(token: str) -> Optional[str]:
    digits = re.sub(r"\D", "", token)
    if len(digits) >= 4:
        return digits[-4:]
    return None


def _ref_number_from_text(text: str) -> str:
    alpha = re.search(r"[\dOolI]{9,}[A-Za-z0-9]{6,}", text)
    if alpha:
        return alpha.group(0)
    digits = re.search(r"[0-9OolI]{15,25}", text)
    return digits.group(0) if digits else ""


def _from_bound_last4_from_masked(masked: Optional[str]) -> Optional[str]:
    if not masked:
        return None
    s = str(masked)
    if re.search(rf"[{_MASK}]", s):
        return _last4_from_token(s)
    return None


def _sender_last4_is_ref_only(
    last4: str,
    ref_number: str,
    from_bound_last4: Optional[str],
) -> bool:
    if not last4 or not ref_number:
        return False
    if from_bound_last4 and last4 == from_bound_last4:
        return False
    return last4 in ref_number


def parse_sender_last4_from_text(text: Optional[str]) -> Optional[str]:
    """Return the payer account's last 4 digits from raw slip OCR text.

    Looks only inside the "จาก" (from) block and ignores the amount and the
    receiver account. Returns ``None`` when it cannot find a confident match.
    """
    if not text:
        return None
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    if not lines:
        return None

    ref_number = _ref_number_from_text(text)

    start = None
    for i, ln in enumerate(lines):
        if "จำนวน" in ln:
            continue
        if any(m in ln for m in _FROM_MARKERS):
            start = i
            break
    if start is None:
        return None

    # Scan the "จาก" line plus a few following lines (name is usually on the
    # first line, the account on the next) until a stop marker appears.
    for offset, ln in enumerate(lines[start : start + 5]):
        if offset > 0 and any(m in ln for m in _STOP_MARKERS):
            break
        for tok in _ACCOUNT_TOKEN.findall(ln):
            if "." in tok or "," in tok:
                # Looks like an amount (1,067.00) — skip.
                continue
            last4 = _last4_from_token(tok)
            if not last4:
                continue
            # Ref tokens can contain mask-like "X" and digit runs — never treat
            # unmasked digit runs that also appear in the ref as shop accounts.
            if ref_number and last4 in ref_number and not re.search(
                rf"[{_MASK}]", tok
            ):
                continue
            return last4
    return None


def _resolve_tesseract_cmd() -> Optional[str]:
    """Locate the tesseract binary via env var, PATH, or common install dirs."""
    env = os.environ.get("CLIPSYNC_TESSERACT_CMD") or os.environ.get("TESSERACT_CMD")
    if env and os.path.exists(env):
        return env
    found = shutil.which("tesseract")
    if found:
        return found
    for cand in (
        r"C:\Program Files\Tesseract-OCR\tesseract.exe",
        r"C:\Program Files (x86)\Tesseract-OCR\tesseract.exe",
        "/usr/bin/tesseract",
        "/opt/homebrew/bin/tesseract",
        "/usr/local/bin/tesseract",
    ):
        if os.path.exists(cand):
            return cand
    return None


def ocr_image_text(image_bytes: bytes) -> Optional[str]:
    """Run Tesseract on slip image bytes; return raw text or ``None`` on failure."""
    if not image_bytes:
        return None
    try:
        from PIL import Image, ImageOps  # type: ignore
        import pytesseract  # type: ignore
    except Exception:
        return None

    cmd = _resolve_tesseract_cmd()
    if not cmd:
        return None
    try:
        pytesseract.pytesseract.tesseract_cmd = cmd
    except Exception:
        pass

    try:
        img = Image.open(io.BytesIO(image_bytes))
        img = ImageOps.exif_transpose(img)
        img = img.convert("L")
        # Upscale small thumbnails so masked digits are legible.
        w, h = img.size
        longest = max(w, h)
        if longest and longest < 1600:
            scale = 1600.0 / longest
            img = img.resize((max(1, int(w * scale)), max(1, int(h * scale))))
        img = ImageOps.autocontrast(img)
    except Exception:
        return None

    for lang in ("tha+eng", "eng", None):
        try:
            if lang:
                text = pytesseract.image_to_string(img, lang=lang)
            else:
                text = pytesseract.image_to_string(img)
            if text and text.strip():
                return text
        except Exception:
            continue
    return None


def extract_sender_account_last4(image_bytes: bytes) -> Optional[str]:
    """Best-effort: OCR the slip image and return the payer account last 4 digits.

    Returns ``None`` if OCR is unavailable or the payer account can't be read.
    Callers must treat ``None`` as "unknown" and fail safe (never guess).
    """
    text = ocr_image_text(image_bytes)
    if not text:
        return None
    return parse_sender_last4_from_text(text)


def resolve_sender_account_last4(
    event: Mapping[str, Any],
    *,
    thumbnail_jpeg_b64: Optional[str] = None,
) -> Optional[str]:
    """Resolve payer (จาก) last4 for confirm — same path as manual ยืนยันเอง.

    Order: explicit last4 → masked trailing digits → optional thumbnail OCR.
    """
    ref_number = str(event.get("ref_number") or event.get("refNumber") or "")

    masked = event.get("sender_account_masked") or event.get("senderAccountMasked")
    from_bound_last4 = _from_bound_last4_from_masked(masked)
    masked_last4 = from_bound_last4

    last4 = str(event.get("sender_account_last4") or "").strip()
    if not last4 and event.get("senderAccountLast4"):
        last4 = str(event.get("senderAccountLast4")).strip()
    digits = "".join(ch for ch in last4 if ch.isdigit())
    if len(digits) >= 4:
        resolved = digits[-4:]
        if not _sender_last4_is_ref_only(resolved, ref_number, from_bound_last4):
            return resolved

    if masked_last4:
        if not _sender_last4_is_ref_only(masked_last4, ref_number, from_bound_last4):
            return masked_last4

    thumb = thumbnail_jpeg_b64
    if not thumb:
        raw_thumb = event.get("thumbnail_jpeg_b64")
        thumb = raw_thumb if isinstance(raw_thumb, str) else None
    if isinstance(thumb, str) and thumb:
        try:
            from clipsync.slip_image import decode_thumbnail_jpeg

            raw_img = decode_thumbnail_jpeg(thumb)
            if raw_img:
                ocr_last4 = extract_sender_account_last4(raw_img)
                if ocr_last4 and not _sender_last4_is_ref_only(
                    ocr_last4, ref_number, from_bound_last4
                ):
                    return ocr_last4
        except Exception:
            return None
    return None

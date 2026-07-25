# ClipSync — Withdraw Notify Design Spec

**Status:** Approved design (2026-07-25) — **plan / design only; no feature code in this change**  
**Reference plan:** [`docs/superpowers/plans/2026-07-25-withdraw-notify.md`](../plans/2026-07-25-withdraw-notify.md)  
**Mockups (Phase A):** `artifacts/withdraw-notify-mockups/withdraw-notify-heads-up.png`, `…/withdraw-notify-expanded.png`  
**Related (separate track):** Chrome Setup install — [`2026-07-25-chrome-ext-setup-install.md`](../plans/2026-07-25-chrome-ext-setup-install.md) (does not block this feature)

---

## 1. Goal

1. **Phase A** — Staff see new withdraw orders on phone immediately, with **copy amount** and **copy full account digits**, plus an in-app inbox (high throughput ~10+/min without drowning notifications).
2. **Phase B** — After transfer, phone shows slip-pipeline status in Thai (success → processing → done / fail) over the existing always-on WebSocket — **no FCM v1**, **no bubble**.
3. **Safety (S)** — Reduce double-transfer risk: after slip, hide copy + show “อย่าโอนซ้ำ”; on confirm success remove from queue; on fail show loud red and **never** silent re-queue as a new withdraw.

---

## 2. Approved approach

| Option | Verdict |
|---|---|
| Typed relay action `withdraw_notify` (and later `slip_status`) | **Chosen** |
| Stuff JSON into existing `clip` messages | Rejected — collides with clipboard sync; weak multi-order queue / two copy buttons |
| Phone HTTP-polls PC | Rejected — latency, battery, fights existing FGS+WS design |

**Transport:** PC → relay typed WebSocket message → all online phones paired to that PC.  
**Local UI:** Flutter local notifications (`flutter_local_notifications` or equivalent) + in-app inbox. Foreground service + WebSocket already exist; reuse them.

---

## 3. Architecture

```
Jinbao (back office)
  → Chrome extension: pending_orders (existing scrape)
  → ClipSync PC: normalize order — MUST keep full account digits + account name + order_id
  → Relay: action = withdraw_notify
  → All online phones paired to that PC
  → Each phone: local queue + local notification (+ inbox UI)

After staff transfers (unchanged slip path):
  Phone slip → PC match / confirm → (Phase B) slip_status via relay
  → Update queue / notifications (Safety S1–S3)
```

### Recipients

- **All online phones** currently paired to the PC session that emitted the order.
- Offline / disconnected phones do not receive live events in v1 (best-effort while FGS+WS are up). No FCM wake in v1.

### PC normalize (required change when implementing)

Today PC roughly keeps `order_id`, `amount`, `account_last4`, `bank`.  
**Must extend** so Phase A payloads include:

| Field | Required for ship | Notes |
|---|---|---|
| `order_id` | Yes | Primary identity / dedupe |
| `amount` | Yes | Display + copy (e.g. `100.00`) |
| `account` | Yes | **Full digits**, e.g. `4774090171` — not last-4 only |
| `bank` | Yes | Code / name for display + logo map |
| `account_name` / `name` | Yes when scrape has it | Empty string allowed if scrape lacks name |
| `ts` / `received_at` | Yes | Queue ordering |

If scrape still only has last-4, do not invent full digits; Prefer fixing scrape/extension fields so full account is available before relying on copy-account in production.

---

## 4. Phase A — UX (approved)

### 4.1 One notification

Heads-up and expanded shade are **one Android notification**, not two features:

- Heads-up = high-importance peek while screen on  
- Expanded = same notification in the shade with detail + action buttons  

Actions: **คัดลอกยอด** · **คัดลอกบัญชี** (full digits).

Layout target: title + amount / account / bank·name + bank logo + two actions. Near-mockup is enough; not pixel-perfect on every OEM.

### 4.2 Active order = latest

- **Active** = newest order that is still pending transfer (not matched / not dismissed / not removed by safety).
- Notification copy buttons **always** target the active order.
- New arrival → active moves to the newest item.

### 4.3 High-throughput (~10+/min)

1. **Detail notification** — shows active order + two copy actions (stable id / group child).  
2. **Summary / group** when queue length > 1 — e.g. `รายการถอนรอโอน · 7 รายการ`.  
3. **Heads-up throttle** — full heads-up on empty→first or after clear→new; within a short window (about 3–5s) update in-place + bump summary count instead of peaking every order.  
4. **Inbox in app** — full pending list (newest first); tap row sets active and refreshes notification; per-row copy; clear on PC matched/confirmed or user dismiss (rules wired with Safety).

### 4.4 Inbox required before first ship

First ship gate: **Phase A complete** = notify + copy actions + **inbox** + bank logos.  
Do not ship Phase A without inbox.

### 4.5 Copy behavior

| Action | Clipboard contents |
|---|---|
| คัดลอกยอด | Amount of **active** order as displayed (e.g. `100.00`) |
| คัดลอกบัญชี | **Full account digits** of active order (e.g. `4774090171`) |

Works from notification actions and from inbox.  
No auto-paste into bank apps in v1.  
After copy: short toast confirming amount or account tail so staff know which order was copied.

---

## 5. Bank logos (approved)

| Decision | Detail |
|---|---|
| Source | **In-app assets** only — map `bank` → bundled asset |
| Where shown | **Notification and inbox** |
| Network | **No** logo fetch / scrape from the web |
| Size budget | Roughly **100–400 KB** total for main Thai banks |
| Unknown bank | **Generic icon** fallback |

Implementation note: use small WebP/PNG (or vector) assets under mobile assets; mapping table in Dart. Placeholders during design/mockups are fine; ship uses real in-app assets licensed for redistribution.

---

## 6. Safety — S0 accepted as approach A

**S0 = A (approved):** anti double-transfer is part of the product design and ships wired with Phase B (S1–S3), not a later afterthought.

| State | Phone UX | Queue / copy |
|---|---|---|
| Pending withdraw | Heads-up / shade + copy buttons | In withdraw queue; can be active |
| Slip received / processing | **กำลังดำเนินการ — อย่าโอนซ้ำ** | Copy for that `order_id` **hidden/disabled** |
| Confirm success | **ปิดงานเรียบร้อย** | **Remove** that order from queue + dismiss withdraw notify |
| Confirm fail after slip | Loud **red** **ไม่สำเร็จ: {reason}** + do not transfer again until check Jinbao/PC | **Must not** silent re-queue as a new withdraw; keep fail state until acknowledge / PC clears |

**Source of truth:** PC slip / confirm status — not staff memory of the bank app.

Identity: bind every notify and copy action to **`order_id`** (fallback amount+account only if `order_id` missing — prefer always having `order_id`).

---

## 7. Phase B — Slip status (after Phase A ship)

| Stage (enum) | Thai UI |
|---|---|
| `received` | **โอนเงินสำเร็จ** |
| `processing` | **กำลังดำเนินการ — อย่าโอนซ้ำ** |
| `done` | **ปิดงานเรียบร้อย** |
| `failed` | **ไม่สำเร็จ: {reason}** |

Rules:

- Separate channel / notification id from Phase A withdraw alerts.  
- One status notification per job (`job_id`, else `order_id`); update in-place; coalesce mid hops into `processing`.  
- Heads-up mainly on first stage and terminal (done/fail); processing updates quieter.  
- Tiny JSON only — **do not** resend slip images.  
- **No FCM v1. No bubble.**

Draft payload:

```json
{
  "action": "slip_status",
  "job_id": "...",
  "order_id": "...",
  "amount": "1464.00",
  "stage": "received | processing | done | failed",
  "message_th": "กำลังดำเนินการ — อย่าโอนซ้ำ",
  "ts": 0
}
```

---

## 8. Ship order (locked)

1. **First ship:** Phase A complete — `withdraw_notify` + local notify + copy amount/full account + inbox + bank logos (+ versions bumped for touched surfaces).  
2. **Then:** Phase B (`slip_status`) + Safety **S1–S3** (hide copy after slip, remove on success, loud fail / no silent re-queue).  
3. Optional later: S4 acknowledge-before-unlock-copy, S5 suppress already-approved scrape, FCM Phase C, bubble.

**Versions (when implementing — not in this doc commit):** bump mobile (`pubspec.yaml` + `kAppVersion`), PC / `release/version.json`, and relay as each surface is touched. Never ship stale display versions.

---

## 9. Permissions & channels

| Item | Spec |
|---|---|
| `POST_NOTIFICATIONS` | Already in manifest; request at runtime on Android 13+ for new channels |
| Phase A channel | e.g. `withdraw_alerts` — `IMPORTANCE_HIGH` (heads-up), separate from FGS `clipsync` LOW channel |
| Phase B channel | e.g. `slip_status` — DEFAULT or HIGH; terminal success/fail may use higher priority / sound |
| Delivery path | Existing FGS + WebSocket — status and withdraw only while connected |

---

## 10. Surfaces to touch (implement later)

| Area | Likely files | When |
|---|---|---|
| Relay | `server/relay_server.py` (+ tests) | A then B |
| PC emit / normalize | `pc/clipsync/orchestrator.py`, bootstrap / transport PC→phone | A then B |
| Extension scrape | `pc/chrome-extension/` + Jinbao profile (full account + name) | A |
| Mobile | `clip_service.dart` WS handler, notification helper, inbox UI, bank asset map | A then B |
| Versions | mobile pubspec + `kAppVersion`, `release/version.json`, PC/relay as touched | each ship |

Mobile dependency: add `flutter_local_notifications` (or equivalent). FGS + WS already present.

---

## 11. Out of scope (v1)

- Bubble / overlay over bank apps  
- FCM / cloud push when process is killed  
- Auto-paste / accessibility fill into bank apps  
- iOS  
- License web admin work  
- Chrome Setup install track (separate plan)  
- Replacing the existing plain `clip` clipboard sync  
- Pixel-perfect RemoteViews on every OEM  
- Guaranteeing delivery if WS/FGS is down at terminal event (v1 = best-effort + staff check PC/Jinbao)

---

## 12. Acceptance (for implement / QA)

### Phase A (first ship)

1. New Jinbao pending order → all online paired phones get heads-up while WS up.  
2. Shade shows detail + copy amount / copy full account; clipboard matches active order.  
3. 10+/min simulated → summary/throttle; no unbounded notification spam; copy still targets active.  
4. App inbox lists pending orders; logos on notification + inbox; unknown bank → generic.  
5. No bubble, no FCM.

### Phase B + S1–S3

1. Slip pipeline stages show Thai messages; one notification per job updated in-place.  
2. After match/slip on `order_id` X → copy for X hidden + “อย่าโอนซ้ำ”.  
3. Confirm success on X → X removed from withdraw queue and withdraw notify.  
4. Confirm fail on X → loud red + reason; **not** silent new withdraw.  
5. No FCM; if WS down, status may be missed (accepted in v1).

---

## 13. Thai summary (review gate)

- ใช้ relay แบบ typed `withdraw_notify` (ไม่ยัด `clip` / ไม่ poll HTTP)  
- เส้นทาง: Jinbao → ext → PC (บัญชีเต็ม+ชื่อ+order_id) → relay → **ทุกมือถือ online** → คิว + local notify  
- Phase A: heads-up+expanded = ใบเดียว · คัดลอกยอด · คัดลอกบัญชี**เต็ม** · active=ใบล่าสุด · **ต้องมี inbox ก่อน ship** · summary/throttle  
- โลโก้ธนาคาร = **asset ในแอป** โชว์ทั้ง notify+inbox · ไม่โหลดเน็ต · ไม่รู้จักใช้ไอคอนทั่วไป  
- Safety S0 แบบ A: มีสลิปแล้วซ่อนคัดลอก+อย่าโอนซ้ำ · สำเร็จลบคิว · fail แดงดัง ห้าม re-queue เงียบ  
- Ship แรก = Phase A ครบ แล้วค่อย Phase B + S1–S3 · ไม่มี bubble/FCM ใน v1  

**เอกสารนี้พร้อมให้รีวิว / OK ก่อนเริ่ม implement — ยังไม่ลงโค้ดฟีเจอร์**

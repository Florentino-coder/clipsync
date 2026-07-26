# Withdraw Amount Scrape + Notify/Inbox UX Fix Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix wrong withdraw notify amounts (e.g. **฿1.00** when Jinbao shows **5,000.00**), harden shade **คัดลอกยอด / คัดลอกบัญชี**, and restyle notify + inbox **รายการถอนรอโอน** with clear line breaks and light emoji so cashiers can tell fields apart.

**Architecture:** (A) Extension scrape must not treat row **ลำดับ** / short bare integers as amounts — prefer `X,XXX.00` / labeled จำนวนเงิน cells. (B) Mobile share one `formatWithdrawDisplay*` helper for notification BigText and inbox cards; emoji prefixes; optional `showsUserInterface: true` on copy actions if shade copy still fails on OEM. (C) Ops note only for stale APK `0.9.5+26` — confirm CI publishes `0.9.9+33+`; no pipeline rewrite unless CI still wrong.

**Tech Stack:** Chrome extension scrape (`engine.js`), Flutter mobile (`withdraw_notify_service.dart`, `withdraw_inbox_page.dart`), Node + flutter_test.

**Worktree:** `.worktrees/feat-slip-auto-confirm`

**Related (separate plan — do first or in parallel):**  
[`2026-07-26-ext-search-save-status.md`](./2026-07-26-ext-search-save-status.md) — Save alert + ค้นหา status + click fix → ext **1.0.43**

**Suggested versions when this plan ships:**
| Surface | Next |
|---|---|
| Extension | **1.0.44** if amount scrape ships after 1.0.43; or fold into **1.0.43** if same release train |
| Mobile | **0.9.9+34** (`pubspec` + `kAppVersion`) |
| PC | unchanged unless normalize needed |
| `release/version.json` | notes for android + extension |

---

## Problem evidence (user screenshots 2026-07-26)

| Symptom | Likely cause |
|---|---|
| Notify/inbox **ยอด: 1.00** while Jinbao row is **5,000.00** | Scrape takes first cell matching `\d{1,8}` → **ลำดับ = 1** |
| Shade **คัดลอกยอด/บัญชี** ไม่ทำงาน | Background action / OEM; inbox toast already works for some copies |
| Body hard to read | Single dense lines without visual hierarchy |
| Phone showed **0.9.5+26** / `ClipSync-13.apk` | Stale APK; live `slip-test-latest` is **0.9.9+33** |

---

## Locked decisions

| # | Decision |
|---|---|
| A1 | Amount cell: reject bare integers with **length ≤ 3** (and optionally ≤ 4 if no thousand sep / no decimals) unless near label จำนวนเงิน. Always prefer `[\d,]+\.\d{2}`. |
| A2 | Prefer amount from cell whose text includes `จำนวนเงิน` / `THB` / `บาท` when present. |
| A3 | Notify + inbox body format (shared helper), Thai + emoji: |
| | `💰 ยอด: 5,000.00` |
| | `🏦 บัญชี: 1048989698` |
| | `🏧 ธนาคาร: KBANK` |
| | `👤 ชื่อ: …` (if present) |
| | `🕒 ถอน: …` / `✅ อนุมัติ: …` when times exist in payload |
| A4 | Shade copy: keep payload-based copy; if still flaky, set copy actions `showsUserInterface: true` **or** open inbox + snackbar (product: prefer UI peek on copy for reliability). |
| A5 | Do **not** change historical WDRAW seed/backfill. |
| A6 | Version ops: document “install only ClipSync-slip.apk from slip-test-latest”; no rename to ClipSync-13. |

---

## File map

| Path | Responsibility |
|---|---|
| `pc/chrome-extension/engine.js` | `cellAmountText` / scrape amount heuristics |
| `pc/chrome-extension/tests/engine.test.js` | Fixture: seq `1` + amount `5,000.00` → amount 5000 not 1 |
| `mobile/lib/withdraw/withdraw_notify_service.dart` | Shared format + copy action flags |
| `mobile/lib/withdraw/withdraw_inbox_page.dart` | Card layout + emoji lines |
| `mobile/lib/withdraw/withdraw_order.dart` | Optional time fields if already on model |
| `mobile/test/withdraw_notify_service_test.dart` / `withdraw_inbox_test.dart` | Format + copy tests |
| `mobile/pubspec.yaml` + `clip_service.dart` `kAppVersion` | **0.9.9+34** |
| `pc/chrome-extension/manifest.json` | bump if scrape ships here |
| `release/version.json` | notes |

---

## Tasks

### Task 1: Extension — stop seq number becoming amount (PRIMARY data bug)

**Files:** `engine.js`, `tests/engine.test.js`

- [ ] **Step 1: Failing test**

```html
<tr>
  <td>1</td>
  <td>…สมาชิก… 1048989698 …</td>
  <td>จำนวนเงิน : 5,000.00THB</td>
  <td>อนุมัติ</td>
</tr>
```
Expect `orders[0].amount` ∈ `5000` / `5,000.00` — **not** `1`.

- [ ] **Step 2: Harden `cellAmountText`**
  - Accept `5,000.00` / `5000.00` always.
  - Reject `/^\d{1,3}$/` bare ints.
  - If cell has `จำนวนเงิน` or `THB`/`บาท`, extract money token inside.
- [ ] **Step 3: Tests pass → commit**  
  `fix(ext): do not scrape row index as withdraw amount`

---

### Task 2: Mobile — shared emoji display format

**Files:** `withdraw_notify_service.dart` (+ optional small `withdraw_format.dart`), tests

- [ ] **Step 1: Failing tests** for `formatWithdrawNotifyBody` / new `formatWithdrawInboxLines` containing `💰` / `🏦` and newlines.
- [ ] **Step 2: Implement shared formatter** used by notify BigText and inbox.
- [ ] **Step 3: Commit**  
  `feat(mobile): emoji structured withdraw notify/inbox copy`

---

### Task 3: Mobile — inbox layout tidy

**Files:** `withdraw_inbox_page.dart`, `withdraw_inbox_test.dart`

- [ ] Stack: amount (large) → account → bank/name → times → status chip → copy buttons.
- [ ] Keep คัดลอกยอด / คัดลอกบัญชี TextButtons.
- [ ] Commit  
  `feat(mobile): tidy withdraw inbox rows with emoji labels`

---

### Task 4: Mobile — shade copy reliability

**Files:** `withdraw_notify_service.dart`

- [ ] Verify foreground + background handlers still payload-first.
- [ ] If product chooses reliability: `AndroidNotificationAction(..., showsUserInterface: true)` for both copy actions **or** on action open inbox then copy + snackbar.
- [ ] Add/adjust tests for action wiring.
- [ ] Commit  
  `fix(mobile): harden withdraw notification copy actions`

---

### Task 5: Versions + release notes

- [ ] Mobile **0.9.9+34** (pubspec + kAppVersion match)
- [ ] Extension bump if Task 1 in this ship (**1.0.43** or **1.0.44** depending on search-status plan order)
- [ ] `release/version.json` notes
- [ ] Push + tell user: reinstall APK from slip-test-latest only; ignore ClipSync-13.apk / 0.9.5+26

---

## Suggested execution order vs other plan

```text
1) ext-search-save-status (1.0.43)     — Save alert + ค้นหา status + click fix
2) THIS plan Task 1 (amount scrape)    — can merge into same ext bump if preferred
3) THIS plan Tasks 2–4 (mobile UX)     — 0.9.9+34
4) QA on device with fresh APK
```

If user wants **one** mobile+ext ship: do search-status + amount scrape as **1.0.43**, then mobile **0.9.9+34**.

---

## Acceptance checklist

1. New approved row 5,000.00 → notify/inbox show **5000** (not 1.00).  
2. Notify body readable with emoji line breaks.  
3. Inbox **รายการถอนรอโอน** same hierarchy + emoji.  
4. Shade copy works on test phone **or** opens UI and copies reliably.  
5. Installed APK shows **0.9.9+34** (not 0.9.5+26).  

---

## Explicit non-goals

- Jinbao Search save-alert / button status (other plan)  
- Auto 3-min checkbox toggle  
- Historical notify backfill  

---

## Plan-only status

**Do not implement until the user says to proceed.**  
When proceeding, clarify order: this plan alone, or after/with `ext-search-save-status`.

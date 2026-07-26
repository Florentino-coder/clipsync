# Extension Search Refresh: Save Feedback + Button Status + Click Fix

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make **「รีเฟรชหน้าอนุมัติแล้ว — กดค้นหา」** actually work on live Jinbao, and give cashiers clear feedback: (1) **alert/toast when Save succeeds**, (2) **live status whether the ค้นหา button was found** on the open tab (plus last skip/click reason).

**Architecture:** Content script probes `findApprovedSearchButton` + tab/busy gates on an interval (or on demand), writes status to `chrome.storage.local` (`approvedSearchStatus`). Popup reads that status and shows green/red line. Save handlers for scrape + page-refresh show an immediate in-popup confirmation (and optionally `alert()` once — prefer non-blocking banner). Fix click path: treat URL `tab=1` / withdraw page as approved when DOM tab chrome is missing; prefer `button.btn-primary[type=submit]` and `form.requestSubmit()` for BootstrapVue Jinbao.

**Tech Stack:** Chrome MV3 (`popup.*`, `content-script.js`, `engine.js`, `background.js` if message relay needed), Node tests.

**Worktree:** `.worktrees/feat-slip-auto-confirm`  
**Baseline already shipped:** extension **1.0.42** (search timer + red 3-min warning). This plan is the **follow-up fix + UX**.  
**Suggested bump:** extension **1.0.43** + `release/version.json` notes.

**Out of scope (separate plans / later):**
- Notify/inbox emoji + amount `1.00` vs seq-column scrape bug (advised earlier — do after or in parallel plan)
- Mobile APK version confusion `0.9.5+26`

---

## Locked product decisions

| # | Decision |
|---|---|
| D1 | **Save feedback:** After **Save page refresh** and **Save scrape refresh**, show clear confirmation that value was written (seconds + ms). Prefer in-popup status flash (2–3s) **and** a one-shot `window.alert` is OK if user asked for “alert” literally — **use both soft banner + `alert()` for Save page refresh** so it is impossible to miss. Scrape save: soft banner enough; page refresh: soft banner + `alert`. |
| D2 | **Button status line** always visible under page-refresh section, e.g. `สถานะปุ่มค้นหา: ✅ เจอแล้ว` / `❌ ไม่เจอ` / `⏳ รอแท็บ Jinbao…` |
| D3 | Status also shows **last tick reason** when not clicking: `wrong_tab` / `unknown_tab` / `busy` / `no_button` / `clicked` + timestamp. |
| D4 | Content script updates `approvedSearchStatus` at least every search interval **and** once on load / when popup asks `ping_search_status`. |
| D5 | **Click fix:** (a) approved if URL has `tab=1` or path `/withdraw/transaction` and not pending-tab DOM; (b) selectors include `button.btn.btn-primary`, `button[type=submit]`; (c) if `type=submit` inside `<form>`, use `form.requestSubmit()` when available else `btn.click()`. |
| D6 | Never click **ล้าง**. Never full reload. Keep red คำเตือน about 3-min checkbox. |
| D7 | No PC/mobile changes in this plan. |

---

## Root-cause notes (why 1.0.42 felt broken)

1. **`maybeClickApprovedSearch` requires `detectWithdrawNotifyTab === true`.** Jinbao approved UI may not use `.el-tabs__item.is-active` → status `unknown_tab` → **never clicks**, even though scrape still runs (`tabKind === false` only blocks scrape).
2. Live button is BootstrapVue: `<button type="submit" class="btn … btn-primary">ค้นหา</button>` — need submit-aware click.
3. Save wrote storage silently — cashiers could not tell if Save worked.

---

## File map

| Path | Change |
|---|---|
| `pc/chrome-extension/engine.js` | Tab URL hints; `btn-primary`; `requestSubmit`; export status helper if useful |
| `pc/chrome-extension/content-script.js` | Publish `approvedSearchStatus`; optional reply to `get_approved_search_status` |
| `pc/chrome-extension/background.js` | Relay popup ↔ tab message if needed (`tabs.sendMessage`) |
| `pc/chrome-extension/popup.html` / `popup.js` | Status line; save alert/banner; refresh status on open |
| `pc/chrome-extension/profiles/jinbao356_v1.json` + `bundled_profiles.js` | `withdraw_notify_tab_query: "tab=1"`; selectors `button.btn-primary` |
| `pc/chrome-extension/tests/engine.test.js` | URL tab=1; submit button click; status reasons |
| `pc/chrome-extension/manifest.json` | **1.0.43** |
| `release/version.json` | extension notes |

---

## Storage shape

```js
// chrome.storage.local.approvedSearchStatus
{
  found: true,                 // boolean | null (unknown / no tab)
  reason: 'clicked',           // last maybeClickApprovedSearch reason or 'probed'
  detail: 'ค้นหา',             // button label if found
  href: 'https://manage…/withdraw/transaction?tab=1…',
  at: '2026-07-26T11:30:00+07:00',
  intervalSec: 10
}
```

---

## Tasks

### Task 1: Fix tab detection + submit click (make refresh actually run)

**Files:** `engine.js`, `jinbao356_v1.json`, `bundled_profiles.js`, `tests/engine.test.js`

- [ ] **Step 1: Failing tests**
  - Fixture with `tab=1` in `location` mock / JSDOM URL + **no** el-tabs active → `detectWithdrawNotifyTab` / click path treats as approved.
  - Fixture with BootstrapVue submit button → `findApprovedSearchButton` finds it; `maybeClickApprovedSearch` triggers submit (spy `requestSubmit` or click count).
  - Pending tab still skipped.

- [ ] **Step 2: Implement**
  - Profile: `"withdraw_notify_tab_query": "tab=1"` (and keep pending query if any).
  - Selectors: add `button.btn-primary`, `button.btn.btn-primary`.
  - Click: if `btn.type === 'submit' && btn.form`, prefer `btn.form.requestSubmit()`.
  - Optionally: if tab is `null` but URL matches `order_page_url_hint` + `tab=1`, treat as approved for **search click only**.

- [ ] **Step 3: Tests pass → commit**  
  `fix(ext): make approved Search click work on Jinbao tab=1 + submit`

---

### Task 2: Content script publishes search-button status

**Files:** `content-script.js`, `background.js` (if needed)

- [ ] **Step 1:** After each `maybeClickApprovedSearch` (and on a lightweight `probe` without click every N seconds if desired), write `approvedSearchStatus` to `chrome.storage.local`.
- [ ] **Step 2:** On message `get_approved_search_status` from popup/background, run one probe (`findApprovedSearchButton` + tab kind) **without** forcing a search click, return + store status.
- [ ] **Step 3:** Commit  
  `feat(ext): publish approved Search button found/status to storage`

---

### Task 3: Popup — Save alert + status UI

**Files:** `popup.html`, `popup.js`

**Save feedback (page refresh):**
```text
alert("บันทึกแล้ว: รีเฟรชหน้าทุก X วินาที")
```
Plus green inline `#saveSearchFlash` text for 3s: `✓ บันทึกแล้ว (Xs)`.

**Save scrape:** inline flash only (or same alert pattern for consistency — prefer flash for scrape, alert for page refresh per D1).

**Status block (always visible under Save page refresh):**
```html
<p id="searchBtnStatus" class="…">สถานะปุ่มค้นหา: ⏳ เปิดแท็บ Jinbao รายการที่อนุมัติแล้ว…</p>
```
- `found === true` → green `✅ เจอแล้ว (ค้นหา)`  
- `found === false` → red `❌ ไม่เจอปุ่มค้นหา`  
- include `reason` + time: `ล่าสุด: clicked · 11:32:01` / `ล่าสุด: unknown_tab · …`

- [ ] **Step 1:** On popup open: `chrome.storage.local.get('approvedSearchStatus')` + request fresh probe via runtime message.
- [ ] **Step 2:** Listen `storage.onChanged` for live updates while popup is open.
- [ ] **Step 3:** Wire Save handlers with alert/flash.
- [ ] **Step 4:** Commit  
  `feat(ext): Save alert + ค้นหา button status in popup`

---

### Task 4: Version bump + QA

- [ ] Bump `manifest.json` → **1.0.43**
- [ ] `release/version.json` extension notes: `Search click fix (tab=1/submit); Save alert; button found status`
- [ ] Commit + push `origin` + `v2 HEAD:main`

**Manual QA**
1. Reload extension → **v1.0.43**
2. Open Jinbao **รายการที่อนุมัติแล้ว** (`tab=1`)
3. Open popup → status should become **✅ เจอแล้ว** within a few seconds
4. Set 10s → **Save page refresh** → must see **alert** + flash
5. Watch network/table refresh ~every 10s; filters unchanged
6. Switch to รออนุมัติ → status / reason shows wrong_tab; no Search click
7. Confirm red 3-min warning still visible

---

## Acceptance checklist

1. Save page refresh → user **cannot miss** success (alert).  
2. Popup shows whether **ค้นหา** is found on the active Jinbao tab.  
3. Last reason (`clicked` / `unknown_tab` / …) visible.  
4. On approved tab with BootstrapVue submit button, auto-search **actually runs**.  
5. Filters preserved; ล้าง never clicked.  
6. Extension **1.0.43** shipped.

---

## Explicit non-goals

- Auto-tick/untick Jinbao 3-min checkbox  
- Mobile notify emoji / amount 1.00 scrape fix (track separately)  
- PC changes  

---

## Plan-only status

**Do not implement until the user says to proceed.**

# Jinbao Approved-Tab Search Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let cashiers set how often ClipSync **reloads the Jinbao approved-withdrawals table** by clicking **「ค้นหา」** (not full page reload), so filters like ยอดถอนตั้งแต่ / ยอดถอนไม่เกิน stay filled, the tab stays on **รายการที่อนุมัติแล้ว**, and new rows appear faster than the site’s fixed 3-minute auto-load.

**Architecture:** Keep today’s **DOM scrape interval** (`pendingOrdersPollMs`) separate from a new **page search interval** (`approvedSearchPollMs`). Content script timer (approved tab only) finds the Search button via profile selectors, clicks it when idle (no busy shield / no confirm queue work), then existing MutationObserver + scrape pick up the refreshed table. Popup Settings exposes both intervals with clear Thai copy. No PC/mobile/relay changes.

**Tech Stack:** Chrome MV3 extension (`content-script.js`, `engine.js`, `popup.*`, `poll_settings.js`, `profiles/jinbao356_v1.json`), Node tests (`engine.test.js` / poll settings tests).

**Worktree root:** `.worktrees/feat-slip-auto-confirm` (paths relative to that root)

**Related:** Prior scrape-only refresh shipped in `2026-07-26-withdraw-copy-refresh-ocr.md` Task 4 (extension **1.0.41**). This plan adds **table refresh via Search click**.

---

## Product decisions (locked)

| # | Decision |
|---|---|
| D1 | **Mechanism:** click **ค้นหา** — never `location.reload()`, never click **ล้าง**. |
| D2 | **Tab gate:** only when `detectWithdrawNotifyTab` / approved-tab hints say **รายการที่อนุมัติแล้ว**. Skip on รออนุมัติ / unknown. |
| D3 | **Filters:** left untouched — Search reuses current form values (ยอดถอนตั้งแต่ / ไม่เกิน, dates, bank, etc.). |
| D4 | **Two settings (recommended):** (A) scrape/read interval — existing `pendingOrdersPollMs`; (B) search-click interval — new `approvedSearchPollMs`. Default search **30000** ms; clamp **10000–300000** same as scrape. |
| D5 | **Safety:** skip click if `#clipsync-busy-shield` present, or confirm `commandQueue` is running a `confirm_order`, or dry_run does **not** need to block Search (Search is read-only for the site list — still allowed in dry_run). |
| D6 | **Site checkbox** 「โหลดอัตโนมัติทุก 3 นาที」: **do not** auto-check/uncheck on load (Jinbao may leave it unchecked by default — OK). Instead show a persistent **red warning** in the ClipSync popup (and optionally a small on-page banner) telling cashiers **ห้ามติ๊ก** that checkbox. |
| D7 | **Impact:** withdraw notify benefits; clipboard/OCR untouched; auto-confirm protected by D5. |
| D8 | Versions: bump extension only (suggested **1.0.42**) + `release/version.json` notes when shipping. |

Optional later (not this plan): single combined interval; auto-toggle site 3-min checkbox.

---

## Why not only raise scrape frequency?

Scrape reads **whatever HTML is already on screen**. If Jinbao’s table is stale for up to 3 minutes, faster scrape still sees old rows. Clicking **ค้นหา** forces the site to fetch with current filters — that is the missing piece.

```text
[Filters stay] → click ค้นหา → table updates → MutationObserver / poll scrape → PC WDRAW
```

---

## File map

| Path | Responsibility |
|---|---|
| `pc/chrome-extension/poll_settings.js` | Clamp helpers for both poll ms keys; shared by popup + content script |
| `pc/chrome-extension/popup.html` / `popup.js` | Second Settings block: “รีเฟรชหน้า (กดค้นหา)” seconds + presets + Save |
| `pc/chrome-extension/engine.js` | `findApprovedSearchButton(profile)` + optional `clickApprovedSearch(profile)` pure-ish DOM helpers |
| `pc/chrome-extension/content-script.js` | Timer for search click; tab + busy gates; storage listener |
| `pc/chrome-extension/profiles/jinbao356_v1.json` + `bundled_profiles.js` | Selectors / button text hints for ค้นหา |
| `pc/chrome-extension/tests/…` | Unit tests: find button, skip wrong tab, skip busy, clamp |
| `pc/chrome-extension/manifest.json` | Version bump on ship |
| `release/version.json` | `extension` version + notes |

---

## Recommended execution order

1. Profile selectors + `findApprovedSearchButton` + tests  
2. Content-script timer + safety gates  
3. Popup UI for `approvedSearchPollMs` + **red คำเตือน** about site 3-min checkbox  
4. Version bump + manual QA checklist  

---

### Task 1: Profile hints + find Search button

**Files:**
- Modify: `pc/chrome-extension/profiles/jinbao356_v1.json`
- Modify: `pc/chrome-extension/bundled_profiles.js` (regen or mirror JSON fields)
- Modify: `pc/chrome-extension/engine.js`
- Test: `pc/chrome-extension/tests/engine.test.js` (or new `search_refresh.test.js`)

**Profile fields (example):**
```json
"approved_search_button_texts": ["ค้นหา", "Search"],
"approved_search_button_selectors": [
  "button.el-button--primary",
  "button[type=submit]"
]
```
Prefer: visible button whose text matches ค้นหา inside the filter form region; exclude **ล้าง**.

- [ ] **Step 1: Failing test** — fixture HTML with filter form + ค้นหา / ล้าง; `findApprovedSearchButton` returns ค้นหา node only.

```html
<form>
  <input placeholder="ยอดถอนตั้งแต่" value="100" />
  <input placeholder="ยอดถอนไม่เกิน" value="5000" />
  <button type="button">ล้าง</button>
  <button type="button" class="el-button--primary">ค้นหา</button>
</form>
<div class="el-tabs__item is-active">รายการที่อนุมัติแล้ว</div>
```

- [ ] **Step 2: Implement `E.findApprovedSearchButton(profile, doc=document)`**
- [ ] **Step 3: Tests pass**
- [ ] **Step 4: Commit** `feat(ext): locate Jinbao approved-tab Search button`

---

### Task 2: Click helper + safety gates

**Files:**
- Modify: `pc/chrome-extension/engine.js`
- Modify: `pc/chrome-extension/content-script.js`
- Test: extend engine/content tests with jsdom fixtures

**Behavior of `maybeClickApprovedSearch(profile)`:**
1. If not approved tab → return `{ clicked: false, reason: 'wrong_tab' }`
2. If `#clipsync-busy-shield` in DOM → `{ clicked: false, reason: 'busy' }`
3. If no button → `{ clicked: false, reason: 'no_button' }`
4. Else `button.click()` → `{ clicked: true }`  
   Do **not** clear inputs. Do **not** navigate.

Content script:
- Storage key `approvedSearchPollMs` (default 30000)
- `restartApprovedSearchTimer(profiles, ms)` via `setInterval`
- On tick: for each active profile matching page, call `maybeClickApprovedSearch`
- Listen `chrome.storage.onChanged` for the new key (same pattern as scrape poll)
- Prefer running search click **outside** `enqueue(confirm)` or skip when queue not idle — simplest: skip when busy shield exists (shown for whole confirm). Optionally also skip if `commandQueue` thenable is pending (track `confirmInFlight` boolean).

- [ ] **Step 1: Failing tests** for wrong_tab / busy / click
- [ ] **Step 2: Implement**
- [ ] **Step 3: Tests pass**
- [ ] **Step 4: Commit** `feat(ext): auto-click ค้นหา on approved tab at interval`

---

### Task 3: Popup Settings UI (separate from scrape refresh) + red warning

**Files:**
- Modify: `pc/chrome-extension/poll_settings.js` — add `clampApprovedSearchPollMs` (can alias same clamp)
- Modify: `pc/chrome-extension/popup.html`
- Modify: `pc/chrome-extension/popup.js`
- Test: existing poll settings tests + load/save new key

**UI copy (Thai):**
- Title: **รีเฟรชหน้าอนุมัติแล้ว (กดค้นหา)**
- Helper: `บังคับโหลดตารางใหม่โดยกด「ค้นหา」 — ฟิลเตอร์ยอดถอน/วันที่คงอยู่ (10–300 วินาที)`
- Presets: 15 / 30 / 45 / 60 / 120
- Button: **Save page refresh**
- Keep existing block labeled clearly as **อ่านรายการส่ง PC** (scrape only) so cashiers are not confused.

**คำเตือน (required — red text):**
- Place under the page-refresh Settings (highly visible; bold label **คำเตือน**).
- Exact intent (Thai, red CSS e.g. `color: #c62828` / class `.warn-danger`):

```text
คำเตือน: ห้ามติ๊ก 「โหลดอัตโนมัติทุก 3 นาที」 บนหน้าเว็บ Jinbao
ใช้รีเฟรชของ ClipSync (กดค้นหา) แทน — ถ้าติ๊กทั้งคู่จะโหลดซ้ำและอาจช้า/ชนกัน
```

- **Do not** auto-tick or auto-untick the site checkbox when the page opens (user confirmed default unchecked is fine).
- Optional (same task if cheap): small fixed/on-page red tip near the Jinbao checkbox when on approved tab — still **text-only**, no DOM mutation of the checkbox state. Skip if it fights the busy shield; popup warning alone is enough for v1.

- [ ] **Step 1: Wire load/save `approvedSearchPollMs`**
- [ ] **Step 2: Add red คำเตือน block in `popup.html` (+ minimal CSS)**
- [ ] **Step 3: Manual** — change 15→60; content script timer restarts without Chrome restart; warning visible in popup
- [ ] **Step 4: Commit** `feat(ext): Settings for approved Search refresh + red 3-min warning`

---

### Task 4: Clarify scrape vs search labels + ship

**Files:**
- Modify: `popup.html` labels for the **existing** scrape control (rename muted text so it no longer says only “รีเฟรชรายการรอดำเนินการ” in a misleading way)
- Modify: `pc/chrome-extension/manifest.json` → **1.0.42**
- Modify: `release/version.json` extension version + notes

Example notes: `Auto-click ค้นหา on approved tab; red warn against Jinbao 3-min auto-load; separate scrape interval`

- [ ] **Step 1: Bump + label polish**
- [ ] **Step 2: Commit** `chore(ext): bump 1.0.42 approved search refresh`

---

## Acceptance checklist

1. On **รายการที่อนุมัติแล้ว**, with filters filled (ยอดถอนตั้งแต่ / ไม่เกิน), Search auto-fires at configured interval.  
2. Filter values **unchanged** after each auto-search.  
3. Tab stays on approved list (not jumped to รออนุมัติ).  
4. On **รออนุมัติ** tab → **no** Search click.  
5. During auto-confirm busy shield → **no** Search click.  
6. Scrape interval still independently configurable.  
7. New approved rows appear for withdraw notify sooner than waiting for site’s 3-minute checkbox alone.  
8. dry_run still only blocks confirm clicks, not Search.  
9. Popup shows **red คำเตือน** telling staff **ห้ามติ๊ก** 「โหลดอัตโนมัติทุก 3 นาที」.  
10. Extension does **not** auto-check that Jinbao checkbox on page load.  

## Manual QA (Jinbao)

1. Reload extension → **1.0.42**  
2. Set page refresh **15s**, scrape **45s** (or whatever).  
3. Fill ยอดถอนตั้งแต่ / ไม่เกิน → Save page refresh.  
4. Watch network/table update ~every 15s without typing filters again.  
5. Start a confirm → shield up → Search must pause.  
6. Confirm popup red warning is visible; leave Jinbao 3-min checkbox **unchecked**.  

## Explicit non-goals

- No full page reload  
- No auto-clear / rewrite of filter fields  
- No PC/mobile/relay changes  
- **No automatic check/uncheck** of Jinbao’s 「โหลดอัตโนมัติทุก 3 นาที」 — warning text only  
- No historical WDRAW backfill changes  

## Impact summary (for stakeholders)

| System | Effect |
|---|---|
| Withdraw notify | Faster fresh rows (intended) |
| Auto-confirm | Safe if busy gate works |
| Clipboard / slip OCR | None |
| Jinbao server | More Search requests — keep interval ≥15–30s in production guidance; avoid double-load with site 3-min checkbox (red warning) |

## Questions before coding?

**None blocking** — defaults above match the advice the user approved (กดค้นหา + คงฟิลเตอร์ + แยกตั้งค่า + red warning, no auto-tick).

Optional: default search interval 30s vs 15s — plan uses **30s**.

---

## Plan-only status

This document is the implementation plan. **Do not implement until the user says to proceed.**

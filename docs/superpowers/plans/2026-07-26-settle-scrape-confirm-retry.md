# Settle scrape + short confirm retry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make auto-confirm stabler against Jinbao Search refresh races — settle DOM before scrape, pause Search when a slip arrives, and retry match for **at most ~4 seconds** (not longer — double-transfer risk).

**Architecture:** Three complementary layers. (2) Extension: after clicking 「ค้นหา」, wait for results text to settle, then publish `pending_orders`. (3) PC→extension: on slip intake, pause Search + request one fresh scrape before / while matching. (1) PC orchestrator: if first `resolve_auto_match` yields `no_match` (or empty-list race), retry match a few times within a **4s** wall clock, then `pending_review`. Confirm-in-flight Search pause from extension **1.0.46** stays.

**Tech Stack:** Chrome extension (`content-script.js` / `engine.js` / `background.js`), PC `clipsync/orchestrator.py` + `chrome_bridge.py`, pytest + node:test.

**Locked product knobs (do not change without user OK):**

| Knob | Value |
|---|---|
| Match retry wall clock | **4.0 s** max |
| Match retry cadence | attempt at **t=0, ~1.3s, ~2.6s** (≤3 attempts) |
| Post-Search scrape settle | **~2.0 s** debounce **or** 「พบ: N」 text unchanged for **800 ms** (whichever first after click; cap 2.5 s) |
| Search pause on slip | **≥ confirm window**; reuse existing `pause_approved_search` / confirm pause (~45s after confirm already) |
| Do **not** retry | `missing_sender_last4`, `over_amount_threshold`, `auto_confirm_disabled`, `parse_failed` (hard gates) — only soft **`no_match`** (and optionally treat empty scrape the same via existing `amount_only` path) |

---

## File map

| File | Responsibility |
|---|---|
| `pc/chrome-extension/content-script.js` | Search click → settle → scrape; handle `pause_approved_search` + `request_pending_scrape`; keep confirm pause |
| `pc/chrome-extension/engine.js` | Optional pure helper: detect results-count text / settle predicate (testable) |
| `pc/chrome-extension/background.js` | Forward new WS types: `pause_approved_search`, `request_pending_scrape` to admin tab |
| `pc/clipsync/chrome_bridge.py` | `push_pause_approved_search(ms)`, `push_request_pending_scrape()` |
| `pc/clipsync/orchestrator.py` | On slip: pause + request scrape; short `no_match` retry loop (4s) |
| `pc/tests/test_orchestrator.py` | Retry timing / only `no_match` retries / hard gates no-retry |
| `pc/tests/test_chrome_bridge.py` | New push helpers serialize correct JSON |
| `pc/chrome-extension/tests/engine.test.js` | Settle helper / scrape-after-search behavior if extracted |
| `pc/chrome-extension/manifest.json` + `release/version.json` | Bump **extension** + **PC** together |

**Out of scope:** OCR / `missing_sender_last4` fixes; mobile APK; lengthening retry past 4s; Jinbao native 3-min checkbox.

---

### Task 1: Extension — settle after Search, then scrape

**Files:**
- Modify: `pc/chrome-extension/content-script.js` (`runApprovedSearchRefresh`, `publishPendingOrders`, timers)
- Modify (optional extract): `pc/chrome-extension/engine.js`
- Test: `pc/chrome-extension/tests/engine.test.js`

- [ ] **Step 1: Failing test for settle helper**

```js
it('isResultsCountStable when พบ text unchanged across samples', () => {
  // fixture: <div>พบ : 4 รายการ</div> — two reads same → true
  // change text → false
});
```

- [ ] **Step 2: Implement helper** (in `engine.js` or content-script pure fn exported for tests)

```js
function readResultsCountLabel(doc) {
  const t = String(doc.body && doc.body.innerText || '');
  const m = t.match(/พบ\s*[:：]?\s*([\d,]+)\s*รายการ/);
  return m ? m[1] : null;
}
```

- [ ] **Step 3: After successful Search click, schedule scrape with settle**

In `runApprovedSearchRefresh`, when `result.clicked === true` (or MAIN-world click fired):

1. Do **not** rely on MutationObserver alone for the immediate post-click publish.
2. Start settle wait: poll every ~200 ms up to **2.5 s**; succeed early if `readResultsCountLabel` same for **800 ms**.
3. Then call `publishPendingOrders(profiles)`.
4. If Search was **paused** / skipped, do not start settle.

- [ ] **Step 4: Run** `npm test` in `pc/chrome-extension` — pass

- [ ] **Step 5: Commit**

```bash
git add pc/chrome-extension/engine.js pc/chrome-extension/content-script.js pc/chrome-extension/tests/engine.test.js
git commit -m "fix(ext): settle Jinbao results before pending_orders scrape after Search"
```

---

### Task 2: Bridge + background — pause Search + request scrape

**Files:**
- Modify: `pc/clipsync/chrome_bridge.py`
- Modify: `pc/chrome-extension/background.js` (`handleServerMessage`)
- Modify: `pc/chrome-extension/content-script.js` (message handlers — `pause_approved_search` may already exist from 1.0.46)
- Test: `pc/tests/test_chrome_bridge.py`

- [ ] **Step 1: Failing bridge tests**

```python
async def test_push_pause_approved_search(bridge):
    await bridge.push_pause_approved_search(ms=8000)
    # client received {"type":"pause_approved_search","ms":8000}

async def test_push_request_pending_scrape(bridge):
    await bridge.push_request_pending_scrape()
    # client received {"type":"request_pending_scrape"}
```

- [ ] **Step 2: Implement bridge push helpers** (same pattern as `push_confirm_order`)

- [ ] **Step 3: background.js** — on those types, `forwardToAdminTab` / `chrome.tabs.sendMessage` like `confirm_order` (no confirm result expected; fire-and-forget OK)

- [ ] **Step 4: content-script** — ensure:
  - `pause_approved_search` → `pauseApprovedSearch(ms)` (already planned/partial)
  - `request_pending_scrape` → `publishPendingOrders(activeProfiles)` **immediately** (still respect confirm busy if needed; prefer allow scrape-read even during short pause)

- [ ] **Step 5: pytest** `pc/tests/test_chrome_bridge.py` — pass

- [ ] **Step 6: Commit**

```bash
git commit -m "feat: PC can pause Search and request fresh pending scrape"
```

---

### Task 3: Orchestrator — slip intake uses 3, then short no_match retry (1)

**Files:**
- Modify: `pc/clipsync/orchestrator.py` (`handle_slip_event`)
- Test: `pc/tests/test_orchestrator.py`

- [ ] **Step 1: Failing tests**

```python
@pytest.mark.asyncio
async def test_no_match_retries_then_pending_review(monkeypatch):
    # pending_orders empty at t=0 → still no_match after retries within 4s
    # assert resolve called >= 2 times; decision pending_review reason no_match
    # assert elapsed < 5.0

@pytest.mark.asyncio
async def test_no_match_becomes_match_on_retry():
    # first resolve None / block no_match; after pending_orders update, second attempt matches → push_confirm_order

@pytest.mark.asyncio
async def test_missing_sender_last4_does_not_retry():
    # block_reason missing_sender_last4 → single path, no sleep loop
```

- [ ] **Step 2: On slip entry (after sig/dedupe, before final match)**

```python
# Pseudocode — keep real structure of handle_slip_event
await self._bridge.push_pause_approved_search(ms=8000)  # if bridge present
await self._bridge.push_request_pending_scrape()
# optional brief yield so extension can publish once
await asyncio.sleep(0.4)
```

Guard with `if self._bridge is not None` / method existence so unit tests without bridge still work.

- [ ] **Step 3: Soft retry only for `no_match`**

```python
RETRY_BUDGET_S = 4.0
RETRY_GAPS_S = (0.0, 1.3, 2.6)  # absolute offsets from start

async def _match_with_short_retry(...):
    start = loop.time()
    last_matched = None
    last_block = "no_match"
    for offset in RETRY_GAPS_S:
        delay = offset - (loop.time() - start)
        if delay > 0:
            await asyncio.sleep(delay)
        if loop.time() - start > RETRY_BUDGET_S:
            break
        matched = resolve_auto_match(...)
        block = auto_confirm_block_reason(...)
        if block != "no_match":
            return matched, block  # hard gate or success path
        if matched is not None and block is None:
            return matched, None
        last_matched, last_block = matched, block
    return last_matched, last_block
```

Important: **do not** retry `missing_sender_last4` (that check stays after a successful match block clear).

- [ ] **Step 4: Wire into `handle_slip_event`** replacing the single-shot match/block section

- [ ] **Step 5: Activity log line** (Thai or existing style), e.g. `Slip match retry (1300.0): attempt 2/3` — keep quiet on success first try

- [ ] **Step 6: Run** `pytest pc/tests/test_orchestrator.py -q` — pass

- [ ] **Step 7: Commit**

```bash
git commit -m "fix(pc): pause Search, refresh scrape, retry no_match within 4s"
```

---

### Task 4: Versions + ship notes

**Files:**
- `pc/chrome-extension/manifest.json` → bump patch (e.g. **1.0.47** if 1.0.46 already has confirm-pause)
- PC version string + `release/version.json` (`pc.version`, `extension.version`, notes)
- Mention: mobile unchanged

- [ ] **Step 1: Bump + notes**

```text
extension: settle after Search; pause/scrape on slip; (keep confirm pause)
pc: slip → pause Search + request scrape; no_match retry ≤4s (≤3 attempts)
```

- [ ] **Step 2: Full verification**

```bash
cd pc/chrome-extension && npm test
cd pc && python -m pytest -q
```

- [ ] **Step 3: Commit + push to `v2` `main` when user asks for build**

```bash
git commit -m "chore: bump ext+pc for settle/scrape/confirm retry"
# git push v2 HEAD:main   # only when user requests CI
```

---

## Acceptance checklist

1. Click Search → scrape published only after settle (not mid-spinner empty flash).  
2. Slip arrives → extension status shows pause; one forced scrape follows.  
3. Artificial empty `pending_orders` then fill within 2s → auto-confirm still fires (retry).  
4. Still empty after 4s → `pending_review` / `no_match` (no long hang).  
5. `missing_sender_last4` → immediate review, **no** retry delay.  
6. Manual confirm + used_refs still block double confirm.  
7. Versions bumped; CI green on request.

---

## Explicit non-goals

- Retry windows > 5s  
- Auto-confirm when account last4 hard-mismatch on a **stable** scrape list (safety)  
- Fixing shade-copy / mobile in this plan  
- Toggling Jinbao 「โหลดอัตโนมัติทุก 3 นาที」

---

## Suggested execution order

```text
Task 1 (ext settle) → Task 2 (bridge messages) → Task 3 (orchestrator retry) → Task 4 (bump/ship)
```

Task 1 and 2 can be parallelized by two agents if desired; Task 3 depends on Task 2 APIs existing (can mock bridge methods first).

---

## Plan-only status

**Do not implement until the user says to proceed.**  
When proceeding, use subagent-driven-development or executing-plans against this file.

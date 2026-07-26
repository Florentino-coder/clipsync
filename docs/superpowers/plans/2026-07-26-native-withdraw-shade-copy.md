# Native Withdraw Shade Copy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make shade **คัดลอกยอด / คัดลอกบัญชี** reliable when the Flutter UI process is paused or dead, by posting withdraw notifications from native Android with clipboard copy via `BroadcastReceiver` (values embedded in `PendingIntent` extras — no Dart queue required for copy).

**Architecture:** Keep Flutter as the source of truth for the withdraw queue + inbox. Phase A adds a small Kotlin notifier + `ClipboardCopyReceiver` and a MethodChannel so Dart calls `WithdrawNativeNotify.show(...)` instead of (or as a hard fallback beside) `flutter_local_notifications` action handlers for copy. Phase B adds optional `RemoteViews` custom expanded layout for a card look; collapsed/heads-up still uses standard `addAction()`. Do **not** rewrite the whole notify stack in Kotlin on day one.

**Tech Stack:** Flutter (`mobile/`), Android Kotlin (`com.clipsync.mobile_build`), `NotificationCompat`, `RemoteViews` (Phase B only), MethodChannel, existing `WithdrawNotifyService` / queue.

**Locked product knobs:**

| Knob | Value |
|---|---|
| Channel id | Keep `withdraw_alerts` (same as today) |
| Copy without opening app | Required |
| Notification stays after copy | `setAutoCancel(false)` / `cancelNotification: false` |
| Toast on Android 12+ | System clipboard indicator only — **no** custom toast on API 31+ |
| Copy text source | Intent extras (`amount` / `account`) — payload-first; never empty-queue lookup |
| Phase order | **A reliability first**, then **B cosmetics** |

**Reference (external sketch):** Claude’s `WithdrawalNotifier` / `ClipboardCopyReceiver` / RemoteViews card — adapt package to `com.clipsync.mobile_build`, do not invent a second channel name.

---

## File map

| File | Responsibility |
|---|---|
| `mobile/android/.../withdraw/ClipboardCopyReceiver.kt` | BroadcastReceiver: copy extra to clipboard |
| `mobile/android/.../withdraw/WithdrawalNotifier.kt` | Build + post notification (actions + optional big view) |
| `mobile/android/.../withdraw/WithdrawNotifyPlugin.kt` | MethodChannel bridge (`show` / `cancel` / `cancelAll`) |
| `mobile/android/.../MainActivity.kt` | Register plugin |
| `mobile/android/.../AndroidManifest.xml` | Register receiver `exported=false` |
| `mobile/android/.../res/layout/notification_withdraw_expanded.xml` | Phase B only |
| `mobile/android/.../res/drawable/*` | Phase B icons / outline button |
| `mobile/lib/withdraw/withdraw_native_notify.dart` | Dart API wrapping MethodChannel |
| `mobile/lib/withdraw/withdraw_notify_service.dart` | Call native show; keep queue sync + inbox open-on-body-tap |
| `mobile/test/withdraw_native_notify_test.dart` | Channel arg encoding tests (mock handler) |
| `mobile/pubspec.yaml` + `clip_service.dart` `kAppVersion` + `release/version.json` | Bump mobile |

**Out of scope:** PC/extension; changing relay `withdraw_notify` schema; FCM; replacing inbox UI; long retry windows.

---

### Task 1: Native receiver + notifier (Phase A — no custom layout yet)

**Files:**
- Create: `mobile/android/app/src/main/kotlin/com/clipsync/mobile_build/withdraw/ClipboardCopyReceiver.kt`
- Create: `mobile/android/app/src/main/kotlin/com/clipsync/mobile_build/withdraw/WithdrawalNotifier.kt`
- Modify: `mobile/android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: Add `ClipboardCopyReceiver`**

```kotlin
package com.clipsync.mobile_build.withdraw

// ACTION_COPY, EXTRA_TYPE, EXTRA_VALUE
// onReceive → ClipboardManager.setPrimaryClip(ClipData.newPlainText(...))
// API < 31: optional Toast.makeText(..., "คัดลอกแล้ว", SHORT)
// API >= 31: no custom toast
```

- [ ] **Step 2: Register in manifest**

```xml
<receiver
    android:name=".withdraw.ClipboardCopyReceiver"
    android:exported="false" />
```

Keep existing `flutterlocalnotifications.ActionBroadcastReceiver` for now (Phase A may still coexist briefly).

- [ ] **Step 3: Implement `WithdrawalNotifier.notify(context, data)`**

- `NotificationCompat.Builder(context, "withdraw_alerts")`
- `IMPORTANCE_HIGH` channel create-if-missing (same id/name as Flutter)
- `setContentTitle` / `setContentText` with amount + account summary
- `setStyle(BigTextStyle().bigText(...))` with emoji lines matching current Dart formatter **or** pass preformatted body string from Dart
- Two `addAction` with `PendingIntent.getBroadcast` → receiver; extras carry **exact** copy strings
- `requestCode = (transactionId + type).hashCode()` unique per action
- `FLAG_UPDATE_CURRENT or FLAG_IMMUTABLE`
- `setAutoCancel(false)`, `setOnlyAlertOnce` as today
- Notification id: stable from `transactionId` **or** keep fixed `41001` detail id if Dart still manages single-active notify (prefer **keep 41001 / 41000** to match current queue UX unless multi-notify is required)

- [ ] **Step 4: Compile check**

```bash
cd mobile
# from repo flutter sdk
flutter build apk --debug   # or at least :app:compileDebugKotlin
```

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(android): native ClipboardCopyReceiver + WithdrawalNotifier (phase A)"
```

---

### Task 2: MethodChannel plugin + Dart wrapper

**Files:**
- Create: `mobile/android/.../withdraw/WithdrawNotifyPlugin.kt`
- Modify: `mobile/android/.../MainActivity.kt`
- Create: `mobile/lib/withdraw/withdraw_native_notify.dart`
- Test: `mobile/test/withdraw_native_notify_test.dart`

- [ ] **Step 1: Channel contract**

```text
channel: com.clipsync.mobile_build/withdraw_notify

show({
  orderId: String,
  amount: String,      // clipboard + display
  account: String,     // clipboard + display
  bank: String,
  accountName: String,
  body: String,        // preformatted BigText from Dart
  title: String,       // default รายการถอนใหม่
  canCopy: bool,
  headsUp: bool,
  pendingCount: int,
}) -> void

cancel({ id: int }) -> void
cancelAll() -> void
```

- [ ] **Step 2: Failing Dart test** — method call encoding

```dart
test('WithdrawNativeNotify.show sends expected map', () async {
  // Mock MethodChannel; expect invokeMethod('show', {...})
});
```

- [ ] **Step 3: Implement Dart + Kotlin plugin; register in `MainActivity` like `SlipObserverPlugin`**

- [ ] **Step 4: `flutter test test/withdraw_native_notify_test.dart`**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(mobile): MethodChannel for native withdraw notifications"
```

---

### Task 3: Wire `WithdrawNotifyService` to native show (Phase A cutover)

**Files:**
- Modify: `mobile/lib/withdraw/withdraw_notify_service.dart`
- Modify: `mobile/test/withdraw_notify_service_test.dart` (keep pure helpers; integration via fake native)

- [ ] **Step 1: In `syncFromQueue`, when posting detail notify**

1. Build `body` with existing `formatWithdrawNotifyBody` (unchanged).
2. Call `WithdrawNativeNotify.show(...)` with amount/account for clipboard + `canCopy`.
3. **Stop relying on** `AndroidNotificationAction` + Dart `withdrawNotifyBackgroundResponse` for copy (can leave body-tap / inbox via FLN **or** move body tap to native `contentIntent` → open app with orderId — prefer: keep FLN **only** if still needed for launch details; simplest cutover = **native owns the detail notification entirely**).

Recommended cutover:

- Detail notify id `41001`: **native only**
- Summary group `41000`: keep FLN **or** native in same PR if easy; else leave FLN summary for Phase A.1

- [ ] **Step 2: Remove / no-op Dart background copy path for shade actions** once native owns actions (avoid double-handling)

- [ ] **Step 3: Body tap opens inbox**

- Native `contentIntent` → `MainActivity` with extra `order_id` → Flutter `getInitial*` / `onOpenWithdrawInbox` (mirror current `handleLaunchDetails`)

- [ ] **Step 4: Manual device checklist**

1. App foreground → copy amount/account → clipboard correct; notify stays.  
2. App backgrounded → same.  
3. Force-stop app → post notify via FGS path still works if FGS can call channel; if not, document that notify must be posted from FGS/main isolate before death (same as today).  
4. Android 12+ : system “Copied” only.  
5. Inbox still opens on body tap.

- [ ] **Step 5: Commit**

```bash
git commit -m "fix(mobile): post withdraw shade notify via native copy actions"
```

---

### Task 4: Phase B — custom expanded `RemoteViews` (optional cosmetics)

**Files:**
- Create: `res/layout/notification_withdraw_expanded.xml` (+ row includes if desired)
- Create: drawables `ic_copy`, outline button, row icons (reuse mipmap / simple vectors)
- Modify: `WithdrawalNotifier.kt` — `setCustomBigContentView` + `setOnClickPendingIntent` on buttons; keep `addAction` for collapsed

- [ ] **Step 1: Layout with RemoteViews-safe widgets only** (LinearLayout / TextView / ImageView / Button)

- [ ] **Step 2: Bind texts + same PendingIntents as actions**

- [ ] **Step 3: `DecoratedCustomViewStyle()` as appropriate; verify on 1 stock emulator + 1 OEM phone

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(android): custom expanded RemoteViews for withdraw notify"
```

---

### Task 5: Versions + release

**Files:**
- `mobile/pubspec.yaml` — bump (e.g. **0.9.10+36** or next after current)
- `mobile/lib/clip_service.dart` — `kAppVersion` **must match**
- `release/version.json` — android notes: native shade copy (BroadcastReceiver)

- [ ] **Step 1: Bump + notes**

- [ ] **Step 2: `flutter test` (withdraw_* ) + debug APK smoke**

- [ ] **Step 3: Push / CI when user requests build**

---

## Acceptance checklist

1. Shade **คัดลอกยอด** copies display amount (no `฿`) with app backgrounded.  
2. Shade **คัดลอกบัญชี** copies full account digits.  
3. Notify does **not** dismiss on first copy.  
4. Wrong value never appears when two notifies/actions exist (unique requestCodes).  
5. Inbox / queue still works; emoji body text unchanged.  
6. APK UI version matches pubspec.  
7. Phase B (if shipped): expanded card shows 3 rows + 2 buttons; collapsed still has two actions.

---

## Explicit non-goals

- Replacing Flutter inbox  
- Custom toast on Android 12+  
- Opening the app on copy button tap  
- Pure-Kotlin rewrite of WebSocket / queue  

---

## Suggested execution order

```text
Task 1 (Kotlin notify+receiver)
  → Task 2 (MethodChannel)
  → Task 3 (Dart cutover + device QA)
  → Task 5 (bump)     // ship Phase A here if shade copy is the fire
  → Task 4 (RemoteViews)  // Phase B polish
```

---

## Plan-only status

**Do not implement until the user says to proceed.**  
When proceeding, confirm whether to ship **Phase A only** first (recommended) or A+B in one PR.

# ClipSync — แจ้งเตือนมือถือ (Withdraw + Slip Status)

> **สถานะ:** แผนเท่านั้น — **ยังไม่เริ่ม implement**  
> **เกต auto-confirm:** ✅ ผู้ใช้ยืนยันแล้วว่า auto-confirm ใช้งานได้ (audit มี `auto_confirmed` โดย `system`) — **อนุญาตจัดคิวงานได้แล้ว** แต่ยังไม่ลงโค้ดจนกว่าผู้ใช้ OK เริ่มเฟส  
> Mockups (Phase A): `artifacts/withdraw-notify-mockups/withdraw-notify-heads-up.png`, `…/withdraw-notify-expanded.png`  
> Bubble (`withdraw-bubble-optional.png`) = **นอกสcope v1**  
> **แทร็กแยก:** แพ็ก Chrome extension เข้า Setup + Settings install helper — ดู [`2026-07-25-chrome-ext-setup-install.md`](./2026-07-25-chrome-ext-setup-install.md) (notify รอ/ไม่บล็อกกัน)

**Goal:**  
1. **Phase A** — พนักงานเห็นรายการถอนใหม่บนมือถือทันที พร้อมปุ่ม **คัดลอกยอด / คัดลอกบัญชี** (ปริมาณสูง ~10+/นาที ไม่จม notification)  
2. **Phase B** — หลังโอนแล้ว มือถือได้ **สถานะ pipeline สลิป** (โอนสำเร็จ → กำลังดำเนินการ → ปิดงานเรียบร้อย) โดยไม่ต้องพึ่ง FCM หนักใน v1  
3. **Safety (S)** — ลดความเสี่ยงโอนซ้ำ: หลังโอนสำเร็จแล้วต้องรู้ชัดว่าปิดงานได้หรือยัง และ **ซ่อน/ถอดรายการถอนนั้นออกจากคิวคัดลอก** เมื่อปิดงานสำเร็จ

**Architecture:**  
- Phase A: Jinbao scrape → ClipSync PC → relay typed message → Flutter local notification + inbox  
- Phase B: PC audit/orchestrator state changes → relay tiny JSON status events → phone notification channel (reuse always-on WS)  
- Safety: ผูกทุก notify / ปุ่มคัดลอกกับ **`order_id`** (fallback amount+account); PC slip/confirm status = source of truth; success ลบรายการจากคิวถอน

**Tech Stack:** Flutter (`flutter_local_notifications` หรือเทียบเท่า), Android channels/actions, PC Python, relay aiohttp, extension `pending_orders` + confirm path ที่มีอยู่แล้ว

---

## Milestone overview

| Phase | ชื่อ | สรุป | ลำดับ |
|---|---|---|---|
| **G0** | Gate | auto-confirm เสถียร — **ผ่านแล้ว** | ✅ |
| **S0** | Safety advice | ยอมรับแนว anti double-transfer (เอกสารนี้ §12) — **ยังไม่โค้ด** | รอ OK จากผู้ใช้ |
| **A** | Withdraw copy-notify | แจ้งรายการถอน + คัดลอกยอด/บัญชี | ทำก่อนหรือคู่ขนานกับ B ได้; แนะนำ A ก่อนถ้า bandwidth จำกัด |
| **B** | Slip status notify | สถานะ pipeline หลังมีสลิป → จบงาน | จัดคิวได้แล้ว; implement หลัง OK จากผู้ใช้ |
| **S1+** | Anti double-pay wiring | ผูกคิวถอนกับ status / ซ่อนปุ่มหลังโอน / fail ดัง | ทำคู่กับ A+B หรือทันทีหลัง B (ดู §12.4) |
| — | Bubble / FCM cloud | นอกสcope v1 | เลื่อน |
| — | Chrome Setup install | แทร็กแยก — ไม่บล็อก notify | ดูแผน chrome-ext-setup |

---

## 1) คำตอบสำคัญ: Heads-up + Expanded เป็นฟีเจอร์เดียวกันไหม?

**ใช่ — เป็น notification เดียวบน Android** (ใช้กับ Phase A เป็นหลัก; Phase B ใช้ channel แยกหรือ notification ID แยก)

| มุมมองใน mockup | สิ่งที่ Android ทำจริง |
|---|---|
| **A — Heads-up** | แบนเนอร์เด้งชั่วคราวเมื่อมี priority สูง (IMPORTANCE_HIGH + category เหมาะสม) ขณะหน้าจอเปิดอยู่ |
| **B — Expanded shade** | รายการเดียวกันในแถบแจ้งเตือน หลังดึงลง / กดขยาย — โชว์รายละเอียด + action buttons |

- ไม่ต้องทำ 2 ระบบแยก — สร้าง **หนึ่ง Notification** ที่มี title/body + **action** `คัดลอกยอด` / `คัดลอกบัญชี`
- ความต่างของ mockup A vs B = โหมดแสดงผล (peek vs expanded layout) ไม่ใช่ feature คนละตัว
- ข้อจำกัด: UI แบบ “การ์ดมีไอคอนแถวละเอียด” ใน mockup B อาจทำได้ครบด้วย BigText / Inbox / custom RemoteViews — v1 ยอมรับ layout ใกล้เคียง (title + บรรทัดยอด/บัญชี/ธนาคาร·ชื่อ + 2 ปุ่ม) ไม่ต้อง pixel-perfect ทุก OEM

**สรุปให้ผู้ใช้:** เลือก A+B พร้อมกันได้ และในทางเทคนิคคือ **ฟีเจอร์เดียว**

---

## 2) ขอบเขต v1 (แนะนำ)

### Phase A — รวมใน v1
- Android notification ตาม mockup A+B (notification only)
- ปุ่ม **คัดลอกยอด** / **คัดลอกบัญชี** บน notification
- คิวรายการถอนในแอป (inbox ง่าย ๆ) เมื่อมีหลายรายการ
- กลยุทธ์ high-throughput (ด้านล่าง)
- สิทธิ์ / channel แจ้งเตือน
- Payload โครงสร้าง: amount, account, bank, name, order_id

### Phase B — รวมใน v1 (สถานะสลิป)
- Local / in-app notification เมื่อ phone↔PC **เชื่อม relay อยู่แล้ว** (FGS + WS เดิม)
- ข้อความสถานะภาษาไทยตามขั้น pipeline (ดู §11)
- อัปเดต notification เดิมของงานนั้น (coalesce) — ไม่ spawn ใบใหม่ทุก hop
- Map จาก audit/log states ที่มีอยู่แล้ว

### นอกสcope v1 (ทั้ง A และ B)
- Bubble / overlay ทับแอปแบงก์ (mockup C)
- Auto-paste เข้าช่องในแอปธนาคาร
- iOS
- **FCM / push เมื่อแอปถูกฆ่าและไม่มี FGS** (Phase B v1 = best-effort ตอน service/WS ยังรัน)
- เปลี่ยน flow OCR → auto-confirm (ใช้ของเดิมต่อหลังโอน)

---

## 3) High-throughput UX (~10+ รายการ/นาที) — Phase A

ปัญหา: ถ้าเด้ง heads-up ทีละใบทุก order จะรก ปุ่มคัดลอกชี้ผิดรายการง่าย

### แนวทางที่แนะนำ (v1)

1. **Active order = รายการล่าสุดที่ยังไม่ matched / ยังไม่ถูก dismiss**  
   - ปุ่มคัดลอกบน notification **เสมอชี้ไปที่ active order**  
   - เมื่อมีใบใหม่ → active เลื่อนไปใบใหม่ล่าสุด (FIFO ของ “ยังไม่เคลียร์” แต่ UI โฟกัสที่ newest)

2. **Notification stacking แบบ summary + detail**  
   - **Detail notification (ID คงที่หรือ group child ล่าสุด):** แสดง active order เต็มรูปแบบ + 2 ปุ่มคัดลอก  
   - **Summary / group header:** เช่น `รายการถอนรอโอน · 7 รายการ` เมื่อคิว > 1  
   - อัปเดต notification เดิมแทนการ spawn ไม่จำกัด (ลด spam heads-up)

3. **Heads-up throttle**  
   - เด้ง heads-up เต็มรูปแบบเมื่อ: คิวว่าง → มีใบแรก หรือ ผู้ใช้เคลียร์แล้วมีใบใหม่  
   - ถ้ามาถี่มากภายในหน้าต่างสั้น (เช่น < 3–5 วินาที): **อัปเดตเนื้อหา in-place** + อัปเดตตัวเลขนับใน summary แทนการเด้งซ้ำทุกใบ

4. **Inbox ในแอป**  
   - รายการรอโอนทั้งหมด (เรียงใหม่→เก่า)  
   - แตะรายการ = ตั้งเป็น active + อัปเดต notification  
   - คัดลอกยอด/บัญชีต่อแถวได้  
   - เคลียร์เมื่อ PC/matcher แจ้ง matched/confirmed หรือผู้ใช้ปัดทิ้ง (กำหนดกติกาชัดใน implement)

5. **คัดลอกเมื่อมีหลายใบ**  
   - ไม่มีปุ่มคัดลอก “แบบสุ่ม” — ชัดเจนว่าคัดลอกของ **active**  
   - หลังคัดลอก: toast สั้น ๆ เช่น `คัดลอกยอด 100.00 แล้ว` (ระบุยอด/ท้ายบัญชีเพื่อยืนยันว่าถูกใบ)

---

## 4) Data flow — Phase A (withdraw)

```
Jinbao (หลังบ้าน)
  → Chrome extension: pending_orders (scrape/API ที่มีอยู่)
  → ClipSync PC: normalize order
  → Relay: action ใหม่ (แนะนำชื่อ withdraw_order / withdraw_notify)
  → มือถือ: เก็บคิว + แสดง/อัปเดต notification
```

หลังโอน: flow เดิมไม่เปลี่ยน — สลิป OCR → `slip_event` → PC match → auto-confirm  
แล้ว **Phase B** แจ้งสถานะตาม §11

### Fields ที่มือถือต้องได้ (Phase A v1)

| Field | ใช้แสดง / ใช้คัดลอก | หมายเหตุ |
|---|---|---|
| `order_id` | ระบุรายการ / dedupe | จาก scrape (`order_id` / `ref`) |
| `amount` | แสดง + คัดลอกยอด | string รูปแบบแสดง เช่น `100.00` |
| `account` | แสดง + คัดลอกบัญชี | เลขเต็มถ้ามี; fallback last4 + บอกชัด |
| `bank` | แสดงบรรทัดธนาคาร | `bank` / `bank_name_th` |
| `account_name` / `name` | แสดงชื่อบัญชี | ถ้า scrape ยังไม่มี → ว่างได้ชั่วคราว |
| `ts` / `received_at` | เรียงคิว | |

### Relat กับระบบเดิม
- `clip` เดิม = ข้อความล้วน → ยังใช้ได้สำหรับ clipboard sync ทั่วไป  
- **อย่า** ยัด withdraw ลง `clip` เป็น plain text อย่างเดียว — ต้องมี **typed message** เพื่อปุ่มคัดลอกแยกยอด/บัญชี และคิวหลายใบ  
- PC ตอนนี้ normalize เหลือประมาณ `order_id`, `amount`, `account_last4`, `bank` — ต้องขยายให้ส่ง **เลขบัญชีเต็ม + ชื่อ** ถ้า scrape มี (และอัปเดต extension fields ถ้ายังขาด)

### ไฟล์ที่น่าจะแตะตอน implement (อ้างอิง worktree)

| ส่วน | ไฟล์โดยประมาณ | Phase |
|---|---|---|
| Relay | `server/relay_server.py` (+ tests) | A + B |
| PC push | `pc/clipsync/orchestrator.py`, `bootstrap.py` / transport ที่ส่ง PC→phone | A + B |
| Extension scrape | `pc/chrome-extension/` + profile jinbao (fields บัญชี/ชื่อ) | A |
| Extension confirm | audit / confirm success path ที่มีอยู่ | B (emit เท่านั้น) |
| Mobile | `mobile/lib/clip_service.dart` (WS handler), notification helper, inbox UI | A + B |
| Manifest | มี `POST_NOTIFICATIONS` อยู่แล้ว — ตรวจ runtime request บน Android 13+ | A + B |
| Versions | bump mobile `pubspec` + `kAppVersion`, `release/version.json` (+ PC/relay ถ้าแตะ) | ตาม surface ที่แตะ |

---

## 5) Copy actions — Phase A

| ปุ่ม | พฤติกรรม |
|---|---|
| **คัดลอกยอด** | `Clipboard` ← amount ของ active order (ตัวเลขพร้อมทศนิยมตามที่แสดง) |
| **คัดลอกบัญชี** | `Clipboard` ← เลขบัญชี (digits-only หรือรูปแบบที่ร้านใช้โอน — ตัดสินตอน implement ให้ตรงแอปแบงก์) |

- ทำงานได้ทั้งจาก notification action (background) และจาก inbox ในแอป  
- ไม่ auto-paste เข้าแอปแบงก์ใน v1

---

## 6) Permissions & channels

| รายการ | รายละเอียด |
|---|---|
| `POST_NOTIFICATIONS` | มีใน manifest แล้ว — ต้อง **ขอ runtime** บน Android 13+ ถ้ายังไม่เคย grant สำหรับ channel ใหม่ |
| Channel Phase A | เช่น `withdraw_alerts` — **IMPORTANCE_HIGH** (heads-up), แยกจาก channel `clipsync` ของ foreground service (LOW) |
| Channel Phase B | เช่น `slip_status` — **IMPORTANCE_DEFAULT หรือ HIGH** (ตัดสินตอน implement: สำเร็จขั้นสุดท้ายอาจ HIGH; ขั้นกลาง DEFAULT เพื่อลดรบกวน) |
| Sound / vibration | Phase A: ตาม default; ลดได้ถ้าดังเกินตอน 10+/นาที — Phase B: เสียงเฉพาะ terminal success/fail แนะนำ |
| Battery / FGS | ยังพึ่ง foreground service + WS เดิมเพื่อรับ event ตอนแอปไม่เปิด UI |

---

## 7) เฟสงาน + ประมาณ effort

> **เกต auto-confirm ผ่านแล้ว** — เริ่มโค้ดได้เมื่อผู้ใช้สั่งเริ่มเฟส (แผนนี้ยังไม่ใช่ใบสั่ง implement)

### Phase A — Withdraw copy-notify

| เฟส | งาน | ประมาณ |
|---|---|---|
| **A1 — Protocol** | นิยาม payload + relay route PC→phone + tests | ~0.5–1 วัน |
| **A2 — PC emit** | เมื่อมี pending order ใหม่ (diff จาก snapshot ก่อนหน้า) → push ไป phone; รวม fields | ~1 วัน |
| **A3 — Mobile notify** | Channel + notification + 2 actions คัดลอก + อัปเดต active | ~1–1.5 วัน |
| **A4 — Queue UX** | Summary/group + throttle + inbox ในแอป | ~1 วัน |
| **A5 — Polish / QA** | OEM ต่าง ๆ, permission flow, ปริมาณสูงจำลอง, bump version + APK | ~0.5–1 วัน |

**รวม Phase A:** ประมาณ **4–5.5 วันทำงาน**

### Phase B — Slip status notify

| เฟส | งาน | ประมาณ |
|---|---|---|
| **B1 — Event map** | ผูก orchestrator/audit transitions → `slip_status` payload + tests | ~0.5 วัน |
| **B2 — PC→relay emit** | ส่ง event ขนาดเล็กตอน state เปลี่ยน (ไม่ส่งรูปซ้ำ) | ~0.5 วัน |
| **B3 — Mobile status UI** | Channel + อัปเดต notification เดิมตาม `job_id`/`order_id` | ~0.5–1 วัน |
| **B4 — Anti-spam + QA** | coalesce, throttle, fail path, bump version | ~0.5 วัน |

**รวม Phase B:** ประมาณ **2–2.5 วันทำงาน** (ต่ำ–กลาง เพราะ reuse WS/relay)

**รวม A+B หลังเกต:** ประมาณ **6–8 วัน** ถ้าทำต่อเนื่อง

---

## 8) เกต & สิ่งที่ยังไม่ทำ

### เกต (อัปเดต)
- [x] ผู้ใช้ยืนยันว่า **auto-confirm ใช้งานได้** (สนาม/audit — ผ่านแล้ว)
- [ ] ผู้ใช้ OK **แนว Anti double-transfer (S0 / §12)** — เอกสารอย่างเดียวจนกว่าจะสั่ง
- [ ] ผู้ใช้ OK **เริ่ม implement** Phase A และ/หรือ Phase B (+ S1–S3 ตามแผน)
- [ ] แผนนี้ได้รับการ OK ขอบเขต v1 (notification only, ไม่มี bubble / ไม่บังคับ FCM)

### Out of scope v1 (ทบทวน)
- Bubble overlay ทับแอปแบงก์  
- Auto-paste / Accessibility fill เข้าแอปธนาคาร  
- Pixel-perfect RemoteViews ทุกยี่ห้อ  
- แทนที่ระบบ `clip` เดิม  
- FCM เมื่อ process ถูกฆ่า (อาจเป็น Phase C ภายหลังถ้าต้องการ offline wake)  
- Jinbao “already approved” suppress (S5 — later)  
- Chrome Setup install (แทร็กแยก)

---

## 9) Acceptance คร่าว ๆ (หลัง implement)

### Phase A
1. มีรายการถอนใหม่บน Jinbao → มือถือเด้ง heads-up ภายในเวลาที่ยอมรับได้ (WS online)  
2. ดึงแถบแจ้งเตือน → เห็นรายละเอียด + ปุ่มคัดลอกยอด/บัญชี  
3. กดคัดลอก → clipboard ถูกต้องตาม active order  
4. ส่ง 10+ รายการ/นาทีจำลอง → ไม่แตกเป็น notification ล้นจอ; มีตัวนับ/summary; คัดลอกยังชี้ active ที่ชัดเจน  
5. เปิดแอป → เห็น inbox รายการรอโอน  
6. Bubble ยังไม่มีใน build

### Phase B
1. มีสลิปเข้า pipeline → มือถือได้สถานะ **โอนเงินสำเร็จ** (หรือเทียบเท่า) เมื่อ WS online  
2. ระหว่าง match/confirm → อัปเดตเป็น **กำลังดำเนินการ — อย่าโอนซ้ำ** (ไม่เด้ง spam หลายใบ)  
3. extension ยืนยันสำเร็จ → **ปิดงานเรียบร้อย** และรายการถอนของ `order_id` นั้น **หายจากคิวคัดลอก** (S1)  
4. confirm/match fail → **ไม่สำเร็จ: reason** ดังชัด; ไม่ silent re-queue เป็น withdraw ใหม่ (S3)  
5. ปริมาณสูง: ไม่เกิด notification 10+ ใบ/นาทีจาก status hops — หนึ่งใบต่องาน อัปเดต in-place  
6. ไม่พึ่ง FCM ใน v1; ถ้าตัด WS/FGS → ไม่รับสถานะ (ยอมรับใน v1)

---

## 10) ทางเลือกที่พิจารณาแล้ว (สั้น) — Phase A

| ทางเลือก | ข้อดี | ข้อเสีย | ตัดสินใจ |
|---|---|---|---|
| A) Notification เดียวอัปเดตเนื้อหา | เรียบ, ไม่รก | ดูประวัติใบเก่ายากถ้าไม่มี inbox | **ฐาน v1 + inbox** |
| B) หนึ่ง notification ต่อ order | ครบทุกใบใน shade | พังที่ 10+/นาที | ไม่ใช้เป็นหลัก |
| C) ใช้แค่ `clip` ข้อความ | โค้ดน้อย | ไม่มี 2 ปุ่ม / คิว | ไม่พอ |

---

## 11) Phase B — Status notifications (slip pipeline)

> **คำแนะนำที่รวมเข้าแผนแล้ว** — ยังไม่ implement

### 11.1 ความยาก / เน็ต / แนวทางที่แนะนำ

| หัวข้อ | คำตอบ |
|---|---|
| **ความยาก** | **ต่ำ–กลาง** — reuse relay WebSocket phone↔PC ที่มีอยู่แล้ว ไม่ต้องสร้างระบบ push ใหม่ทั้งก้อน |
| **อินเทอร์เน็ต** | **แทบไม่เพิ่ม** — event เป็น JSON เล็กมาก (สิบ–ร้อยไบต์); ช่องทาง WS เปิดค้างอยู่แล้วเพื่อ sync/สลิป — status ping ไม่ใช่รูป |
| **แนวทาง v1** | PC ยิง status event → relay → มือถือแสดง/อัปเดต **local notification** เฉพาะตอนเชื่อมอยู่ (FGS + WS) — **ไม่บังคับ FCM** ใน v1 |
| **เมื่อไรค่อย FCM** | ถ้าภายหลังต้องการปลุกเครื่องตอนแอปถูกฆ่าจริง ๆ ค่อยเป็น Phase C — ไม่บล็อกคุณค่าหลักตอนร้านใช้งานคู่กับ PC |

### 11.2 ข้อความที่ผู้ใช้ต้องการ (UI)

| ลำดับ | ข้อความบนมือถือ | ความหมาย |
|---|---|---|
| 1 | **โอนเงินสำเร็จ** | จับสลิปได้ / ตรวจพบการโอนแล้ว (มือถือมีสลิปอยู่แล้ว; อาจรวมยืนยันว่า PC รับสลิปแล้ว) |
| 2 | **กำลังดำเนินการ — อย่าโอนซ้ำ** | PC กำลัง match และ/หรือ ส่ง confirm ไป extension |
| 3 | **ปิดงานเรียบร้อย** | extension สำเร็จ (`ยืนยันสำเร็จ` / equivalent) → **ลบรายการถอนนี้ออกจากคิว** (ดู §12) |

ทางเลือก fail (แนะนำใส่ v1): **ไม่สำเร็จ: {reason}** — อัปเดต notification เดิม + สั่งเช็ก Jinbao/PC ก่อนโอนซ้ำ — **ห้าม** เงียบหายหรือโผล่เป็นใบถอนใหม่ (ดู §12)

### 11.3 Map กับ audit / log states (แนวทาง)

ผูกกับ state ที่มีใน orchestrator / audit — ชื่อจริงตอน implement ดูจากโค้ด แต่ mapping เป้าหมายประมาณนี้:

| ขั้น UI | Trigger ฝั่ง PC (แนว) | หมายเหตุ |
|---|---|---|
| โอนเงินสำเร็จ | สลิปเข้ามา / `slip` received · OCR พร้อม · เริ่มคิว match | มือถือส่งสลิปอยู่แล้ว — event นี้คือ “PC รับแล้ว / เริ่มงาน” |
| กำลังดำเนินการ | เข้า pending / auto path · match พบ · `confirm_sent` ไป extension | **รวม hops กลางเป็นขั้นเดียวบน UI** เพื่อไม่ spam |
| ปิดงานเรียบร้อย | extension success · audit `auto_confirmed` / confirmed by `system` | terminal success |
| (fail) | match miss · confirm fail · timeout | terminal fail — แจ้งชัด |

### 11.4 Data flow — Phase B

```
Phone: slip capture / OCR upload (ของเดิม)
  → PC: receive slip → match → confirm_sent → extension result
  → ที่แต่ละ transition ที่เลือก: emit slip_status { job_id, order_id?, amount?, stage, ts }
  → Relay: forward ไป phone session
  → Phone: อัปเดต notification ID คงที่ต่อ job (หรือต่อ order_id)
```

**อย่า** ส่งภาพสลิปซ้ำใน status event — แค่ metadata สถานะ

### 11.5 Payload คร่าว ๆ (ร่าง)

```json
{
  "action": "slip_status",
  "job_id": "...",
  "order_id": "...",
  "amount": "1464.00",
  "stage": "received | processing | done | failed",
  "message_th": "กำลังดำเนินการ",
  "ts": 0
}
```

- `stage` เป็น enum คงที่; `message_th` ใส่ได้เพื่อให้มือถือแสดงตรงข้อความที่ตกลงโดยไม่ hard-code ทุกเคส  
- Dedupe key = `job_id` (หรือ `order_id` ถ้าไม่มี job)

### 11.6 Anti-spam (สำคัญ — สนามมีหลายงาน/นาที)

ปัญหา: ถ้าทุก hop ของ matcher/OCR/confirm เด้ง heads-up จะรกพอ ๆ กับ withdraw 10+/นาที

### แนวทางที่แนะนำ (v1)

1. **หนึ่ง notification ต่องาน** — อัปเดต title/body in-place ตาม `stage`  
2. **Coalesce ขั้นกลาง** — hops ระหว่าง received → confirm_sent แสดงเป็น **กำลังดำเนินการ** ใบเดียว (ไม่เด้งทุก sub-step)  
3. **Heads-up น้อย** — แนะนำเด้งชัดเจนเฉพาะ:  
   - เข้าขั้นแรก (โอนเงินสำเร็จ / PC รับแล้ว) **หรือ**  
   - ขั้น terminal (ปิดงานเรียบร้อย / fail)  
   - ขั้น “กำลังดำเนินการ” = อัปเดตเงียบหรือ priority ต่ำกว่า  
4. **Throttle** — ถ้า stage เดิมซ้ำภายในหน้าต่างสั้น → no-op  
5. **แยก channel จาก withdraw** — ไม่ปนปุ่มคัดลอกของ Phase A กับสถานะ Phase B

### 11.7 Relat Phase A vs Phase B

| | Phase A Withdraw | Phase B Status |
|---|---|---|
| เวลาเกิด | **ก่อน** โอน (มี order รอ) | **หลัง** มีสลิป / ระหว่างปิดงาน |
| เป้าหมาย | คัดลอกยอด·บัญชี เร็ว | รู้ว่างานไปถึงไหนแล้ว |
| Spam risk | สูง (หลาย order/นาที) | กลาง (หลาย hop ต่องาน) — แก้ด้วย coalesce |
| Transport | typed relay event | typed relay event (คนละ `action`) |
| FCM | ไม่จำเป็น v1 | ไม่จำเป็น v1 |

ทำ **A แล้ว B** หรือ **B เล็ก ๆ ก่อน** ก็ได้ถ้าผู้ใช้ต้องการ feedback หลัง auto-confirm ก่อน — แต่ reuse notification helper / channel setup จากเฟสที่ทำก่อนจะคุ้มกว่า

### 11.8 สิ่งที่ยังไม่ทำใน Phase B v1

- Push ตอนแอปถูก force-stop / ไม่มี FGS  
- ประวัติสถานะยาวใน UI (พอมี notification + log ในแอปสั้น ๆ)  
- รวม Phase A+B เป็น notification เดียว (แยกชัดเจนกว่า)  
- (Anti double-pay เต็มรูปแบบ → ดู §12; ส่วน notify ขั้นพื้นฐานของ B ยังทำได้ก่อน S1)

---

## 12) Anti double-transfer / safety

> **สถานะ:** คำแนะนำ + แผนเท่านั้น — **ยังไม่ implement** (S0 = รอผู้ใช้ยอมรับแนวทาง)  
> **ความกลัวหลัก:** พนักงานโอนเงินสำเร็จแล้ว แต่ ClipSync **ปิดงานบน Jinbao ไม่สำเร็จ** → รายการถอนยังโผล่ / ยังคัดลอกได้ → **โอนซ้ำโดยไม่ตั้งใจ**

ปริมาณร้าน ~10 ถอน/นาที → ต้องพึ่ง **identity + queue state** ไม่ใช่แค่ข้อความแจ้งเตือนอย่างเดียว

### 12.1 Verdict (แนะนำ)

| คำถาม | คำตอบสั้น |
|---|---|
| Notify ช่วยกันโอนซ้ำได้ไหม? | **ช่วยได้มาก** ถ้าระบบ **เอาใบถอนออกจากคิวเมื่อปิดงานสำเร็จ** และตอน fail **ห้ามเงียบ / ห้ามโผล่เป็นใบถอนใหม่** |
| พอแค่ข้อความสถานะไหม? | **ไม่พอ** — ต้องผูกกับ `order_id` และตัดปุ่มคัดลอกหลังมีสลิป match |
| Source of truth คืออะไร? | **สถานะสลิป/confirm บน PC** (สำเร็จ / รอตรวจ / ล้มเหลว) ไม่ใช่ “พนักงานจำว่าโอนแล้ว” |
| ทำเมื่อไหร่? | ออกแบบคู่ A+B ตั้งแต่แรก; wire จริง = **S1 คู่กับ B** (หรือทันทีหลัง B) — ไม่รอ Phase C |

### 12.2 Recommended notify states (ผูก `order_id` / amount+account)

ทุกแถวด้านล่าง = **รายการเดียวกัน** อัปเดต in-place — ไม่สร้าง “ใบถอนใหม่” จาก fail

| State | Phone UX | ผลต่อคิวถอน (anti double-pay) |
|---|---|---|
| **pending withdraw** | แสดง copy card / heads-up + ปุ่มคัดลอกยอด·บัญชี | อยู่ในคิวรอโอน; เป็น active ได้ |
| **slip_received / processing** | อัปเดตใบเดิม: **กำลังดำเนินการ — อย่าโอนซ้ำ** | รายการนี้ **ไม่ใช่ “รอโอน” อีกแล้ว** — ปุ่มคัดลอกของ `order_id` นี้ **เทา / ซ่อน** |
| **confirm success** | **ปิดงานเรียบร้อย** (+ ยอดสั้น ๆ) | **ลบ/dismiss รายการถอนนั้นออกจากคิวและจาก withdraw notify** — ไม่เหลือปุ่มคัดลอกของใบนี้ |
| **confirm fail after slip** | **ไม่สำเร็จ: {reason}** + ข้อความชัด: **อย่าโอนซ้ำจนกว่าเช็ก Jinbao/PC** | **อย่า** เด้งกลับเป็น pending withdraw เงียบ ๆ; คงสถานะ fail ดัง; actions: **เปิดรายละเอียด** / **ยืนยันเองบน PC** |

**Success path (ที่ต้องการ):**  
โอนเงินสำเร็จ → กำลังดำเนินการ (อย่าโอนซ้ำ) → ปิดงานเรียบร้อย → **withdraw alert ของยอด/`order_id` นั้นหายจากคิว**

**Fail path (ที่ต้องการ):**  
โอนเงินสำเร็จ → กำลังดำเนินการ → **ไม่สำเร็จ: …** → สั่งให้ retry ระวัง / เช็กก่อนโอนใหม่ — **ไม่** คืนปุ่มคัดลอกอัตโนมัติจนกว่าจะ acknowledge หรือสถานะ PC เคลียร์

### 12.3 Other safety checks (นอก notify) — จัดอันดับแนะนำ

เรียงจาก **ต้องมีใน v1 / คู่ A+B** → optional ทีหลัง

| อันดับ | มาตรการ | ทำไมสำคัญที่ ~10/นาที |
|---|---|---|
| **1 (must)** | **Single active order identity (`order_id`)** — ปุ่มคัดลอกผูก id; success ลบ id นั้น | กันคัดลอกผิดใบ + กันใบที่ปิดแล้วยังคัดลอกได้ |
| **2 (must)** | **PC Slip status = source of truth** (สำเร็จ / รอตรวจ / ล้มเหลว) | พนักงานไม่ต้องเดาจากแอปแบงก์อย่างเดียว |
| **3 (must)** | หลัง OCR **match กับ order** → mark คิวมือถือ `transferred_awaiting_close` → copy UI **เทา/ซ่อน** | จุดกันโอนซ้ำเร็วสุด — เกิดก่อน confirm สำเร็จ/ล้ม |
| **4 (must)** | Failed close → **loud red alert**; **ห้าม** re-queue เงียบเป็น “รายการถอนใหม่” | Fail ที่ดูเหมือนใบใหม่ = สาเหตุโอนซ้ำอันดับต้น |
| **5 (optional v1.1)** | ต้อง **acknowledge fail** ก่อนแสดงปุ่มคัดลอกอีกครั้ง | บังคับหยุดคิดก่อนโอนรอบสอง |
| **6 (later)** | Jinbao scrape “already approved” → suppress notify / ลบคิว | กัน scrape ช้าหรือ race หลังปิดงาน |
| **7 (ops)** | Training copy: ไม่แน่ใจ → เช็ก **PC ประวัติ** / แท็บ approved บน Jinbao ก่อนโอนซ้ำ | ถูกที่สุดทันที ไม่รอฟีเจอร์ |

**หลักสั้น ๆ ให้ร้าน:**  
“มีสลิปแล้ว = **อย่าโอนซ้ำ** จนกว่า PC บอกปิดงานหรือบอก fail ชัด ๆ แล้วคุณเช็ก Jinbao แล้ว”

### 12.4 Safety milestones (แผน — ยังไม่โค้ด)

| Milestone | งาน | สถานะ |
|---|---|---|
| **S0** | ผู้ใช้ยอมรับแนว §12 (states + ranking + non-goals) | แผนเท่านั้น — รอ OK |
| **S1** | ผูก withdraw queue item กับ `order_id`; success → remove จากคิว + dismiss withdraw notify | ทำคู่ Phase B (หรือทันทีหลัง B3) |
| **S2** | ตอน match/slip_received → `transferred_awaiting_close` + ซ่อน/เทาปุ่มคัดลอก + ข้อความ “อย่าโอนซ้ำ” | คู่ B / หลัง S1 |
| **S3** | Fail path ดัง + reason + actions (เปิดรายละเอียด / ยืนยันบน PC); **ห้าม** silent re-queue | คู่ B4 |
| **S4** | (Optional) ต้องกด acknowledge ก่อน unlock คัดลอกอีกครั้ง | หลัง S1–S3 เสถียร |
| **S5** | (Later) scrape “already approved” suppress | ไม่บล็อก v1 |
| **S6** | (Ops) ข้อความอบรมสั้นในแอป/คู่มือร้าน | ทำได้ทันทีแม้ยังไม่โค้ดลึก |

**ลำดับแนะนำกับ A/B:** ออกแบบ protocol A1/B1 ให้มี `order_id` + stage ที่รองรับ S1–S3 ตั้งแต่แรก → implement สาย A → B พร้อม S1–S3 → S4/S5 ทีหลัง

### 12.5 Relat กับ Phase A / B

- Phase A อย่างเดียว **ไม่พอ**กันโอนซ้ำ (ยังไม่มีสัญญาณ “โอนแล้ว/ปิดงานแล้ว”)  
- Phase B อย่างเดียวช่วยรู้สถานะ แต่ถ้า **ไม่ลบคิวถอน** พนักงานยังกดคัดลอกใบเก่าได้  
- **Safety = สะพาน A↔B:** status event ต้องอัปเดต **ทั้ง** slip notify และ **สถานะรายการในคิวถอน**

### 12.6 Non-goals ของรอบ advice นี้

- ไม่เขียนโค้ด / ไม่เริ่ม Phase A หรือ B  
- ไม่รวมแพ็ก Chrome Setup install (แทร็กแยก)  
- ไม่บังคับ FCM / bubble / auto-paste  
- ไม่สัญญาว่ากันโอนซ้ำได้ 100% ถ้า WS ขาดตอน terminal event — v1 ยอมรับ best-effort + อบรมเช็ก PC/Jinbao

### 12.7 Acceptance คร่าว ๆ (เมื่อทำ S1–S3 แล้ว)

1. หลัง `confirm success` ของ `order_id` X → รายการ X **หายจากคิวถอน** และปุ่มคัดลอกของ X ใช้ไม่ได้  
2. หลัง slip match กับ X (ยังไม่ปิดงาน) → UI บอก **กำลังดำเนินการ — อย่าโอนซ้ำ** และคัดลอกของ X ถูกบล็อก  
3. Confirm fail ของ X → แจ้งแดงชัด + reason; **ไม่** โผล่เป็น withdraw ใหม่เงียบ ๆ  
4. ที่ ~10/นาที: identity ต่อใบชัด — ไม่สลับปุ่มคัดลอกไปใบที่กำลัง awaiting_close

---

## 13) สรุปสำหรับผู้ใช้ (ไทย — paste ได้)

- **สถานะแผน:** อัปเดตแล้ว (รวม §12 Anti double-transfer) — **ยังไม่เขียนโค้ด**  
- **เกต auto-confirm:** ผ่านแล้ว จัดคิว Phase A/B ได้ เมื่อสั่งเริ่ม  
- **ความกลัวโอนซ้ำ:** จริง — แก้ด้วย notify + **ลบคิวถอนเมื่อปิดงานสำเร็จ** + **ซ่อนคัดลอกหลังมีสลิป** + fail ดังห้าม re-queue เงียบ  
- **Phase A:** แจ้งรายการถอน + คัดลอกยอด/บัญชี  
- **Phase B:** โอนเงินสำเร็จ → กำลังดำเนินการ (อย่าโอนซ้ำ) → ปิดงานเรียบร้อย **หรือ** ไม่สำเร็จ: reason  
- **Safety S0–S3:** ออกแบบคู่ A+B; wire หลักคู่ B — รายละเอียด §12  
- **เช็กอื่นที่แนะนำ:** `order_id` เป็นหลัก → PC status เป็น truth → `transferred_awaiting_close` → fail ดัง → (optional) ack ก่อนคัดลอกใหม่ → (later) scrape approved → อบรมเช็ก PC/Jinbao  
- **ความยาก Phase B:** ต่ำ–กลาง (ใช้ WS/relay เดิม)  
- **เน็ต:** แทบไม่เพิ่ม (JSON เล็ก; ไม่ส่งรูปซ้ำ)  
- **แนะนำ:** ไม่ใช้ FCM ใน v1 — ส่งสถานะตอนเชื่อม PC อยู่แล้ว + อัปเดต notification เดิม ไม่เด้งทุก hop  
- **แทร็กแยก:** Chrome Setup install ไม่บล็อกงานนี้  

---

**แผนนี้พร้อมให้ผู้ใช้ยืนยันขอบเขต / เลือกลำดับ Phase A vs B และ OK แนว Safety (S0) — ยังไม่ลงมือเขียนโค้ด**

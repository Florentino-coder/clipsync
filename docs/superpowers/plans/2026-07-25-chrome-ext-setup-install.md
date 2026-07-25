# Chrome Extension — Bundle กับ Setup + Settings Install Helper (A+B)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.  
> **สถานะ:** แผนเท่านั้น — **ยังไม่เริ่ม implement** (ผู้ใช้ยืนยันแนว A+B แล้ว; รอสั่งเริ่มเฟส)  
> **Worktree แนะนำ:** `C:\Users\fluk3\Documents\New project\.worktrees\feat-slip-auto-confirm`

**Goal:** ให้พนักงานติดตั้ง Chrome extension จาก path ที่**คงที่และหาเจอง่าย** — Setup วาง/ทับโฟลเดอร์ให้ทุกครั้งที่ติดตั้ง, Settings มีปุ่มช่วย Copy path + เปิด `chrome://extensions`, อัปเดตครั้งถัดไปแค่ติดตั้ง Setup ใหม่แล้ว **Reload** ใน Chrome

**Architecture:**  
- **A — Setup:** Inno Setup คัดลอก `pc/chrome-extension/**` ไปยัง stable path และทับของเก่าทุกครั้งที่รัน Setup  
- **B — Settings helper:** ปุ่มในแท็บ Settings เรียก `guide_install` ที่ชี้ไปยัง stable path เดียวกัน (ไม่ใช่ `_internal` หรือข้าง EXE ชั่วคราว)  
- Chrome **ไม่รองรับ** silent install ของ unpacked extension — พนักงานต้อง Load unpacked ครั้งแรก / Reload ตอนอัปเดต

**Tech Stack:** Inno Setup (`.iss`), PyInstaller onedir/onefile, `pc/clipsync/ext_installer.py`, Tk Settings (`settings_panel.py`), Chrome MV3 unpacked extension

---

## Goal / Non-goals

### Goal
1. รวมโฟลเดอร์ `chrome-extension` เข้า **ClipSyncPC_Setup** และวางลง **path คงที่** ทุกเครื่อง
2. ปรับปรุง UX ติดตั้งใน **Settings** (แสดง path เต็ม, Copy, เปิด Chrome extensions, เรียก `guide_install`)
3. Flow อัปเดต: ติดตั้ง Setup ใหม่ → โฟลเดอร์เดิมถูก **overwrite in place** → พนักงานกด **Reload** ใน Chrome เท่านั้น
4. Pairing token + Push Site Profiles ยังใช้ได้หลัง Load unpacked / Reload ตามเดิม

### Non-goals (v1)
- Chrome Web Store publish / private store
- Silent / force-install unpacked extension (Chrome ไม่อนุญาต)
- Zip auto-update ของ extension แยกจาก Setup (มี hook ใน `ext_installer.check_extension_update` แล้ว — **เลื่อนเป็นเฟสถัดไป**)
- เปลี่ยน pairing / bridge protocol
- งาน withdraw-notify (แทร็กคนละเส้น — ดู pointer ท้ายไฟล์นั้น)

---

## Stable path decision

### เลือก path เดียว (ล็อกแล้ว)

```text
%AppData%\Roaming\ClipSync\chrome-extension\
```

ตัวอย่างเต็มบนเครื่องพนักงาน:

```text
C:\Users\<username>\AppData\Roaming\ClipSync\chrome-extension\
```

Inno equivalent: `{userappdata}\ClipSync\chrome-extension\`  
Python: `Path(os.environ["APPDATA"]) / "ClipSync" / "chrome-extension"`

### ทำไมไม่ใช้ `{app}\chrome-extension\` หรือ `_internal\`

| ตัวเลือก | ข้อดี | ข้อเสีย | ตัดสิน |
|---|---|---|---|
| **`%AppData%\Roaming\ClipSync\chrome-extension\`** | Path คงที่; Setup ทับที่เดิมได้; **portable EXE + Setup ชี้ path เดียวกัน** → Reload path ไม่เปลี่ยน; ไม่หายตอนย้ายโฟลเดอร์ EXE | ต้อง copy จาก bundle ตอน Setup / ครั้งแรกที่เปิดแอป (portable) | **เลือก** |
| `{app}\chrome-extension\` ภายใต้ install dir | อยู่กับแอป | Portable exe ใน Downloads ไม่ใช้ path นี้ → พนักงานมี 2 path; uninstall อาจสับสน | ไม่เลือก |
| `_internal\chrome-extension\` (สถานะปัจจุบันของ onedir) | ได้ฟรีจาก PyInstaller datas | Path ลึก พนักงานหาไม่เจอ; `guide_install` ที่มองข้าง EXE พลาด | เลิกใช้เป็น Load unpacked target |

### พฤติกรรมที่ต้องล็อก
- **Load unpacked ชี้ไปที่โฟลเดอร์นี้เท่านั้น** (มี `manifest.json` อยู่ระดับรากของโฟลเดอร์นี้)
- Setup ทุกครั้ง: **copy + overwrite** ทั้งต้นไม้ (flags ที่ทับไฟล์เก่า; ลบ orphan ในโฟลเดอร์ปลายทางถ้าจำเป็น — ระบุในเฟส A)
- Portable / onedir ที่ยังฝัง extension ใน `_internal` หรือข้าง exe: ใช้เป็น **แหล่งคัดลอก** ไปยัง stable path ไม่ใช่ path ที่ให้พนักงานเลือกใน Chrome
- `site_profiles_dir()` / Push Site Profiles: อ่าน profiles จาก stable path เป็นลำดับแรก (fallback ไป bundle/dev ตามเดิมได้)

---

## สภาพปัจจุบัน (baseline ที่แผนนี้แก้)

- PyInstaller ฝัง `chrome-extension` ผ่าน `ClipSyncPC.spec` → มักอยู่ใต้ `_internal\chrome-extension\`
- `guide_install()` ใน `ext_installer.py` ใช้ `extension_dir()` = **ข้าง EXE / `pc/`** — ไม่ตรง stable path
- Settings มี pairing token + Push Site Profiles — **ยังไม่มีปุ่มติดตั้ง extension**
- `pc/installer/ClipSyncPC.iss` ติดตั้งแค่ `{app}` จาก `dist\ClipSyncPC\*` — **ยังไม่มีขั้นตอน copy extension ไป AppData**
- Chrome ไม่สามารถ silent-install unpacked ได้ → ยังต้องมีขั้นตอนมือครั้งแรก

---

## ขั้นตอนสำหรับพนักงาน — ติดตั้งครั้งแรก (First-time)

> เป้าหมาย: พนักงานไม่ต้องไล่หาโฟลเดอร์ใน `_internal` หรือ Downloads

1. ติดตั้ง **ClipSyncPC_Setup.exe** (รันให้จบตาม wizard)
2. เปิด **ClipSync PC** → ไปแท็บ **Settings**
3. ในส่วน **Chrome extension** จะเห็น **path เต็ม** ของโฟลเดอร์  
   `...\AppData\Roaming\ClipSync\chrome-extension\`
4. กดปุ่ม **ติดตั้ง / เปิดคู่มือติดตั้ง** (เรียก `guide_install`)  
   - คัดลอก path เข้าคลิปบอร์ด  
   - เปิด `chrome://extensions`
5. ใน Chrome: เปิด **Developer mode**
6. กด **Load unpacked** → วาง path จากคลิปบอร์ด (หรือ Browse ไปโฟลเดอร์ที่ Settings แสดง) → เลือกโฟลเดอร์ `chrome-extension`
7. เปิด popup ของ ClipSync extension → วาง **pairing token** จาก Settings → Save
8. (ถ้าใช้ Site Profile) กด **Push Site Profiles → Extension** เมื่อ extension ขึ้น connected

**เสร็จ** — ครั้งถัดไปที่อัปเดตแอป ไม่ต้อง Load unpacked ใหม่

---

## ขั้นตอนสำหรับพนักงาน — อัปเดต (Update / Setup only → Reload)

> Path เดิมถูกรักษาไว้ → Chrome ยังชี้โฟลเดอร์เดิม; ไฟล์ข้างในถูกทับโดย Setup

1. ดาวน์โหลด / รัน **ClipSyncPC_Setup.exe** เวอร์ชันใหม่ (ติดตั้งทับ)
2. Setup **overwrite** โฟลเดอร์  
   `%AppData%\Roaming\ClipSync\chrome-extension\`  
   ให้ตรงกับ extension ในตัวติดตั้ง
3. เปิด Chrome → `chrome://extensions` (หรือกดปุ่มใน Settings ที่เปิดหน้านี้)
4. ที่การ์ด ClipSync กด **Reload** เท่านั้น
5. ตรวจว่า pairing ยังอยู่ + Push Site Profiles ยังใช้ได้ (ไม่ต้อง Load unpacked ใหม่)

**ไม่ต้อง:** ลบ extension เก่า, หาโฟลเดอร์ใหม่, คัดลอก zip มือ

---

## Approach A+B (สรุปเทคนิค)

| ส่วน | ทำอะไร |
|---|---|
| **A — Setup** | `[Files]` (หรือ `[Code]` / post-install) คัดลอก `chrome-extension\*` → `{userappdata}\ClipSync\chrome-extension\` ด้วย flags ทับของเก่า |
| **B — Settings** | UI แสดง path คงที่ + Copy path + Open chrome://extensions + ปุ่มที่เรียก `guide_install(stable_path)` |
| **Runtime** | `ext_installer.extension_dir()` / helper ใหม่คืน stable path; optional: ตอนสตาร์ทแอป ถ้า stable ว่างแต่มี bundle → sync ครั้งหนึ่ง (portable) |

---

## Implementation phases

### Phase 0 — ล็อกสัญญา path + ทดสอบย่อย (ไม่เปลี่ยน UX พนักงานยัง)

**Files:**
- Modify: `pc/clipsync/ext_installer.py`
- Modify / Create tests: `pc/tests/test_ext_installer.py`

- [ ] **Step 0.1:** เพิ่มค่าคงที่ เช่น `STABLE_EXTENSION_ROOT = Path(os.environ["APPDATA"]) / "ClipSync" / "chrome-extension"` (หรือฟังก์ชัน `stable_extension_dir()` ที่ mock ได้ในเทสต์)
- [ ] **Step 0.2:** แยกความหมาย:
  - `bundled_extension_dir()` = แหล่งในแอป (`_MEIPASS` / ข้าง exe / `pc/chrome-extension` ตอน dev)
  - `extension_dir()` / `stable_extension_dir()` = **path ที่ให้ Load unpacked** = AppData Roaming
- [ ] **Step 0.3:** เพิ่ม `ensure_stable_extension_installed(source=None)` — copytree จาก bundle → stable (dirs_exist_ok / ลบแล้วคัดลอกใหม่ถ้าเลือกแบบ clean overwrite)
- [ ] **Step 0.4:** `guide_install()` ใช้ stable path; ถ้ายังไม่มีโฟลเดอร์ ให้ `ensure_…` ก่อน แล้วค่อย copy clipboard + เปิด Chrome
- [ ] **Step 0.5:** อัปเดตเทสต์ path / guide_install / ensure overwrite
- [ ] **Step 0.6:** Commit เฟสนี้เมื่อเริ่ม implement

### Phase 1 — Inno Setup (A)

**Files:**
- Modify: `pc/installer/ClipSyncPC.iss`
- Verify: `pc/build_exe.ps1`, `pc/ClipSyncPC.spec` (ยัง bundle `chrome-extension` ใน onedir เพื่อเป็นแหล่งติดตั้ง)

- [ ] **Step 1.1:** เพิ่ม `[Files]` แยกจาก `{app}` เช่น  
  `Source: "..\dist\ClipSyncPC\chrome-extension\*"` (หรือ path ที่ onedir วางจริงหลัง build — ตรวจว่าอยู่ที่รากหรือ `_internal`)  
  `DestDir: "{userappdata}\ClipSync\chrome-extension"`  
  `Flags: ignoreversion recursesubdirs createallsubdirs`
- [ ] **Step 1.2:** ถ้าไฟล์อยู่ใน `_internal\chrome-extension` หลัง PyInstaller — ชี้ Source ให้ถูก **หรือ** ปรับ build ให้มีสำเนาที่ราก `dist\ClipSyncPC\chrome-extension` เพื่อ Source ชัดเจน (แนะนำให้มีที่รากเพื่อ Setup อ่านง่าย)
- [ ] **Step 1.3:** พิจารณา `[InstallDelete]` / `[Dirs]` สำหรับ orphan ไฟล์เก่าในปลายทางถ้าต้องการ clean overwrite ทั้งโฟลเดอร์ (ระวังไม่ลบข้อมูลอื่นภายใต้ `ClipSync\` นอก `chrome-extension`)
- [ ] **Step 1.4:** ทดสอบติดตั้งบนเครื่องสะอาด: หลัง Setup ต้องมี `manifest.json` ที่  
  `%AppData%\Roaming\ClipSync\chrome-extension\manifest.json`
- [ ] **Step 1.5:** ทดสอบติดตั้งทับ: เปลี่ยนไฟล์ในโฟลเดอร์ → รัน Setup ใหม่ → ไฟล์กลับเป็นของในตัวติดตั้ง

### Phase 2 — Settings UX (B)

**Files:**
- Modify: `pc/clipsync/ui/settings_panel.py`
- Modify: `pc/clipsync/legacy.py` (wire callback ถ้า Settings รับ `on_guide_install` แบบเดียวกับ `on_push_profiles`)
- Modify: `pc/tests/test_settings_panel.py` (หรือเทสต์ที่มีอยู่)

- [ ] **Step 2.1:** เพิ่มบล็อกใต้ pairing / ใกล้ Push Site Profiles:
  - หัวข้อภาษาไทย เช่น **ติดตั้ง Chrome extension**
  - Label แสดง **path เต็ม** (readonly / wrap)
  - ปุ่ม **คัดลอก path**
  - ปุ่ม **เปิด chrome://extensions**
  - ปุ่มหลัก **ติดตั้ง extension (Load unpacked)** → เรียก `guide_install`
- [ ] **Step 2.2:** คำอธิบายสั้นภาษาไทย: ครั้งแรกใช้ Load unpacked; อัปเดตครั้งถัดไปติดตั้ง Setup แล้วกด Reload
- [ ] **Step 2.3:** ไม่แตะ pairing token / Push Site Profiles นอกจากจัด layout ให้ชัดว่า “หลัง Load แล้วค่อย pair / push”
- [ ] **Step 2.4:** เทสต์ smoke: กดปุ่มเรียก mock ของ `guide_install` / copy path

### Phase 3 — Portable EXE parity (รองรับ path เดียวกัน)

**Files:**
- Modify: `pc/clipsync/ext_installer.py` และ/หรือจุดสตาร์ทใน `legacy.py` / `bootstrap.py`
- Optional note ใน `pc/chrome-extension/docs/CUSTOMER_ONBOARDING.md` หรือคู่มือพนักงานสั้น ๆ

- [ ] **Step 3.1:** ตอนเปิดแอป (frozen): ถ้า stable ยังไม่มี / เก่ากว่า bundle → `ensure_stable_extension_installed()` จาก `_MEIPASS` หรือ datas
- [ ] **Step 3.2:** Portable และ Setup ใช้ **path เดียวกัน** สำหรับ Load unpacked / Reload
- [ ] **Step 3.3:** เอกสารหนึ่งย่อหน้า: พนักงานที่ใช้แค่ portable ก็ได้ path เดียวกับคนใช้ Setup

### Phase 4 — CI / release / version bump

**Files:**
- Modify: workflow ที่ build `ClipSyncPC_Setup` (เช่น `.github/workflows/*` ที่เรียก `build_exe.ps1` + ISCC)
- Modify: `pc/installer/ClipSyncPC.iss` `#define MyAppVersion`
- Modify: PC `APP_VERSION` (ที่ `legacy.py` หรือโมดูล version ที่โปรเจกต์ใช้)
- Modify: `release/version.json` → `pc.version` + notes; เพิ่ม/อัปเดต `extension.version` ให้ตรง `pc/chrome-extension/manifest.json` ถ้ายังไม่มีในไฟล์ release

- [ ] **Step 4.1:** ยืนยัน artifact Setup มีขั้นตอน copy ไป `{userappdata}\ClipSync\chrome-extension`
- [ ] **Step 4.2:** Bump เวอร์ชัน PC + Setup ตามกฎ ClipSync (ทุกครั้งที่ ship)
- [ ] **Step 4.3:** ใส่ notes สั้น: “Setup installs Chrome extension to %AppData%\\Roaming\\ClipSync\\chrome-extension; Settings guide_install; update = Setup + Reload”
- [ ] **Step 4.4:** (ถ้าแตะ manifest extension ในรอบเดียวกัน) bump `manifest.json` + `release/version.json` extension ด้วย

### Phase 5 — Docs พนักงาน + acceptance บนเครื่องจริง

**Files:**
- Modify หรือสร้างสั้น ๆ: คู่มือใน `pc/chrome-extension/docs/` หรือ README ย่อ (ไทย)
- Optional: ลิงก์จาก backlog

- [ ] **Step 5.1:** คัดลอก “ขั้นตอนครั้งแรก” + “ขั้นตอนอัปเดต” จากแผนนี้ลงคู่มือพนักงาน
- [ ] **Step 5.2:** รัน acceptance checklist ด้านล่างบนเครื่องจริง 1 เครื่อง

---

## File touch map (สรุป)

| ไฟล์ | บทบาท |
|---|---|
| `pc/installer/ClipSyncPC.iss` | Copy/overwrite extension → `{userappdata}\ClipSync\chrome-extension` |
| `pc/clipsync/ext_installer.py` | Stable path, ensure copy, `guide_install` ชี้ path จริง |
| `pc/clipsync/ui/settings_panel.py` | ปุ่ม + แสดง path + Copy + เปิด Chrome |
| `pc/clipsync/legacy.py` (และ/หรือ bootstrap) | Wire callback; optional sync ตอนสตาร์ท |
| `pc/ClipSyncPC.spec` / `pc/build_exe.ps1` | คง bundle เป็นแหล่ง; จัดตำแหน่ง Source ให้ Setup ชัด |
| `pc/tests/test_ext_installer.py`, `test_settings_panel.py` | ครอบคลุม path + UX hooks |
| `release/version.json` + PC/iss version | Bump เมื่อ ship |
| `pc/chrome-extension/docs/*` | คู่มือพนักงาน (ขั้นตอนไทย) |

---

## Acceptance criteria

1. หลังรัน Setup ใหม่บนเครื่องสะอาด มีโฟลเดอร์  
   `%AppData%\Roaming\ClipSync\chrome-extension\` และมี `manifest.json` ถูกต้อง
2. Settings แสดง **path เต็ม** ตรงกับโฟลเดอร์นั้นทุกครั้ง (ไม่ใช่ `_internal\...`)
3. ปุ่มติดตั้งเรียก `guide_install` → path ถูก copy + เปิด `chrome://extensions`
4. พนักงาน Load unpacked จาก path นั้นได้; pairing token + Push Site Profiles ทำงานหลัง connected
5. รัน Setup ทับเวอร์ชันใหม่ → ไฟล์ในโฟลเดอร์เดิมถูกอัปเดต → กด **Reload** ใน Chrome พอ (ไม่ต้อง Load unpacked ใหม่)
6. Portable EXE (ถ้ายังรองรับ) ใช้ **path เดียวกัน** หลัง sync
7. ไม่มี silent install / ไม่พึ่ง Web Store ใน v1
8. เวอร์ชัน PC/Setup/`release/version.json` ถูก bump ในรอบที่ ship

---

## Out of scope

- Chrome Web Store / enterprise force-install policy
- Silent install unpacked extension
- Zip auto-update จาก `version.json` `download_url` (อาจเป็น Phase ภายหลัง; Setup + Reload เป็นช่องทางหลักของพนักงานตอนนี้)
- เปลี่ยน UX pairing นอกจากจัด layout ใกล้ปุ่มติดตั้ง
- Withdraw / slip notify บนมือถือ (แทร็กแยก)

---

## ความเสี่ยงและหมายเหตุ

- **Chrome จำ path โฟลเดอร์** ของ unpacked — ถ้าย้าย path หลัง Load แล้ว พนักงานต้อง Load unpacked ใหม่หนึ่งครั้ง; ดังนั้น **ห้ามเปลี่ยน stable path** หลัง ship โดยไม่มี migration note
- Uninstall แอป: ตัดสินใจตอน implement ว่าจะลบ `{userappdata}\ClipSync\chrome-extension` หรือทิ้งไว้ (แนะนำ v1: **ไม่ลบ** ตอน uninstall เพื่อไม่พัง Reload path โดยไม่ตั้งใจ — ระบุใน `.iss` ถ้าเพิ่ม uninstall delete)
- สิทธิ์: Setup ใช้ `PrivilegesRequired=lowest` อยู่แล้ว — เขียนใต้ `%AppData%` ของ user ได้โดยไม่ต้อง admin

---

## สรุปสั้นสำหรับผู้ใช้ (ไทย)

- **ทำอะไร:** แพ็ก Chrome extension เข้า Setup + ปุ่มช่วยติดตั้งใน Settings  
- **เก็บที่ไหน:** `%AppData%\Roaming\ClipSync\chrome-extension\` (path คงที่)  
- **ครั้งแรก:** Setup → Settings → ปุ่มติดตั้ง → Load unpacked  
- **อัปเดต:** Setup ใหม่ (ทับโฟลเดอร์เดิม) → Chrome **Reload** เท่านั้น  
- **ไฟล์แผน:** `docs/superpowers/plans/2026-07-25-chrome-ext-setup-install.md`  
- **ยังไม่เขียนโค้ดแอป** จนกว่าจะสั่งเริ่มเฟส

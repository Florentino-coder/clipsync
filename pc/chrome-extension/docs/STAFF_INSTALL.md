# ติดตั้ง Chrome extension สำหรับพนักงาน (ClipSync PC)

Path คงที่ (ทุกเครื่อง / Setup + portable เหมือนกัน):

```text
%AppData%\Roaming\ClipSync\chrome-extension\
```

ตัวอย่าง: `C:\Users\<username>\AppData\Roaming\ClipSync\chrome-extension\`

## ติดตั้งครั้งแรก

1. ติดตั้ง **ClipSyncPC_Setup.exe** ให้จบ wizard
2. เปิด **ClipSync PC** → แท็บ **Settings**
3. ในส่วน **ติดตั้ง Chrome extension** จะเห็น **path เต็ม** ของโฟลเดอร์ด้านบน
4. กด **ติดตั้ง extension (Load unpacked)** (คัดลอก path + เปิด `chrome://extensions`)
5. ใน Chrome: เปิด **Developer mode** → **Load unpacked** → วาง path / Browse ไปโฟลเดอร์ `chrome-extension`
6. เปิด popup ของ ClipSync → วาง **pairing token** จาก Settings → Save
7. (ถ้าใช้ Site Profile) กด **Push Site Profiles → Extension** เมื่อ extension ขึ้น connected

## อัปเดต (Setup → Reload)

1. รัน **ClipSyncPC_Setup.exe** เวอร์ชันใหม่ (ทับติดตั้ง)
2. Setup **overwrite** โฟลเดอร์ `%AppData%\Roaming\ClipSync\chrome-extension\`
3. เปิด `chrome://extensions` (หรือกดปุ่มใน Settings)
4. ที่การ์ด ClipSync กด **Reload** เท่านั้น
5. ตรวจ pairing + Push Site Profiles ยังใช้ได้

**ไม่ต้อง** ลบ extension เก่า / Load unpacked ใหม่ / หาโฟลเดอร์ `_internal`

## Portable EXE

เปิดแอปครั้งแรก (หรือหลังอัปเดต) จะ sync extension จาก bundle ไป path เดียวกันด้านบน — ใช้ Load unpacked / Reload เหมือนคนที่ติดตั้ง Setup

# HR Line Agent PoC

ระบบแชทบอทลางาน เช็ควันลาคงเหลือ เช็ค Job Description ผ่าน LINE OA และระบบหลังบ้าน Next.js Dashboard สำหรับ HR อนุมัติวันลาและสถิติรายงาน

บอทตัวนี้รันอยู่บน **Infrastructure ร่วม** กับ `Law-digitalize-PoC` (PostgreSQL 18, n8n v2.26.8, Ollama, Cloudflare tunnel)

---

## ฟีเจอร์หลัก (Key Features)
1. **ขอลาหยุดผ่าน LINE**: พนักงานสามารถพิมพ์แจ้งลางานแบบภาษาธรรมชาติได้ (Ollama qwen3.6 คอยสกัดข้อมูล ประเภทวันลา, วันที่เริ่ม-สิ้นสุด, เหตุผล) หรือกดปุ่มฟอร์มลางานทีละขั้นตอน
2. **สถิติวันลาคงเหลือ**: แสดงผลแถบพลัง (Progress Bar) วันลาป่วย, ลาพักร้อน, ลากิจ ผ่าน Flex Message ที่สวยงาม
3. **เช็คขอบข่ายงาน (Job Description)**: พนักงานพิมพ์ "ขอดู Job Description" หรือ "งานของฉันคืออะไร" เพื่อแสดงหน้าที่และขอบเขตงานสะสม
4. **ดูประวัติเพื่อนร่วมงาน (Staff Scope)**: ตรวจสอบสถานะการทำงานของเพื่อนร่วมทีมแผนกเดียวกันในวันนี้ (ว่าใครอยู่ทำงาน หรือใครลาป่วย/ลาพักร้อนวันนี้)
5. **สลับบัญชีผู้ใช้สะดวกสำหรับ PoC**: พิมพ์คำสั่ง `/switch <employee_code>` ในแชท LINE เพื่อเปลี่ยนโปรไฟล์ผู้ใช้งานทดสอบได้อย่างอิสระ (เช่น สลับเป็นผู้บริหาร, พนักงานทั่วไป, หรือทีม HR)
6. **HR Admin Dashboard Web UI (Next.js)**: 
   - ระบบ Report วันลาสะสมตามแผนก
   - หน้าจอสรุปคำขอหยุดงาน (Total, Pending, Approved, Rejected)
   - ฟังก์ชันอนุมัติ/ปฏิเสธแบบเรียลไทม์ และรองรับการเลือกบัญชีเจ้าหน้าที่ HR หลายคนเพื่อทดสอบ Context การลงชื่ออนุมัติ (`approved_by`)

---

## โครงสร้างโปรเจกต์ (Project Layout)
```
hr-line-agent/
├── README.md                # คู่มือการใช้งานและการติดตั้ง
├── .env.example             # ตัวแปรระบบตัวอย่าง
├── db/
│   ├── init.sql             # SQL Schema (employees, leave_requests, user_sessions)
│   └── seed.sql             # ข้อมูลทดสอบพนักงาน 5 คน หลายบทบาท
├── n8n/
│   └── flows/
│       └── hr-agent-bot.json # n8n JSON Template บอร์ดเชื่อมต่อ LINE และ DB
└── web-admin/               # ส่วนเว็บบอร์ดหลังบ้าน (Next.js 15, Tailwind, TS)
    ├── .env.local           # ข้อมูลเชื่อมต่อ DB ท้องถิ่น
    └── ...
```

---

## ขั้นตอนการติดตั้งและเตรียมทดสอบ (Setup Runbook)

### 1. ตั้งค่าฐานข้อมูล PostgreSQL
รันสคริปต์เพื่อสร้างฐานข้อมูล `hr_db` และโหลดข้อมูลพนักงานพร้อมประวัติขอลาหยุดตัวอย่าง:
```bash
# 1. สร้าง DB (รันแล้วในการเริ่มต้นโปรเจกต์)
PGPASSWORD=contractpw psql -h localhost -U contract -d contracts -c "CREATE DATABASE hr_db;"

# 2. นำเข้า Schema และข้อมูลตัวอย่าง (Seeding)
PGPASSWORD=contractpw psql -h localhost -U contract -d hr_db -f db/init.sql
PGPASSWORD=contractpw psql -h localhost -U contract -d hr_db -f db/seed.sql
```

**รายชื่อพนักงานตัวอย่าง (สำหรับทดสอบสลับบทบาท):**
* `EMP001` - สมชาย ดีใจ (พนักงานทั่วไป - Senior Developer)
* `EMP002` - สมศรี รักงาน (ผู้จัดการทีม - Engineering Manager)
* `EMP003` - สมรักษ์ พารวย (เจ้าหน้าที่ HR - HR Specialist)
* `EMP004` - สมพงษ์ คล่องแคล่ว (พนักงานทั่วไป - HR Assistant)
* `EMP005` - วิภา พรประเสริฐ (เจ้าหน้าที่ HR ระดับสูง - HR Director)

---

### 2. ตั้งค่า Next.js Web Admin Dashboard
ส่วนเว็บบอร์ดถูกตั้งค่าให้เชื่อมต่อฐานข้อมูล `hr_db` โดยรันอยู่ในเครื่องที่พอร์ต `3000`:
```bash
# เข้าโฟลเดอร์ web-admin และรัน Server
cd web-admin
npm run dev
```
เปิดบราวเซอร์ไปที่: http://localhost:3000
* ด้านขวาบนจะมี Dropdown ให้สลับบัญชี HR (สมรักษ์ หรือ วิภา) เพื่อทดสอบสิทธิ์อนุมัติ
* รายงานวันลาจะสรุปยอดแสดงสถานะในทันทีเมื่อกดปุ่มอนุมัติ/ปฏิเสธ

---

### 3. ตั้งค่า n8n & LINE Webhook
1. เปิด n8n UI: https://n8n.jesadakorn.com
2. นำเข้า workflow จากไฟล์ `n8n/flows/hr-agent-bot.json` (ไปที่ Workflows -> Import from File)
3. สร้างหรือตั้งค่า Credentials:
   - **Postgres HR - localhost:5432**: ต่อไปที่ฐานข้อมูล `hr_db`
   - **LINE HR Bearer Auth**: นำ LINE Channel Access Token ของบอทตัวใหม่ไปกรอก
4. นำ Webhook URL จาก n8n ไปตั้งใน LINE Developers Console:
   - URL: `https://n8n.jesadakorn.com/webhook/hr-line-agent`
5. เปิดใช้งาน (Activate) Workflow ใน n8n

---

## วิธีการใช้งานแชท LINE ในช่วง PoC

1. **สลับบทบาทการทดสอบ**:
   พิมพ์ส่งข้อความไปหาบอทดังนี้:
   - `/switch EMP001` (เพื่อสวมบทบาท สมชาย)
   - `/switch EMP002` (เพื่อสวมบทบาท สมศรี ผู้จัดการ)
   - `/switch EMP003` (เพื่อสวมบทบาท สมรักษ์ HR)
2. **ขอดูหน้าที่งาน**: พิมพ์ว่า `"ขอดู job description ของฉัน"`
3. **ตรวจสอบวันลาเหลือ**: พิมพ์ว่า `"วันลาคงเหลือ"` หรือ `"ขอดูวันหยุดที่เหลือ"`
4. **ขอลางาน**: พิมพ์ลากดปุ่ม หรือพิมพ์แชทเป็นภาษาธรรมชาติ เช่น `"ผมอยากขอลาป่วยในวันพรุ่งนี้เพราะปวดท้องครับ"`
5. **อนุมัติใบลา**: สลับบทบาทเป็นผู้จัดการ (`EMP002`) หรือ HR (`EMP003`) แล้วพิมพ์คำว่า `"รายการรออนุมัติ"` บอทจะแสดงคำขอของลูกน้องและส่งการอนุมัติ/ปฏิเสธได้ทางแชท LINE ทันที

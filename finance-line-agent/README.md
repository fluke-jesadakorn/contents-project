# Account and Finance AI Agent (FinAgent PoC)

ระบบวิเคราะห์ บันทึก และอนุมัติค่าใช้จ่ายทางการเงินด้วย AI แบบมีระบบตรวจสอบความถูกต้อง (Corrective parsing) และระบุประเภทบัญชีตามความหมายเชิงภาษา (Semantic COA mapping) ผ่าน LINE OA และระบบหลังบ้าน Next.js Dashboard สำหรับแบ่งบทบาทการทำงาน (Staff, Accountant, Manager, Admin)

บอทตัวนี้รันอยู่บน **Infrastructure ร่วม** ในเครื่องโลคอล (PostgreSQL 18, n8n, local Ollama)

---

## 📂 โครงสร้างโปรเจกต์ (Project Layout)

```text
finance-line-agent/
├── README.md                 # คู่มือการใช้งานและการติดตั้ง
├── .env                      # การตั้งค่าโทเคน LINE (Local Config)
├── package.json              # ไฟล์กำหนด dependencies ระดับบนสุด
├── db/
│   ├── init.sql              # SQL Schema (users, roles, chart_of_accounts, expenses, pgvector)
│   ├── seed.sql              # ข้อมูลผู้ใช้งาน และผังบัญชีเบื้องต้น
│   ├── embed_coa.js          # สคริปต์ทำ Embedding ผังบัญชี (COA) ด้วย Ollama bge-m3
│   └── test_mapping.js       # สคริปต์ทดสอบการจำแนกประเภทบัญชีด้วยความหมายเวกเตอร์
├── n8n/
│   ├── README.md             # คู่มือการตั้งค่า flow ใน n8n
│   └── flows/
│       └── finance-agent-bot.json # n8n workflow สำหรับเชื่อม LINE, OCR, Embedding และ Postgres
└── web-admin/                # Next.js Dashboard สำหรับพนักงาน, นักบัญชี และผู้บริหาร
    ├── .env.local            # การตั้งค่าเชื่อมต่อฐานข้อมูลใน Next.js
    └── ...
```

---

## 🛠️ วิธีการติดตั้งและเตรียมการทดสอบ (Setup Runbook)

### 1. เปิดใช้งานฐานข้อมูล PostgreSQL และ pgvector
ฐานข้อมูลรันอยู่บนพอร์ตหลัก `localhost:5432` ของเครื่อง ให้รันคำสั่ง SQL สร้างฐานข้อมูล `finance_db` และเปิดใช้งาน extension สำหรับเก็บเวกเตอร์:

```bash
# 1. สร้างฐานข้อมูลใหม่
PGPASSWORD=contractpw psql -h localhost -U contract -d contracts -c "CREATE DATABASE finance_db;"

# 2. นำเข้า Schema และเปิดใช้งาน pgvector
PGPASSWORD=contractpw psql -h localhost -U contract -d finance_db -f db/init.sql
```

### 2. นำเข้าข้อมูลผังบัญชี (Seeding) & ทำ Embed
นำข้อมูลพนักงาน ผังบัญชีเบื้องต้นเข้าฐานข้อมูล และรันสคริปต์เรียก **Ollama** แปลงค่าชื่อบัญชี (เช่น *Salaries & Wages / เงินเดือนและค่าจ้าง*) ให้กลายเป็นเวกเตอร์ 1024 มิติด้วยโมเดล `bge-m3`:

```bash
# 1. นำเข้าข้อมูลดิบ
PGPASSWORD=contractpw psql -h localhost -U contract -d finance_db -f db/seed.sql

# 2. ติดตั้ง dependencies และแปลงคำให้เป็นเวกเตอร์
npm install
npm run embed
```

---

## 🧪 การทดสอบระบบจัดหมวดหมู่เชิงความหมาย (Semantic Mapping Test)
คุณสามารถตรวจสอบความแม่นยำในการจับคู่คำอธิบายรายการใบเสร็จกับรหัสบัญชีด้วยเวกเตอร์ (BGE-M3 Cosine Distance) ผ่านสคริปต์ทดสอบ:

```bash
node db/test_mapping.js
```
*ผลลัพธ์จะจำลองการหาคำสั่งซื้อภาษาไทยและอังกฤษ เช่น "ค่าแท็กซี่ไปพบลูกค้า" ➡️ จัดให้อยู่ในกลุ่ม `[510200] Travel & Transportation` เป็นต้น*

---

## 💻 การตั้งค่าและรัน Next.js Web Admin Dashboard
ส่วนแสดงผลหลังบ้านสำหรับนักบัญชีและผู้บริหารตรวจทานความถูกต้อง สามารถเปิดรันได้ดังนี้:

```bash
# 1. เข้าไปในโฟลเดอร์ web-admin
cd web-admin

# 2. รันแอปพลิเคชัน (ทำงานอยู่บนพอร์ต 3003)
npm run dev
```
เปิดบราวเซอร์ไปที่: **[http://localhost:3003](http://localhost:3003)**

---

## 👥 บทบาทผู้ใช้งานที่รองรับ (Supported Roles)

* **`EMP001` (สมชาย - Staff)**: ส่งเอกสารใบเสร็จเข้าระบบ
* **`EMP002` (สมศรี - Manager)**: ตรวจสอบสรุปแผนกและอนุมัติจ่ายเงิน
* **`EMP003` (สมรักษ์ - Accountant)**: ตรวจจับสมการเลขคลาดเคลื่อน (Corrective Workspace) และแก้ไขผังบัญชี
* **`EMP005` (วิภา - Executive / Admin)**: ตรวจสอบความถูกต้องและ Audit Trails

---

## 💬 วิธีการใช้งานแชท LINE ในช่วง PoC

1. **การสลับบทบาทในการแชท**:
   พิมพ์ส่งข้อความไปหาบอทดังนี้เพื่อสวมบทบาทเสมือน:
   * `/switch EMP001` (สลับเป็น สมชาย - พนักงานทั่วไป)
   * `/switch EMP003` (สลับเป็น สมรักษ์ - นักบัญชี)
   * `/switch EMP002` (สลับเป็น สมศรี - ผู้จัดการ)
2. **การส่งใบเสร็จล้างหนี้**:
   * ในบทบาทพนักงาน (`EMP001`) ถ่ายรูปภาพหรือส่งใบเสร็จเข้าไปในแชท
   * บอท n8n จะส่งภาพไปสกัดผ่าน Gemini Vision Node ➡️ คำนวณสมการตัวเลข ➡️ วิเคราะห์หมวดหมู่บัญชีด้วย Ollama ➡️ ส่ง Flex Message คอนเฟิร์มกลับไปให้พนักงาน
3. **การอนุมัติผ่าน LINE (สำหรับ Manager)**:
   * เมื่อนักบัญชียืนยันความถูกต้องแล้ว n8n จะส่งการแจ้งเตือนมาหาผู้จัดการ (`EMP002`) ทาง LINE OA พร้อมแสดงปุ่มอนุมัติ [Approve] / [Reject] บน Flex Card

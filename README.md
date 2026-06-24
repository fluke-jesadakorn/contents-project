# Contents Project Workspace

ยินดีต้อนรับสู่พื้นที่ทำงาน (Workspace) ของโครงการ **Contents Project** ซึ่งเป็นการรวมระบบ Proof of Concept (PoC) สองระบบหลักที่ทำงานร่วมกันบนโครงสร้างพื้นฐานภายในตัวเครื่อง (Local Infrastructure) เดียวกัน

---

## 📂 โครงสร้างระบบใน Workspace

พื้นที่ทำงานนี้แบ่งออกเป็น 3 ส่วนหลักๆ ดังนี้:

### 1. [Law-digitalize-PoC](file:///Users/fluke/Desktop/Work/Contents/Law-digitalize-PoC) (ระบบสืบค้นและจัดการเอกสารทางกฎหมาย)
ระบบค้นหาเอกสารสัญญาทางกฎหมายด้วยความสามารถของ AI (RAG - Retrieval-Augmented Generation) 
* **ฟีเจอร์**: อัปโหลดเอกสาร PDF กฎหมาย, ทำระบบดึงข้อความอัตโนมัติ (OCR via Native macOS Vision API), ค้นหาข้อมูลด้วยเวกเตอร์ค้นหา (Semantic Search) และมี Dashboard (Next.js) ให้ฝ่ายบริหารสืบค้นข้อมูล
* **โครงสร้างภายใน**: Next.js (Admin UI & Executive Presentation Deck), PostgreSQL (Vector extension), MinIO (Object Storage) และ n8n Workflows

### 2. [hr-line-agent](file:///Users/fluke/Desktop/Work/Contents/hr-line-agent) (ระบบบอทบริการฝ่ายบุคคล - HR LINE Bot & Dashboard)
ระบบช่วยพนักงานขอลาหยุดงาน เช็คสิทธิ์วันหยุดตนเอง และขอดูขอบข่ายงาน (Job Description) ผ่านแชทบอท LINE OA
* **ฟีเจอร์**: บันทึกคำขอลาหยุดเข้าฐานข้อมูล, ตรวจเช็คยอดวันลาด้วย Flex Message (แถบ Progress Bar คาดสีสวยงาม), ทำรายการแบบทีละขั้นตอน (State Machine / Slot Filling) รองรับข้อความธรรมชาติของพนักงาน และมี Next.js Dashboard หลังบ้านเพื่อให้ HR อนุมัติ/ปฏิเสธแบบเรียลไทม์
* **โครงสร้างภายใน**: Next.js Web Admin Portal, PostgreSQL (`hr_db`), n8n Workflows (พร้อมการดึงค่า Header Auth จาก Environment ตัวแปรระบบโดยตรงเพื่อไม่ให้ชนกับระบบอื่น)

### 3. [infra](file:///Users/fluke/Desktop/Work/Contents/infra) (โครงสร้างพื้นฐานและการจัดการระบบ)
รวบรวมไฟล์การตั้งค่าและ Daemon สคริปต์ที่รันระบบสนับสนุนทั้งหมดในเครื่อง macOS Host-native:
* **บริการภายใน**: 
  - **n8n** (พอร์ต `5678`): ระบบรัน Flow Orchestration อัตโนมัติ
  - **MinIO** (พอร์ต `9000` / Console `9001`): ระบบเก็บไฟล์สำหรับเอกสารสัญญากฎหมาย
  - **PostgreSQL 18** (พอร์ต `5432`): ฐานข้อมูลหลักของทั้งสองโปรเจกต์ (`lawpoc_n8n`, `hr_db`)
  - **OCR Native Service** (พอร์ต `8765`): บริการดึงข้อความจากภาพ/PDF ทำงานร่วมกันบนสคริปต์ Swift และ Node.js
* ** launchd plists**: การตั้งค่าไฟล์ Daemon ในตัว macOS เพื่อช่วยสตาร์ทและกู้คืนบริการให้อัตโนมัติ (`com.lawpoc.*`)

---

## 🛠️ การเปิดรันบริการทั้งหมดในเครื่อง (Startup Runbook)

บริการหลังบ้านทั้งหมดทำงานผ่าน `launchd` ของ macOS ซึ่งจะถูกสตาร์ทอัตโนมัติอยู่แล้วเมื่อเปิดเครื่อง หากต้องการควบคุมด้วยตนเอง:

```bash
# 1. ตรวจสอบสถานะการทำงานของบริการทั้งหมด
launchctl list | grep lawpoc

# 2. ตัวอย่างการสตาร์ท/รีสตาร์ทบริการ n8n
# (หรือสั่ง kill pid ของบริการแล้ว launchd จะทำการ respawn ให้อัตโนมัติเนื่องจากมี KeepAlive=true)
kill $(pgrep -f start-n8n.js)
```

### รายละเอียดพอร์ตการเชื่อมต่อโลคอล:
* **Next.js HR Admin**: http://localhost:3000
* **n8n Editor (HTTPS)**: https://n8n.jesadakorn.com (พอร์ตภายใน `5678`)
* **MinIO Console**: http://localhost:9001
* **PostgreSQL**: `localhost:5432`

---

## 📝 รายละเอียดโปรเจกต์เชิงลึก
กรุณาเปิดอ่านไฟล์ README ของแต่ละโปรเจกต์ย่อยสำหรับคู่มือและวิธีการตั้งค่าโดยละเอียด:
* **คู่มือระบบ HR**: [hr-line-agent/README.md](file:///Users/fluke/Desktop/Work/Contents/hr-line-agent/README.md)
* **คู่มือระบบสืบค้นกฎหมาย**: [Law-digitalize-PoC/README.md](file:///Users/fluke/Desktop/Work/Contents/Law-digitalize-PoC/README.md)

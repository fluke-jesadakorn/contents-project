# Smart Home LINE Agent (Nous Hermes local integration)

ระบบควบคุมและจัดการอุปกรณ์ภายในบ้านอัจฉริยะ (Smart Home Control Agent) ผ่าน LINE Messaging API โดยเชื่อมต่อกับ **Home Assistant (HA)** และรันผ่าน **Nous Hermes Agent** ในเครื่องโลคอล เพื่อความเป็นส่วนตัวสูงสุดและไม่ต้องผ่าน n8n workflow ซับซ้อน

บอทตัวนี้จะทำงานเป็น Gateway รับข้อความจาก LINE แล้วแปลงเป็น Action/Service เพื่อสั่งงานอุปกรณ์อัจฉริยะ (เช่น หลอดไฟ, ปลั๊กไฟ, สวิตช์, เครื่องปรับอากาศ) ในบ้านคุณได้ทันทีผ่านคำสั่งภาษาธรรมชาติ

---

## 🛠️ สถาปัตยกรรมระบบ (Architecture)

```
LINE User (In Group / DM)
   │
   │ ส่งข้อความ / @mention Agent
   ▼
LINE Messaging API
   │ Webhook (HTTPS)
   ▼
Cloudflare Tunnel / ngrok (Public HTTPS)
   │
   ▼
Local Hermes Agent (Port 8646)
   │
   ├─► [Inference] ──► OpenRouter / Local Ollama (ทำความเข้าใจภาษาธรรมชาติ)
   │
   └─► [Execution] ──► Home Assistant (REST API & WebSocket)
                        ├─► สอบถามสถานะ (ha_get_state)
                        ├─► เรียกใช้บริการ (ha_call_service)
                        └─► ค้นหาอุปกรณ์ (ha_list_entities)
```

---

## 📂 โครงสร้างโปรเจกต์ (Project Structure)

```
smarthome-line-agent/
├── README.md               # คู่มือการติดตั้งและการใช้งาน
├── .env.example            # เทมเพลตสำหรับกำหนดตัวแปรระบบ (LINE, Home Assistant, LLM)
├── .env                    # ตัวแปรระบบจริงสำหรับใช้งาน (Git-ignored)
└── run.sh                  # สคริปต์สั้นสำหรับรันบอทพร้อมโหลด Env
```

---

## 🚀 ขั้นตอนการติดตั้งและเตรียมพร้อมใช้งาน (Setup Guide)

### 1. ตั้งค่า LINE Messaging API
1. เข้าไปที่ [LINE Developers Console](https://developers.line.biz/)
2. สร้าง Provider และ Messaging API Channel ใหม่
3. ในแท็บ **Messaging API**:
   - บันทึก **Channel access token (long-lived)**
   - บันทึก **Channel secret** (อยู่ในแท็บ Basic settings)
    - เปิดใช้งานฟังก์ชัน Webhook และกรอก Webhook URL: `https://hermes.jesadakorn.com/webhook/line`
    - **สำคัญ**: เปิดฟังก์ชัน "Allow bot to join group chats" เพื่อดึงบอทเข้ากลุ่ม

### 2. สร้าง Long-Lived Access Token ใน Home Assistant
1. เปิดหน้าจอ Home Assistant ของคุณ
2. คลิกที่รูป **โปรไฟล์** มุมล่างซ้าย
3. เลื่อนลงไปล่างสุดในหัวข้อ **Long-Lived Access Tokens**
4. กด **Create Token** ตั้งชื่อว่า `Hermes Smart Home`
5. คัดลอกโทเคนเก็บไว้ (จะแสดงเพียงครั้งเดียว)

### 3. การเชื่อมต่อ Cloudflare Tunnel
เนื่องจากคุณใช้โดเมนส่วนตัว ระบบได้ตั้งค่าเชื่อมต่อในพื้นหลังเรียบร้อยแล้ว:
* **Webhook URL สำหรับกรอกใน LINE Developers Console**: `https://hermes.jesadakorn.com/webhook/line`
* ตัว Cloudflare Tunnel หลัก (`com.cloudflare.tunnel.n8n`) ได้ถูกอัปเดตไฟล์คอนฟิก `config-n8n.yml` ให้ส่งต่อทราฟฟิกของ `hermes.jesadakorn.com` ไปยังพอร์ต `localhost:8646` ของเครื่องคุณเรียบร้อยแล้ว และบริการของระบบ macOS (`launchd`) ได้ทำการ Restart เพื่อโหลดคอนฟิกใหม่ให้ทำงานทันที
* **ไม่ต้องรันคำสั่ง Tunnel เองแบบ manual** เนื่องจากมี Service รันอยู่เบื้องหลังใน macOS ให้ตลอดเวลา


---

## ⚙️ การตั้งค่า Environment Variables

สร้างไฟล์ `.env` โดยก๊อปปี้จาก `.env.example` และกรอกข้อมูลจริง:

```bash
# คัดลอกเทมเพลต
cp .env.example .env
```

แก้ไขฟิลด์สำคัญใน `.env` ดังนี้:
* `LINE_CHANNEL_ACCESS_TOKEN`: โทเคนจาก LINE Console
* `LINE_CHANNEL_SECRET`: ซีเคร็ตจาก LINE Console
* `LINE_REQUIRE_MENTION`: ตั้งค่าเป็น `true` เพื่อให้บอทตอบเฉพาะเมื่อถูก `@mention` ชื่อตัวเอเจนต์เท่านั้นในแชทกลุ่ม
* `LINE_BOT_NAME`: ระบุชื่อบอทของคุณสำหรับใช้ตรวจจับการ Mention
* `HASS_TOKEN`: โทเคนควบคุมอุปกรณ์จาก Home Assistant
* `HASS_URL`: ที่อยู่ของ Home Assistant ในวงแลนของคุณ (เช่น `http://homeassistant.local:8123`)
* `OPENROUTER_API_KEY`: API Key สำหรับประมวลผลข้อความ LLM

---

## 🏃 วิธีการรันบอท (Running the Agent)

เมื่อตั้งค่า `.env` เรียบร้อยแล้ว สามารถเริ่มรัน Hermes LINE Gateway ได้ด้วยคำสั่ง:

```bash
# ให้สิทธิ์รันสคริปต์
chmod +x run.sh

# รันเกตเวย์
./run.sh
```

บอทจะเริ่มทำงานและแสดงข้อความล็อกอินพร้อมรับ Webhook บนพอร์ต `8646`

---

## 💬 ตัวอย่างการสั่งงานบอทผ่าน LINE

บอทถูกจำกัดสิทธิ์ **(Gated)** ให้ประมวลผลเฉพาะตอนมี `@mention` ในกลุ่ม เพื่อไม่ให้บอทไปรบกวนบทสนทนาอื่นในบ้าน:

* **สอบถามสถานะอุปกรณ์**:
  * `[User]`: `@HomeBot ตอนนี้ไฟห้องนั่งเล่นเปิดอยู่ไหม?`
  * `[Bot]`: *(เรียกใช้ ha_get_state)* `ตอนนี้ไฟห้องนั่งเล่น (light.living_room) ปิดอยู่ครับ`
* **สั่งเปิด/ปิดอุปกรณ์**:
  * `[User]`: `@HomeBot ช่วยเปิดไฟห้องครัวให้หน่อย`
  * `[Bot]`: *(เรียกใช้ ha_call_service)* `เปิดไฟห้องครัวให้เรียบร้อยแล้วครับ!`
* **ปรับเครื่องปรับอากาศ**:
  * `[User]`: `@HomeBot ปรับแอร์ห้องนอนเป็น 25 องศาซิ`
  * `[Bot]`: *(เรียกใช้ ha_call_service)* `ปรับเครื่องปรับอากาศห้องนอน (climate.bedroom_ac) เป็น 25°C แล้วครับ`
* **เช็คอุณหภูมิเซนเซอร์**:
  * `[User]`: `@HomeBot อุณหภูมินอกบ้านเท่าไหร่แล้ว`
  * `[Bot]`: *(เรียกใช้ ha_get_state)* `ตอนนี้เซนเซอร์ภายนอกรายงานอุณหภูมิ 32.5°C ครับ`

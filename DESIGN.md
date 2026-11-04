# I’FEEW Massage & Wellness

## Design System v1.0

**Design Direction:** Warm Minimal · Clean · Modern · Wellness

**Design Principle:** เรียบง่าย สบายตา ดูอบอุ่น มีความเป็นมืออาชีพ และใช้งานง่ายทั้งบนมือถือและ Desktop

---

## 1. Brand Identity

**Brand Personality**

- Warm — อบอุ่น เป็นมิตร
- Calm — สงบ ผ่อนคลาย
- Natural — เป็นธรรมชาติ
- Professional — น่าเชื่อถือและเป็นมืออาชีพ
- Minimal — ใช้เท่าที่จำเป็น ไม่รกสายตา

**Visual Direction**

ใช้สีครีม น้ำตาล และสีเอิร์ธโทนเป็นหลัก พื้นที่ว่างต้องเพียงพอ ภาพประกอบควรสื่อถึงการพักผ่อนและการดูแลตัวเอง

## 2. Color Palette

### Primary Colors

| Token      | HEX       | Usage                  |
| ---------- | --------- | ---------------------- |
| Primary    | `#97714C` | ปุ่มหลัก, Active state |
| Brown      | `#B0885F` | สีตกแต่ง, Accent       |
| Brown Dark | `#64513E` | หัวข้อสำคัญ            |
| Text       | `#4D4238` | ข้อความหลัก            |

### Neutral Colors

| Token       | HEX       | Usage        |
| ----------- | --------- | ------------ |
| Background  | `#FAF8F3` | พื้นหลังหลัก |
| Surface     | `#FFFFFF` | Card, Modal  |
| Surface Alt | `#F6F1E9` | พื้นหลังรอง  |
| Border      | `#EAE2D4` | เส้นขอบ      |
| Border Soft | `#F1EBE0` | เส้นแบ่งบาง  |
| Muted Text  | `#6E6053` | ข้อความรอง   |

### Semantic Colors

| State   | Text      | Background |
| ------- | --------- | ---------- |
| Success | `#4A7D52` | `#EDF5ED`  |
| Warning | `#B28C4D` | `#FAF5E8`  |
| Danger  | `#C06A5C` | `#FAEEEB`  |

**Usage Rule:** ใช้ Primary เป็นสีเน้นหลัก ไม่ควรใช้สีน้ำตาลเข้มกับทุกองค์ประกอบ และไม่ใช้สีสถานะเป็นสีตกแต่งทั่วไป

## 3. Typography

**Primary Font:** Kanit

| Style   | Size |  Weight | Usage         |
| ------- | ---: | ------: | ------------- |
| Display | 32px | 500–600 | Hero Heading  |
| H1      | 28px |     500 | Page Title    |
| H2      | 22px |     500 | Section Title |
| H3      | 18px |     500 | Card Title    |
| Body    | 14px | 300–400 | เนื้อหาทั่วไป |
| Label   | 13px |     400 | Form Label    |
| Caption | 12px | 300–400 | ข้อความรอง    |
| Small   | 10px |     400 | Metadata      |

**Typography Rules**

- ใช้ Kanit เป็นฟอนต์หลักทั้งระบบ
- หัวข้อใช้ Weight 500 เป็นหลัก
- เนื้อหาใช้ Weight 300–400
- หลีกเลี่ยงตัวหนาหนักเกินความจำเป็น
- ใช้ Line Height ประมาณ 1.5–1.7

## 4. Spacing System

ใช้ระบบระยะห่างแบบ 4px scale

| Token    | Value |
| -------- | ----: |
| space-1  |   4px |
| space-2  |   8px |
| space-3  |  12px |
| space-4  |  16px |
| space-5  |  20px |
| space-6  |  24px |
| space-8  |  32px |
| space-10 |  40px |
| space-12 |  48px |
| space-16 |  64px |

**Layout Rules**

- ระยะห่างระหว่าง Section: 32–48px
- ระยะห่างภายใน Card: 20–24px
- ระยะห่างระหว่าง Form Fields: 16px
- ระยะห่างระหว่าง Label กับ Input: 8px

## 5. Border Radius & Elevation

### Radius

| Token       | Value | Usage                 |
| ----------- | ----: | --------------------- |
| radius-sm   |   8px | Input, Small Badge    |
| radius-md   |  12px | Button                |
| radius-lg   |  16px | Card                  |
| radius-xl   |  20px | Hero, Large Container |
| radius-full | 999px | Pill, Avatar          |

### Shadow

ใช้ Shadow อย่างประหยัด เพื่อให้หน้าจอดูสะอาด

- Card: `0 4px 16px rgba(100,81,62,0.05)`
- Floating Element: `0 16px 40px -16px rgba(100,81,62,0.15)`

## 6. Components

### Buttons

| Type      | Appearance              | Usage             |
| --------- | ----------------------- | ----------------- |
| Primary   | พื้นน้ำตาล ตัวอักษรขาว  | Action หลัก       |
| Secondary | พื้นครีม ตัวอักษรน้ำตาล | Action รอง        |
| Outline   | พื้นขาว เส้นขอบบาง      | Action ทั่วไป     |
| Ghost     | ไม่มีพื้นหลัง           | Action ที่ไม่เน้น |

**Button Height**

- Small: 32px
- Medium: 40px
- Large: 48px

ทุกปุ่มควรมี Hover, Active, Disabled State

### Input & Form

- ความสูง Input: 44–48px
- พื้นหลังสีขาว
- Border สี `#EAE2D4`
- Radius 8–12px
- Focus Border ใช้ Primary
- Error Message อยู่ใต้ Input

### Cards

- พื้นหลังขาว
- Border บาง หรือไม่มี Border
- Radius 16–20px
- Padding 20–24px
- ใช้ Shadow เฉพาะเมื่อจำเป็น

### Status Badge

- Success: สีเขียวอ่อน
- Pending: สีเหลืองอ่อน
- Cancelled: สีแดงอ่อน
- Processing: สีน้ำตาลอ่อน

ใช้ข้อความร่วมกับสีเสมอ ไม่ใช้สีเพียงอย่างเดียวในการสื่อสถานะ

### Tables

- Header พื้นหลังโปร่งหรือครีมอ่อน
- เส้นแบ่งแถวบาง
- Row Height ประมาณ 52–60px
- ตัวเลขและราคาเรียงแนวเดียวกัน
- ใช้ Status Badge สำหรับสถานะ

### Navigation

**Customer Website**

- Navigation เข้าใจง่าย
- ให้ความสำคัญกับบริการ สาขา และการจอง
- Mobile ใช้ Bottom Navigation ได้

**Management System**

- Sidebar สำหรับ Desktop
- Bottom Navigation เฉพาะเมนูหลักบน Mobile
- แบ่งกลุ่มเมนูตามหน้าที่
- Active Menu ใช้พื้นครีมและตัวอักษรน้ำตาล

## 7. Iconography

- ใช้ Icon สไตล์ Outline
- น้ำหนักเส้นสม่ำเสมอ
- ขนาดมาตรฐาน 18–20px
- หลีกเลี่ยงการใช้ Emoji ปะปนกับ Icon
- ใช้ Icon คู่กับข้อความในเมนูที่ผู้ใช้ใหม่อาจไม่เข้าใจ

## 8. Layout & Responsive

| Breakpoint |      Width | Layout         |
| ---------- | ---------: | -------------- |
| Mobile     |    ≤ 700px | Single Column  |
| Tablet     | 701–1050px | Compact Layout |
| Desktop    |   > 1050px | Full Layout    |

**Desktop**

- Header สูงประมาณ 72px
- Sidebar กว้างประมาณ 240–250px
- Main Content มี Padding 32px

**Mobile**

- Header สูงประมาณ 60–64px
- Content Padding 16px
- Card เต็มความกว้าง
- Form เรียง 1 Column
- ตารางควรเลื่อนแนวนอนได้เมื่อจำเป็น

## 9. Product Experience

### Customer Website

เป้าหมายคือให้ลูกค้าค้นหาบริการและจองคิวได้ง่ายที่สุด

ลำดับความสำคัญ:

1. Home
2. Services & Pricing
3. Branches
4. Booking
5. Booking Tracking
6. My Account

**Primary CTA:** จองคิว

### Management System

เป้าหมายคือช่วยให้พนักงานและเจ้าของร้านทำงานได้รวดเร็ว

ลำดับความสำคัญ:

1. Dashboard
2. POS
3. Queue Management
4. Bookings
5. Customers
6. Employees
7. Services
8. Resources
9. Finance & Reports
10. Expenses
11. Settings

**Primary CTA:** การทำงานที่เกี่ยวข้องกับคิวและการขายหน้าร้าน

## 10. Design Principles

1. **Less is More** — แสดงเฉพาะสิ่งที่จำเป็น
2. **Clear Hierarchy** — ผู้ใช้ต้องรู้ว่าควรมองตรงไหนก่อน
3. **Consistent Components** — Component เดียวกันต้องหน้าตาเหมือนกันทั้งระบบ
4. **Comfortable Spacing** — เว้นพื้นที่ให้หน้าจอหายใจ
5. **Functional First** — ความสวยต้องไม่ลดความสะดวกในการใช้งาน
6. **Responsive Always** — ทุกหน้าต้องใช้งานได้ดีบนมือถือ

---

**Design System Summary**

I’FEEW ใช้โทนสี Warm Neutral + Earth Tone, ฟอนต์ Kanit, Layout แบบ Minimal, Component ที่เรียบง่าย และใช้ Primary Brown เป็นจุดเน้น เพื่อสร้างประสบการณ์ที่อบอุ่นสำหรับลูกค้าและเป็นมืออาชีพสำหรับระบบจัดการร้าน

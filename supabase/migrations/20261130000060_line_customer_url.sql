-- URL จริงของแอปลูกค้า (ลิงก์ติดตามการจอง/ตรวจสอบการจองในข้อความ LINE) — แก้ต่อได้ที่ /settings/line
update private.line_settings set customer_url = 'https://bookingifeew.vercel.app' where customer_url is null;

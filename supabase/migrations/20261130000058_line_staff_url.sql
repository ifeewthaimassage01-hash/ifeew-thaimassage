-- URL จริงของแอปพนักงาน (ลิงก์ในข้อความแจ้งเตือนกลุ่ม LINE)
alter table private.push_config alter column staff_url set default 'https://staffifeew.vercel.app';
update private.push_config set staff_url = 'https://staffifeew.vercel.app';

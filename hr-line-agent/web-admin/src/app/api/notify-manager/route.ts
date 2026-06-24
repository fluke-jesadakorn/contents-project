import { NextResponse } from 'next/server';
import pool from '@/lib/db';

const LINE_API = 'https://api.line.me/v2/bot/message/push';

export async function POST(request: Request) {
  const client = await pool.connect();
  try {
    const { employeeId, employeeName, department, lineToken } = await request.json();

    if (!employeeId || !department) {
      return NextResponse.json({ success: false, error: 'Missing required fields' }, { status: 400 });
    }

    const token = lineToken || process.env.LINE_CHANNEL_ACCESS_TOKEN;
    if (!token) {
      return NextResponse.json({ success: false, error: 'No LINE token available' }, { status: 500 });
    }

    // Fetch the latest pending leave request for this employee
    const leaveRes = await client.query(
      `SELECT lr.leave_type, lr.start_date::text, lr.end_date::text, lr.days, lr.reason, lr.created_at::text
       FROM leave_requests lr
       WHERE lr.employee_id = $1 AND lr.status = 'pending'
       ORDER BY lr.created_at DESC LIMIT 1`,
      [employeeId]
    );
    const leave = leaveRes.rows[0];

    // Find manager or HR in same department (or any hr role as fallback)
    const managerRes = await client.query(
      `SELECT line_user_id, name FROM employees 
       WHERE (role = 'manager' AND department = $1) OR role = 'hr'
       AND line_user_id IS NOT NULL
       ORDER BY (role = 'manager' AND department = $1) DESC
       LIMIT 1`,
      [department]
    );

    if (managerRes.rows.length === 0) {
      return NextResponse.json({ success: false, error: 'No manager/HR found to notify' });
    }

    const manager = managerRes.rows[0];

    function leaveTypeLabel(t: string) {
      if (t === 'sick') return '🤒 ลาป่วย';
      if (t === 'annual') return '✈️ ลาพักร้อน';
      if (t === 'personal') return '💼 ลากิจ';
      return t;
    }

    const flexMessage = {
      type: 'flex',
      altText: `🔔 คำขอลาใหม่จาก ${employeeName}`,
      contents: {
        type: 'bubble',
        header: {
          type: 'box',
          layout: 'vertical',
          backgroundColor: '#4f46e5',
          contents: [
            { type: 'text', text: '🔔 คำขอลาใหม่', weight: 'bold', size: 'lg', color: '#ffffff' },
            { type: 'text', text: `รออนุมัติจากคุณ`, size: 'sm', color: '#c7d2fe' }
          ]
        },
        body: {
          type: 'box',
          layout: 'vertical',
          contents: [
            { type: 'text', text: `👤 ${employeeName}`, weight: 'bold', size: 'md' },
            { type: 'text', text: `แผนก: ${department}`, size: 'sm', color: '#64748b', margin: 'xs' },
            { type: 'separator', margin: 'md' },
            ...(leave ? [
              { type: 'box', layout: 'baseline', margin: 'md', contents: [
                { type: 'text', text: 'ประเภท:', size: 'sm', color: '#94a3b8', flex: 2 },
                { type: 'text', text: leaveTypeLabel(leave.leave_type), size: 'sm', weight: 'bold', flex: 3 }
              ]},
              { type: 'box', layout: 'baseline', margin: 'xs', contents: [
                { type: 'text', text: 'ระยะเวลา:', size: 'sm', color: '#94a3b8', flex: 2 },
                { type: 'text', text: `${leave.start_date} ถึง ${leave.end_date} (${leave.days} วัน)`, size: 'sm', weight: 'bold', flex: 3 }
              ]},
              { type: 'box', layout: 'baseline', margin: 'xs', contents: [
                { type: 'text', text: 'เหตุผล:', size: 'sm', color: '#94a3b8', flex: 2 },
                { type: 'text', text: leave.reason, size: 'sm', flex: 3, wrap: true }
              ]}
            ] : [
              { type: 'text', text: 'ไม่พบรายละเอียดใบลา', size: 'sm', color: '#94a3b8', margin: 'md' }
            ])
          ]
        },
        footer: {
          type: 'box',
          layout: 'vertical',
          contents: [
            {
              type: 'button',
              action: { type: 'uri', label: '📋 ดูและอนุมัติที่ Web Admin', uri: 'http://localhost:3000/hr' },
              style: 'primary',
              color: '#4f46e5'
            },
            { type: 'text', text: '- bot', size: 'xs', color: '#94a3b8', align: 'end', margin: 'xs' }
          ]
        }
      }
    };

    // Push message to manager
    const pushRes = await fetch(LINE_API, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
      },
      body: JSON.stringify({
        to: manager.line_user_id,
        messages: [flexMessage]
      })
    });

    if (!pushRes.ok) {
      const err = await pushRes.text();
      console.error('LINE push failed:', err);
      return NextResponse.json({ success: false, error: 'LINE push failed', detail: err }, { status: 500 });
    }

    return NextResponse.json({ success: true, notifiedManager: manager.name });

  } catch (error: unknown) {
    const errMsg = error instanceof Error ? error.message : String(error);
    console.error('notify-manager error:', errMsg);
    return NextResponse.json({ success: false, error: errMsg }, { status: 500 });
  } finally {
    client.release();
  }
}

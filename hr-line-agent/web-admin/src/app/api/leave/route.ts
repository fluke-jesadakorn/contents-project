import { NextResponse } from 'next/server';
import pool from '@/lib/db';

export async function POST(request: Request) {
  const client = await pool.connect();
  try {
    const { requestId, action, hrId, rejectReason } = await request.json();

    if (!requestId || !action || !hrId) {
      return NextResponse.json(
        { success: false, error: 'Missing required parameters: requestId, action, hrId' },
        { status: 400 }
      );
    }

    if (action !== 'approve' && action !== 'reject') {
      return NextResponse.json(
        { success: false, error: 'Invalid action. Must be "approve" or "reject"' },
        { status: 400 }
      );
    }

    if (action === 'reject' && (!rejectReason || !rejectReason.trim())) {
      return NextResponse.json(
        { success: false, error: 'Rejection reason is required' },
        { status: 400 }
      );
    }

    await client.query('BEGIN');

    // 1. Update the leave request status and approved_by
    const statusText = action === 'approve' ? 'approved' : 'rejected';
    const updateRequestRes = await client.query(
      `UPDATE leave_requests 
       SET status = $1, approved_by = $2, reject_reason = $3, updated_at = NOW() 
       WHERE id = $4 
       RETURNING employee_id, leave_type, days::float as days`,
      [statusText, hrId, action === 'reject' ? rejectReason : null, requestId]
    );

    if (updateRequestRes.rowCount === 0) {
      throw new Error('Leave request not found or not updated');
    }

    const { employee_id, leave_type, days } = updateRequestRes.rows[0];

    // 2. If approved, increment the corresponding used leave days for the employee
    if (action === 'approve') {
      let columnToUpdate = '';
      if (leave_type === 'sick') {
        columnToUpdate = 'used_sick_leave';
      } else if (leave_type === 'annual') {
        columnToUpdate = 'used_annual_leave';
      } else if (leave_type === 'personal') {
        columnToUpdate = 'used_personal_leave';
      } else {
        throw new Error(`Unknown leave type: ${leave_type}`);
      }

      const updateEmployeeQuery = `
        UPDATE employees 
        SET ${columnToUpdate} = ${columnToUpdate} + $1, updated_at = NOW() 
        WHERE id = $2
      `;
      await client.query(updateEmployeeQuery, [days, employee_id]);
    }

    await client.query('COMMIT');

    // 3. Send LINE notification push message to the employee (non-blocking)
    try {
      const infoRes = await client.query(
        `SELECT 
           (SELECT line_user_id FROM employees WHERE id = $1) as emp_line_id,
           (SELECT name FROM employees WHERE id = $2) as hr_name,
           start_date::text, end_date::text, leave_type, days::float as days
         FROM leave_requests WHERE id = $3`,
        [employee_id, hrId, requestId]
      );

      if (infoRes.rows.length > 0) {
        const { emp_line_id, hr_name, start_date, end_date, leave_type: type, days: numDays } = infoRes.rows[0];
        
        if (emp_line_id) {
          const leaveTypeThai = type === 'sick' ? '🤒 ลาป่วย' : type === 'annual' ? '✈️ ลาพักร้อน' : type === 'personal' ? '💼 ลากิจ' : type;
          let messageText = '';
          if (action === 'approve') {
            messageText = `✅ คำขอลาของคุณได้รับการอนุมัติแล้ว!\n\n📋 รายละเอียด:\n- ประเภท: ${leaveTypeThai}\n- ระยะเวลา: ${start_date} ถึง ${end_date} (${numDays} วัน)\n- ผู้อนุมัติ: ${hr_name}`;
          } else {
            messageText = `❌ คำขอลาของคุณถูกปฏิเสธ\n\n📋 รายละเอียด:\n- ประเภท: ${leaveTypeThai}\n- ระยะเวลา: ${start_date} ถึง ${end_date} (${numDays} วัน)\n- เหตุผลการปฏิเสธ: ${rejectReason}\n- ผู้พิจารณา: ${hr_name}`;
          }

          const lineToken = process.env.LINE_CHANNEL_ACCESS_TOKEN;
          if (lineToken) {
            fetch('https://api.line.me/v2/bot/message/push', {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${lineToken}`
              },
              body: JSON.stringify({
                to: emp_line_id,
                messages: [
                  {
                    type: 'text',
                    text: messageText
                  }
                ]
              })
            }).then(r => {
              if (!r.ok) {
                r.text().then(t => console.error('LINE Push API error response:', t));
              } else {
                console.log(`LINE Push message sent successfully to ${emp_line_id}`);
              }
            }).catch(e => console.error('Fetch error sending LINE Push message:', e));
          } else {
            console.warn('LINE_CHANNEL_ACCESS_TOKEN not configured in process.env');
          }
        }
      }
    } catch (infoErr) {
      console.error('Failed to query info for LINE push message:', infoErr);
    }

    return NextResponse.json({ success: true, status: statusText });
  } catch (error: any) {
    await client.query('ROLLBACK');
    console.error('Error processing leave decision:', error);
    return NextResponse.json(
      { success: false, error: error.message },
      { status: 500 }
    );
  } finally {
    client.release();
  }
}

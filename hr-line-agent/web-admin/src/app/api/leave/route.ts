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
       WHERE id = $4 AND status = 'pending'
       RETURNING employee_id, leave_type, days::float as days`,
      [statusText, hrId, action === 'reject' ? rejectReason : null, requestId]
    );

    if (updateRequestRes.rowCount === 0) {
      // Could be: not found, or already processed (not pending)
      const checkRes = await client.query(
        `SELECT status FROM leave_requests WHERE id = $1`,
        [requestId]
      );
      if (checkRes.rows.length === 0) {
        throw new Error('Leave request not found');
      }
      const currentStatus = checkRes.rows[0].status;
      throw new Error(`Cannot process: leave request is already "${currentStatus}" (ใบลานี้ได้รับการดำเนินการไปแล้ว)`);
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
          const isApproved = action === 'approve';
          const headerBg  = isApproved ? '#064e3b' : '#4c0519';
          const headerAccent = isApproved ? '#10b981' : '#f43f5e';
          const statusText = isApproved ? '✅ อนุมัติแล้ว' : '❌ ปฏิเสธแล้ว';
          const statusSub  = isApproved ? 'คำขอลาของคุณได้รับการอนุมัติ' : 'คำขอลาของคุณถูกปฏิเสธ';

          const flexRows: object[] = [
            { type: 'box', layout: 'horizontal', contents: [
              { type: 'text', text: 'ประเภท', size: 'sm', color: '#64748b', flex: 2 },
              { type: 'text', text: leaveTypeThai, size: 'sm', color: '#e2e8f0', weight: 'bold', flex: 3 },
            ]},
            { type: 'box', layout: 'horizontal', margin: 'sm', contents: [
              { type: 'text', text: 'ระยะเวลา', size: 'sm', color: '#64748b', flex: 2 },
              { type: 'text', text: `${start_date} – ${end_date} (${numDays} วัน)`, size: 'sm', color: '#e2e8f0', flex: 3 },
            ]},
            { type: 'box', layout: 'horizontal', margin: 'sm', contents: [
              { type: 'text', text: isApproved ? 'ผู้อนุมัติ' : 'ผู้พิจารณา', size: 'sm', color: '#64748b', flex: 2 },
              { type: 'text', text: hr_name, size: 'sm', color: '#e2e8f0', weight: 'bold', flex: 3 },
            ]},
          ];
          if (!isApproved && rejectReason) {
            flexRows.push({ type: 'separator', margin: 'md' });
            flexRows.push({ type: 'box', layout: 'horizontal', margin: 'md', contents: [
              { type: 'text', text: 'เหตุผล', size: 'sm', color: '#64748b', flex: 2 },
              { type: 'text', text: rejectReason, size: 'sm', color: '#fda4af', wrap: true, flex: 3 },
            ]});
          }

          const flexMsg = {
            type: 'flex',
            altText: `${statusText} • ${leaveTypeThai} ${numDays} วัน`,
            contents: {
              type: 'bubble',
              styles: { body: { backgroundColor: '#0f172a' }, footer: { backgroundColor: '#0f172a' } },
              header: {
                type: 'box', layout: 'vertical', backgroundColor: headerBg, paddingAll: 'lg',
                contents: [
                  { type: 'text', text: statusText, weight: 'bold', size: 'xl', color: headerAccent },
                  { type: 'text', text: statusSub, size: 'sm', color: '#94a3b8', margin: 'xs' },
                ],
              },
              body: {
                type: 'box', layout: 'vertical', backgroundColor: '#0f172a', paddingAll: 'lg',
                contents: [
                  { type: 'separator', color: '#1e293b' },
                  { type: 'box', layout: 'vertical', margin: 'lg', spacing: 'xs', contents: flexRows },
                ],
              },
              footer: {
                type: 'box', layout: 'vertical', backgroundColor: '#0f172a',
                contents: [{ type: 'text', text: '- HR Leave Portal', size: 'xs', color: '#334155', align: 'end' }],
              },
            },
          };

          const lineToken = process.env.LINE_CHANNEL_ACCESS_TOKEN;
          if (lineToken) {
            try {
              const r = await fetch('https://api.line.me/v2/bot/message/push', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${lineToken}` },
                body: JSON.stringify({ to: emp_line_id, messages: [flexMsg] }),
              });
              if (!r.ok) {
                const t = await r.text();
                console.error('LINE Push API error:', t);
              } else {
                console.log(`LINE Push sent to ${emp_line_id}`);
              }
            } catch (e: any) {
              console.error('Fetch error LINE Push:', e.message);
            }
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

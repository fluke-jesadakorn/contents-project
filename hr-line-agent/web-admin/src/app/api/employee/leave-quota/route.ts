import { NextResponse } from 'next/server';
import pool from '@/lib/db';

export async function POST(request: Request) {
  const client = await pool.connect();
  try {
    const { employeeId, hrId, totalSickLeave, totalAnnualLeave, totalPersonalLeave, reason } = await request.json();

    // ── Validation ────────────────────────────────────────────────────────────
    if (!employeeId || !hrId) {
      return NextResponse.json({ success: false, error: 'Missing required fields: employeeId, hrId' }, { status: 400 });
    }
    if (!reason?.trim()) {
      return NextResponse.json({ success: false, error: 'Reason is required (จำเป็นต้องระบุเหตุผล)' }, { status: 400 });
    }
    if (
      totalSickLeave === undefined &&
      totalAnnualLeave === undefined &&
      totalPersonalLeave === undefined
    ) {
      return NextResponse.json({ success: false, error: 'No quota changes specified' }, { status: 400 });
    }
    if (
      (totalSickLeave !== undefined && totalSickLeave < 0) ||
      (totalAnnualLeave !== undefined && totalAnnualLeave < 0) ||
      (totalPersonalLeave !== undefined && totalPersonalLeave < 0)
    ) {
      return NextResponse.json({ success: false, error: 'Leave quota cannot be negative' }, { status: 400 });
    }

    // ── Verify HR role ────────────────────────────────────────────────────────
    const hrRes = await client.query(
      `SELECT name FROM employees WHERE id = $1 AND role = 'hr'`,
      [hrId]
    );
    if (hrRes.rows.length === 0) {
      return NextResponse.json({ success: false, error: 'Unauthorized: HR user not found or insufficient role' }, { status: 403 });
    }
    const hrName: string = hrRes.rows[0].name;

    // ── Get current employee data ─────────────────────────────────────────────
    const empRes = await client.query(
      `SELECT name, line_user_id,
              total_sick_leave, used_sick_leave,
              total_annual_leave, used_annual_leave,
              total_personal_leave, used_personal_leave
       FROM employees WHERE id = $1`,
      [employeeId]
    );
    if (empRes.rows.length === 0) {
      return NextResponse.json({ success: false, error: 'Employee not found' }, { status: 404 });
    }
    const emp = empRes.rows[0];

    // ── Compute new values (keep original if not passed) ──────────────────────
    const newSick    = totalSickLeave    ?? emp.total_sick_leave;
    const newAnnual  = totalAnnualLeave  ?? emp.total_annual_leave;
    const newPersonal= totalPersonalLeave ?? emp.total_personal_leave;

    // Ensure used leave never exceeds new total (clamp if needed)
    const clampedUsedSick    = Math.min(emp.used_sick_leave,    newSick);
    const clampedUsedAnnual  = Math.min(emp.used_annual_leave,  newAnnual);
    const clampedUsedPersonal= Math.min(emp.used_personal_leave,newPersonal);

    // ── Apply update ──────────────────────────────────────────────────────────
    await client.query(
      `UPDATE employees
       SET total_sick_leave     = $1,
           used_sick_leave      = $2,
           total_annual_leave   = $3,
           used_annual_leave    = $4,
           total_personal_leave = $5,
           used_personal_leave  = $6,
           updated_at           = NOW()
       WHERE id = $7`,
      [newSick, clampedUsedSick, newAnnual, clampedUsedAnnual, newPersonal, clampedUsedPersonal, employeeId]
    );

    // ── Build change summary for notification ─────────────────────────────────
    type ChangeLine = { emoji: string; label: string; from: number; to: number };
    const changes: ChangeLine[] = [];
    if (newSick    !== emp.total_sick_leave)    changes.push({ emoji: '🤒', label: 'ลาป่วย',    from: emp.total_sick_leave,    to: newSick });
    if (newAnnual  !== emp.total_annual_leave)  changes.push({ emoji: '✈️', label: 'ลาพักร้อน', from: emp.total_annual_leave,  to: newAnnual });
    if (newPersonal!== emp.total_personal_leave)changes.push({ emoji: '💼', label: 'ลากิจ',     from: emp.total_personal_leave, to: newPersonal });

    // ── Send LINE notification (non-blocking) ─────────────────────────────────
    const lineToken = process.env.LINE_CHANNEL_ACCESS_TOKEN;
    if (lineToken && emp.line_user_id && changes.length > 0) {
      const changeContents = changes.flatMap(c => {
        const delta = c.to - c.from;
        const arrow = delta > 0 ? `▲ +${delta}` : `▼ ${delta}`;
        const arrowColor = delta > 0 ? '#10b981' : '#ef4444';
        return [
          {
            type: 'box', layout: 'horizontal', margin: 'sm',
            contents: [
              { type: 'text', text: `${c.emoji} ${c.label}`, size: 'sm', flex: 3, color: '#e2e8f0', weight: 'bold' },
              { type: 'text', text: `${c.from} → ${c.to} วัน`, size: 'sm', flex: 3, color: '#94a3b8' },
              { type: 'text', text: arrow, size: 'sm', flex: 2, color: arrowColor, weight: 'bold', align: 'end' },
            ],
          },
        ];
      });

      const flexMessage = {
        type: 'flex',
        altText: `📋 สิทธิ์วันลาของคุณได้รับการปรับปรุงโดย ${hrName}`,
        contents: {
          type: 'bubble',
          size: 'mega',
          styles: {
            header: { backgroundColor: '#1e1b4b' },
            body:   { backgroundColor: '#0f172a' },
            footer: { backgroundColor: '#0f172a' },
          },
          header: {
            type: 'box',
            layout: 'vertical',
            backgroundColor: '#1e1b4b',
            paddingAll: 'lg',
            contents: [
              { type: 'text', text: '📋 อัปเดตสิทธิ์วันลา', weight: 'bold', size: 'xl', color: '#818cf8' },
              { type: 'text', text: 'ฝ่ายบุคคลได้ปรับสิทธิ์วันลาของคุณ', size: 'sm', color: '#6366f1', margin: 'xs' },
            ],
          },
          body: {
            type: 'box',
            layout: 'vertical',
            backgroundColor: '#0f172a',
            paddingAll: 'lg',
            contents: [
              // Change table header
              {
                type: 'box', layout: 'horizontal', margin: 'none',
                contents: [
                  { type: 'text', text: 'ประเภทการลา', size: 'xs', flex: 3, color: '#475569', weight: 'bold' },
                  { type: 'text', text: 'เปลี่ยนจาก → เป็น', size: 'xs', flex: 3, color: '#475569', weight: 'bold' },
                  { type: 'text', text: 'ผลต่าง', size: 'xs', flex: 2, color: '#475569', weight: 'bold', align: 'end' },
                ],
              },
              { type: 'separator', margin: 'sm', color: '#1e293b' },
              ...changeContents,
              { type: 'separator', margin: 'lg', color: '#1e293b' },
              // Reason
              {
                type: 'box', layout: 'horizontal', margin: 'md',
                contents: [
                  { type: 'text', text: '📝 เหตุผล', size: 'sm', flex: 2, color: '#475569', weight: 'bold' },
                  { type: 'text', text: reason.trim(), size: 'sm', flex: 5, color: '#94a3b8', wrap: true },
                ],
              },
              // Approved by
              {
                type: 'box', layout: 'horizontal', margin: 'sm',
                contents: [
                  { type: 'text', text: '👤 โดย', size: 'sm', flex: 2, color: '#475569', weight: 'bold' },
                  { type: 'text', text: hrName, size: 'sm', flex: 5, color: '#e2e8f0', weight: 'bold' },
                ],
              },
            ],
          },
          footer: {
            type: 'box',
            layout: 'vertical',
            backgroundColor: '#0f172a',
            contents: [
              { type: 'text', text: '- HR Leave Portal', size: 'xs', color: '#334155', align: 'end' },
            ],
          },
        },
      };

      try {
        const r = await fetch('https://api.line.me/v2/bot/message/push', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${lineToken}`,
          },
          body: JSON.stringify({ to: emp.line_user_id, messages: [flexMessage] }),
        });
        if (!r.ok) {
          const t = await r.text();
          console.error('LINE push error:', t);
        } else {
          console.log(`LINE Push sent to ${emp.line_user_id}`);
        }
      } catch (e: any) {
        console.error('LINE push fetch error:', e.message);
      }
    }

    return NextResponse.json({
      success: true,
      changes: changes.map(c => ({ label: c.label, from: c.from, to: c.to })),
      notified: !!(lineToken && emp.line_user_id && changes.length > 0),
    });
  } catch (error: unknown) {
    const errMsg = error instanceof Error ? error.message : String(error);
    console.error('leave-quota error:', errMsg);
    return NextResponse.json({ success: false, error: errMsg }, { status: 500 });
  } finally {
    client.release();
  }
}

import { query } from '@/lib/db';

export const dynamic = 'force-dynamic';

export async function GET(request: Request) {
  try {
    const { searchParams } = new URL(request.url);
    const month = searchParams.get('month'); // expected format: YYYY-MM

    let sql = `
      SELECT
        e.employee_code      AS "รหัสพนักงาน",
        e.name               AS "ชื่อ-สกุล",
        e.department         AS "แผนก",
        e.position           AS "ตำแหน่ง",
        lr.leave_type        AS "ประเภทการลา",
        lr.start_date::text  AS "วันเริ่ม",
        lr.end_date::text    AS "วันสิ้นสุด",
        lr.days::float       AS "จำนวนวัน",
        lr.reason            AS "เหตุผล",
        lr.status            AS "สถานะ",
        appr.name            AS "อนุมัติโดย",
        lr.created_at        AS "วันที่ส่งคำขอ"
      FROM leave_requests lr
      JOIN employees e ON lr.employee_id = e.id
      LEFT JOIN employees appr ON lr.approved_by = appr.id
    `;

    const params: string[] = [];
    if (month) {
      // Filter by created_at month
      sql += ` WHERE TO_CHAR(lr.created_at, 'YYYY-MM') = $1`;
      params.push(month);
    }

    sql += ` ORDER BY lr.created_at DESC`;

    const result = await query(sql, params);
    const rows = result.rows;

    if (rows.length === 0) {
      const period = month || 'all';
      return new Response('ไม่พบข้อมูลในช่วงเวลาที่เลือก', {
        headers: {
          'Content-Type': 'text/plain; charset=utf-8',
          'Content-Disposition': `attachment; filename="leave-report-${period}.csv"`,
        },
      });
    }

    // Convert leave_type to Thai
    const leaveTypeThai: Record<string, string> = {
      sick: 'ลาป่วย',
      annual: 'ลาพักร้อน',
      personal: 'ลากิจ',
    };
    const statusThai: Record<string, string> = {
      pending: 'รออนุมัติ',
      approved: 'อนุมัติแล้ว',
      rejected: 'ปฏิเสธแล้ว',
    };

    // CSV headers
    const columns = [
      'รหัสพนักงาน',
      'ชื่อ-สกุล',
      'แผนก',
      'ตำแหน่ง',
      'ประเภทการลา',
      'วันเริ่ม',
      'วันสิ้นสุด',
      'จำนวนวัน',
      'เหตุผล',
      'สถานะ',
      'อนุมัติโดย',
      'วันที่ส่งคำขอ',
    ];

    const escapeCell = (val: unknown): string => {
      if (val === null || val === undefined) return '';
      const str = String(val);
      // If the value contains a comma, double-quote, or newline, wrap in quotes
      if (str.includes(',') || str.includes('"') || str.includes('\n')) {
        return `"${str.replace(/"/g, '""')}"`;
      }
      return str;
    };

    const csvLines: string[] = [columns.join(',')];

    for (const row of rows) {
      const leaveType = leaveTypeThai[row['ประเภทการลา']] || row['ประเภทการลา'];
      const status = statusThai[row['สถานะ']] || row['สถานะ'];
      // Format created_at to date only
      const createdAt = row['วันที่ส่งคำขอ']
        ? new Date(row['วันที่ส่งคำขอ']).toISOString().split('T')[0]
        : '';

      const cells = [
        escapeCell(row['รหัสพนักงาน']),
        escapeCell(row['ชื่อ-สกุล']),
        escapeCell(row['แผนก']),
        escapeCell(row['ตำแหน่ง']),
        escapeCell(leaveType),
        escapeCell(row['วันเริ่ม']),
        escapeCell(row['วันสิ้นสุด']),
        escapeCell(row['จำนวนวัน']),
        escapeCell(row['เหตุผล']),
        escapeCell(status),
        escapeCell(row['อนุมัติโดย']),
        escapeCell(createdAt),
      ];
      csvLines.push(cells.join(','));
    }

    const csvContent = '\uFEFF' + csvLines.join('\r\n'); // BOM for Thai UTF-8 in Excel
    const period = month || 'all';

    return new Response(csvContent, {
      headers: {
        'Content-Type': 'text/csv; charset=utf-8',
        'Content-Disposition': `attachment; filename="leave-report-${period}.csv"`,
      },
    });
  } catch (error: any) {
    console.error('Error generating CSV export:', error);
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
}

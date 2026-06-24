import { NextResponse } from 'next/server';
import pool from '@/lib/db';

export async function POST(request: Request) {
  const client = await pool.connect();
  try {
    const { requestId, action, hrId } = await request.json();

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

    await client.query('BEGIN');

    // 1. Update the leave request status and approved_by
    const statusText = action === 'approve' ? 'approved' : 'rejected';
    const updateRequestRes = await client.query(
      `UPDATE leave_requests 
       SET status = $1, approved_by = $2, updated_at = NOW() 
       WHERE id = $3 
       RETURNING employee_id, leave_type, days::float as days`,
      [statusText, hrId, requestId]
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

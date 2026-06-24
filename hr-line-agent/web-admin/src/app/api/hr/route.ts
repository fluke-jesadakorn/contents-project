import { NextResponse } from 'next/server';
import { query } from '@/lib/db';

export const dynamic = 'force-dynamic';

export async function GET() {
  try {
    // 1. Get all HR users
    const hrUsersRes = await query(
      "SELECT id, employee_code, name, position FROM employees WHERE role = 'hr' ORDER BY name ASC"
    );

    // 2. Get all leave requests joined with employee details
    const requestsRes = await query(`
      SELECT 
        lr.id,
        lr.employee_id,
        e.name as employee_name,
        e.employee_code,
        e.department,
        e.position,
        lr.leave_type,
        lr.start_date::text,
        lr.end_date::text,
        lr.days::float as days,
        lr.reason,
        lr.reject_reason,
        lr.status,
        lr.approved_by,
        appr.name as approved_by_name,
        lr.created_at
      FROM leave_requests lr
      JOIN employees e ON lr.employee_id = e.id
      LEFT JOIN employees appr ON lr.approved_by = appr.id
      ORDER BY lr.created_at DESC
    `);

    // 3. Get aggregate statistics
    const statsRes = await query(`
      SELECT 
        COUNT(*) as total,
        COUNT(*) FILTER (WHERE status = 'pending') as pending,
        COUNT(*) FILTER (WHERE status = 'approved') as approved,
        COUNT(*) FILTER (WHERE status = 'rejected') as rejected
      FROM leave_requests
    `);

    // 4. Get leave days breakdown by department (only approved)
    const deptStatsRes = await query(`
      SELECT 
        e.department,
        SUM(lr.days)::float as total_days
      FROM leave_requests lr
      JOIN employees e ON lr.employee_id = e.id
      WHERE lr.status = 'approved'
      GROUP BY e.department
      ORDER BY total_days DESC
    `);

    // 5. Get all employees details for user profiles
    const employeesRes = await query(`
      SELECT 
        id, 
        employee_code, 
        name, 
        department, 
        position, 
        role, 
        job_description, 
        total_sick_leave, used_sick_leave,
        total_annual_leave, used_annual_leave,
        total_personal_leave, used_personal_leave,
        created_at
      FROM employees 
      ORDER BY name ASC
    `);

    return NextResponse.json({
      success: true,
      hrUsers: hrUsersRes.rows,
      requests: requestsRes.rows,
      stats: statsRes.rows[0] || { total: 0, pending: 0, approved: 0, rejected: 0 },
      deptStats: deptStatsRes.rows,
      employees: employeesRes.rows,
    });
  } catch (error: any) {
    console.error('Error fetching HR dashboard data:', error);
    return NextResponse.json(
      { success: false, error: error.message },
      { status: 500 }
    );
  }
}

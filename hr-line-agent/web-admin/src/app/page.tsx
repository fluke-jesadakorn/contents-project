'use client';

import { useState, useEffect } from 'react';

interface HRUser {
  id: string;
  employee_code: string;
  name: string;
  position: string;
}

interface LeaveRequest {
  id: string;
  employee_id: string;
  employee_name: string;
  employee_code: string;
  department: string;
  position: string;
  leave_type: 'sick' | 'annual' | 'personal';
  start_date: string;
  end_date: string;
  days: number;
  reason: string;
  reject_reason: string | null;
  status: 'pending' | 'approved' | 'rejected';
  approved_by: string | null;
  approved_by_name: string | null;
  created_at: string;
}

interface Stats {
  total: number;
  pending: number;
  approved: number;
  rejected: number;
}

interface DeptStat {
  department: string;
  total_days: number;
}

export default function HRDashboard() {
  const [hrUsers, setHrUsers] = useState<HRUser[]>([]);
  const [selectedHrId, setSelectedHrId] = useState<string>('');
  const [requests, setRequests] = useState<LeaveRequest[]>([]);
  const [stats, setStats] = useState<Stats>({ total: 0, pending: 0, approved: 0, rejected: 0 });
  const [deptStats, setDeptStats] = useState<DeptStat[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [submittingId, setSubmittingId] = useState<string | null>(null);

  const fetchData = async () => {
    try {
      setLoading(true);
      const res = await fetch('/api/hr');
      const data = await res.json();
      if (data.success) {
        setHrUsers(data.hrUsers);
        setRequests(data.requests);
        setStats(data.stats);
        setDeptStats(data.deptStats);
        
        // Auto-select first HR user if none selected
        if (data.hrUsers.length > 0 && !selectedHrId) {
          setSelectedHrId(data.hrUsers[0].id);
        }
      } else {
        setError(data.error || 'Failed to fetch data');
      }
    } catch (err: any) {
      setError(err.message || 'An error occurred');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
  }, []);

  const handleDecision = async (requestId: string, action: 'approve' | 'reject') => {
    if (!selectedHrId) {
      alert('โปรดเลือกผู้ใช้ HR ที่จะอนุมัติงานก่อน');
      return;
    }

    let rejectReason = '';
    if (action === 'reject') {
      const reasonInput = prompt('โปรดระบุเหตุผลในการปฏิเสธคำขอลางานนี้ (จำเป็น):');
      if (reasonInput === null) return; // User cancelled prompt
      if (!reasonInput.trim()) {
        alert('จำเป็นต้องระบุเหตุผลในการปฏิเสธคำขอลา');
        return;
      }
      rejectReason = reasonInput.trim();
    }

    try {
      setSubmittingId(requestId);
      const res = await fetch('/api/leave', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ 
          requestId, 
          action, 
          hrId: selectedHrId,
          rejectReason: action === 'reject' ? rejectReason : undefined
        }),
      });
      const data = await res.json();
      if (data.success) {
        // Refresh data
        await fetchData();
      } else {
        alert('เกิดข้อผิดพลาด: ' + data.error);
      }
    } catch (err: any) {
      alert('เกิดข้อผิดพลาดในการเชื่อมต่อ: ' + err.message);
    } finally {
      setSubmittingId(null);
    }
  };

  const getLeaveTypeThai = (type: string) => {
    switch (type) {
      case 'sick': return '🤒 ลาป่วย';
      case 'annual': return '✈️ ลาพักร้อน';
      case 'personal': return 'ลากิจ';
      default: return type;
    }
  };

  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'approved':
        return <span className="px-2 py-1 text-xs font-semibold rounded-full bg-emerald-500/20 text-emerald-400 border border-emerald-500/30">อนุมัติแล้ว</span>;
      case 'rejected':
        return <span className="px-2 py-1 text-xs font-semibold rounded-full bg-rose-500/20 text-rose-400 border border-rose-500/30">ปฏิเสธแล้ว</span>;
      default:
        return <span className="px-2 py-1 text-xs font-semibold rounded-full bg-amber-500/20 text-amber-400 border border-amber-500/30">รออนุมัติ</span>;
    }
  };

  // Find max dept days to calculate bar percentage
  const maxDeptDays = deptStats.length > 0 ? Math.max(...deptStats.map(d => d.total_days)) : 1;

  return (
    <main className="min-h-screen bg-slate-950 text-slate-100 p-6 md:p-12 font-sans selection:bg-indigo-500 selection:text-white">
      {/* Header Panel */}
      <div className="max-w-7xl mx-auto flex flex-col md:flex-row md:items-center md:justify-between border-b border-slate-800 pb-6 mb-8 gap-4">
        <div>
          <h1 className="text-3xl font-extrabold tracking-tight bg-gradient-to-r from-indigo-400 via-purple-400 to-pink-400 bg-clip-text text-transparent">
            HR Leave Management Portal
          </h1>
          <p className="text-slate-400 text-sm mt-1">
            ระบบตรวจสอบสิทธิ์ สถิติการลา และพิจารณาอนุมัติคำขอหยุดงานสำหรับฝ่ายบุคคล
          </p>
        </div>

        {/* HR Switcher Dropdown */}
        <div className="flex items-center gap-3 bg-slate-900 border border-slate-800 px-4 py-2.5 rounded-xl shadow-lg shadow-indigo-950/20 self-start md:self-auto">
          <span className="text-xs text-indigo-400 font-bold uppercase tracking-wider">สลับบัญชี HR:</span>
          <select 
            value={selectedHrId} 
            onChange={(e) => setSelectedHrId(e.target.value)}
            className="bg-transparent border-0 text-slate-200 text-sm font-semibold focus:ring-0 focus:outline-none cursor-pointer"
          >
            {hrUsers.map(user => (
              <option key={user.id} value={user.id} className="bg-slate-900 text-slate-200">
                {user.name} ({user.position})
              </option>
            ))}
          </select>
        </div>
      </div>

      <div className="max-w-7xl mx-auto space-y-8">
        {loading && requests.length === 0 ? (
          <div className="flex justify-center py-20">
            <div className="animate-spin rounded-full h-10 w-10 border-t-2 border-b-2 border-indigo-500"></div>
          </div>
        ) : error ? (
          <div className="p-4 bg-rose-500/20 border border-rose-500/30 text-rose-300 rounded-xl text-center">
            {error}
          </div>
        ) : (
          <>
            {/* Stats Summary Grid */}
            <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 md:gap-6">
              <div className="bg-slate-900/60 backdrop-blur-md border border-slate-800 p-5 rounded-2xl flex flex-col justify-between">
                <span className="text-slate-400 text-xs font-bold uppercase tracking-wider">คำขอลาทั้งหมด</span>
                <span className="text-3xl font-black text-slate-100 mt-2">{stats.total}</span>
              </div>
              <div className="bg-amber-500/10 border border-amber-500/20 p-5 rounded-2xl flex flex-col justify-between">
                <span className="text-amber-400 text-xs font-bold uppercase tracking-wider">รออนุมัติ</span>
                <span className="text-3xl font-black text-amber-300 mt-2">{stats.pending}</span>
              </div>
              <div className="bg-emerald-500/10 border border-emerald-500/20 p-5 rounded-2xl flex flex-col justify-between">
                <span className="text-emerald-400 text-xs font-bold uppercase tracking-wider">อนุมัติแล้ว</span>
                <span className="text-3xl font-black text-emerald-300 mt-2">{stats.approved}</span>
              </div>
              <div className="bg-rose-500/10 border border-rose-500/20 p-5 rounded-2xl flex flex-col justify-between">
                <span className="text-rose-400 text-xs font-bold uppercase tracking-wider">ปฏิเสธแล้ว</span>
                <span className="text-3xl font-black text-rose-300 mt-2">{stats.rejected}</span>
              </div>
            </div>

            {/* Department Breakdown Mini-Report */}
            <div className="bg-slate-900/40 border border-slate-800 p-6 rounded-2xl">
              <h2 className="text-lg font-bold text-slate-200 mb-4 flex items-center gap-2">
                📊 สถิติวันลาสะสมตามแผนก (เฉพาะที่อนุมัติแล้ว)
              </h2>
              {deptStats.length === 0 ? (
                <p className="text-slate-500 text-sm italic">ยังไม่มีข้อมูลวันลาที่ได้รับการอนุมัติ</p>
              ) : (
                <div className="space-y-4">
                  {deptStats.map(dept => {
                    const pct = (dept.total_days / maxDeptDays) * 100;
                    return (
                      <div key={dept.department} className="space-y-1.5">
                        <div className="flex justify-between text-sm">
                          <span className="font-semibold text-slate-300">{dept.department}</span>
                          <span className="text-indigo-400 font-bold">{dept.total_days} วัน</span>
                        </div>
                        <div className="h-2.5 w-full bg-slate-850 rounded-full overflow-hidden border border-slate-800/40">
                          <div 
                            className="h-full bg-gradient-to-r from-indigo-500 via-purple-500 to-pink-500 rounded-full transition-all duration-500" 
                            style={{ width: `${pct}%` }}
                          />
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>

            {/* Leave Requests Table */}
            <div className="bg-slate-900/30 border border-slate-800 rounded-2xl overflow-hidden shadow-2xl">
              <div className="px-6 py-4 border-b border-slate-800 bg-slate-900/50 flex justify-between items-center">
                <h2 className="text-lg font-bold text-slate-200">
                  📋 รายการขอลาหยุดทั้งหมด
                </h2>
                <button 
                  onClick={fetchData} 
                  className="px-3 py-1.5 text-xs font-semibold rounded-lg bg-indigo-600/80 hover:bg-indigo-600 border border-indigo-500/20 text-white transition cursor-pointer"
                >
                  โหลดข้อมูลใหม่
                </button>
              </div>

              <div className="overflow-x-auto">
                <table className="w-full text-left border-collapse">
                  <thead>
                    <tr className="bg-slate-950/50 text-slate-400 text-xs font-bold uppercase tracking-wider border-b border-slate-800">
                      <th className="px-6 py-4">พนักงาน / แผนก</th>
                      <th className="px-6 py-4">ประเภทการลา</th>
                      <th className="px-6 py-4">ระยะเวลาที่ลา</th>
                      <th className="px-6 py-4">จำนวนวัน</th>
                      <th className="px-6 py-4">เหตุผลการลา</th>
                      <th className="px-6 py-4">สถานะ</th>
                      <th className="px-6 py-4 text-right">ดำเนินการ</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-800 text-sm">
                    {requests.length === 0 ? (
                      <tr>
                        <td colSpan={7} className="px-6 py-10 text-center text-slate-500 italic">
                          ยังไม่มีประวัติการส่งคำขอลาหยุดงาน
                        </td>
                      </tr>
                    ) : (
                      requests.map((req) => (
                        <tr key={req.id} className="hover:bg-slate-900/20 transition-colors">
                          <td className="px-6 py-4">
                            <div className="font-bold text-slate-200">{req.employee_name}</div>
                            <div className="text-xs text-slate-400 mt-0.5">{req.employee_code} • {req.department}</div>
                          </td>
                          <td className="px-6 py-4 font-medium text-slate-300">
                            {getLeaveTypeThai(req.leave_type)}
                          </td>
                          <td className="px-6 py-4 text-slate-300 font-mono text-xs">
                            {req.start_date} ถึง {req.end_date}
                          </td>
                          <td className="px-6 py-4 text-slate-200 font-bold">
                            {req.days} วัน
                          </td>
                          <td className="px-6 py-4 text-slate-400 italic max-w-xs truncate" title={req.reason}>
                            {req.reason || 'ไม่ได้ระบุเหตุผล'}
                          </td>
                          <td className="px-6 py-4">
                            <div className="flex flex-col gap-1 items-start">
                              {getStatusBadge(req.status)}
                              {req.approved_by_name && (
                                <span className="text-[10px] text-slate-500">
                                  โดย: {req.approved_by_name}
                                </span>
                              )}
                              {req.status === 'rejected' && req.reject_reason && (
                                <span className="text-[10px] text-rose-400 mt-1 max-w-[150px] break-words" title={req.reject_reason}>
                                  เหตุผล: {req.reject_reason}
                                </span>
                              )}
                            </div>
                          </td>
                          <td className="px-6 py-4 text-right">
                            {req.status === 'pending' ? (
                              <div className="flex justify-end gap-2">
                                <button
                                  onClick={() => handleDecision(req.id, 'approve')}
                                  disabled={submittingId !== null}
                                  className="px-3 py-1.5 rounded-lg text-xs font-bold bg-emerald-600/80 hover:bg-emerald-600 border border-emerald-500/20 text-white disabled:opacity-40 transition cursor-pointer"
                                >
                                  อนุมัติ
                                </button>
                                <button
                                  onClick={() => handleDecision(req.id, 'reject')}
                                  disabled={submittingId !== null}
                                  className="px-3 py-1.5 rounded-lg text-xs font-bold bg-rose-600/80 hover:bg-rose-600 border border-rose-500/20 text-white disabled:opacity-40 transition cursor-pointer"
                                >
                                  ปฏิเสธ
                                </button>
                              </div>
                            ) : (
                              <span className="text-xs text-slate-500 italic">เสร็จสิ้นแล้ว</span>
                            )}
                          </td>
                        </tr>
                      ))
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          </>
        )}
      </div>
    </main>
  );
}

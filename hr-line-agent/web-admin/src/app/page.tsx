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

interface Employee {
  id: string;
  employee_code: string;
  name: string;
  department: string;
  position: string;
  role: string;
  job_description: string;
  total_sick_leave: number;
  used_sick_leave: number;
  total_annual_leave: number;
  used_annual_leave: number;
  total_personal_leave: number;
  used_personal_leave: number;
  created_at: string;
}

export default function HRDashboard() {
  const [hrUsers, setHrUsers] = useState<HRUser[]>([]);
  const [selectedHrId, setSelectedHrId] = useState<string>('');
  const [requests, setRequests] = useState<LeaveRequest[]>([]);
  const [employees, setEmployees] = useState<Employee[]>([]);
  const [activeTab, setActiveTab] = useState<'requests' | 'employees'>('requests');
  const [selectedEmployeeId, setSelectedEmployeeId] = useState<string | null>(null);
  const [stats, setStats] = useState<Stats>({ total: 0, pending: 0, approved: 0, rejected: 0 });
  const [deptStats, setDeptStats] = useState<DeptStat[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [submittingId, setSubmittingId] = useState<string | null>(null);
  const [searchTerm, setSearchTerm] = useState('');

  const filteredEmployees = employees.filter(emp => 
    emp.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
    emp.employee_code.toLowerCase().includes(searchTerm.toLowerCase()) ||
    emp.department.toLowerCase().includes(searchTerm.toLowerCase()) ||
    emp.position.toLowerCase().includes(searchTerm.toLowerCase())
  );

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
        setEmployees(data.employees || []);
        
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

      {/* Tab Switcher */}
      <div className="max-w-7xl mx-auto flex gap-4 border-b border-slate-800 pb-3 mb-8">
        <button
          onClick={() => { setActiveTab('requests'); setSelectedEmployeeId(null); }}
          className={`px-4 py-2 text-sm font-bold rounded-lg transition border cursor-pointer ${
            activeTab === 'requests'
              ? 'bg-indigo-600 border-indigo-500 text-white shadow-lg shadow-indigo-950/45'
              : 'bg-slate-900 border-slate-800 text-slate-400 hover:text-slate-200'
          }`}
        >
          📋 รายการขอลาหยุด ({requests.filter(r => r.status === 'pending').length} รออนุมัติ)
        </button>
        <button
          onClick={() => { setActiveTab('employees'); setSelectedEmployeeId(null); }}
          className={`px-4 py-2 text-sm font-bold rounded-lg transition border cursor-pointer ${
            activeTab === 'employees'
              ? 'bg-indigo-600 border-indigo-500 text-white shadow-lg shadow-indigo-950/45'
              : 'bg-slate-900 border-slate-800 text-slate-400 hover:text-slate-200'
          }`}
        >
          👥 ทำเนียบพนักงาน ({employees.length} คน)
        </button>
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
        ) : activeTab === 'requests' ? (
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
                            <button
                              onClick={() => {
                                setSelectedEmployeeId(req.employee_id);
                                setActiveTab('employees');
                              }}
                              className="font-bold text-indigo-400 hover:text-indigo-300 hover:underline text-left focus:outline-none cursor-pointer"
                              title="คลิกเพื่อดูข้อมูลผู้ใช้และประวัติการลา"
                            >
                              {req.employee_name}
                            </button>
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
        ) : (
          /* Tab 2: Employees Directory */
          <div className="grid grid-cols-1 lg:grid-cols-12 gap-8">
            {/* Left Side: Employee List */}
            <div className="lg:col-span-4 bg-slate-900/30 border border-slate-800 rounded-2xl p-5 space-y-4 flex flex-col">
              <h2 className="text-lg font-bold text-slate-200 flex items-center gap-2 border-b border-slate-800 pb-3 mb-2">
                👥 รายชื่อพนักงาน
              </h2>
              {/* Search Box */}
              <div className="relative">
                <span className="absolute inset-y-0 left-0 flex items-center pl-3 pointer-events-none text-slate-500 text-xs">
                  🔍
                </span>
                <input
                  type="text"
                  placeholder="ค้นหาชื่อ, รหัส หรือแผนก..."
                  value={searchTerm}
                  onChange={(e) => setSearchTerm(e.target.value)}
                  className="w-full bg-slate-950 border border-slate-800 rounded-xl pl-8 pr-8 py-2 text-sm text-slate-200 placeholder-slate-500 focus:outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500 transition-all"
                />
                {searchTerm && (
                  <button
                    onClick={() => setSearchTerm('')}
                    className="absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-500 hover:text-slate-350 text-xs font-bold px-1 py-0.5 rounded cursor-pointer"
                  >
                    ✕
                  </button>
                )}
              </div>
              <div className="space-y-2.5 flex-1 max-h-[500px] overflow-y-auto pr-1">
                {filteredEmployees.length === 0 ? (
                  <p className="text-slate-500 text-xs italic text-center py-8">ไม่พบข้อมูลพนักงาน</p>
                ) : (
                  filteredEmployees.map(emp => {
                    const isSelected = selectedEmployeeId === emp.id;
                    return (
                      <button
                        key={emp.id}
                        onClick={() => setSelectedEmployeeId(emp.id)}
                        className={`w-full text-left p-3.5 rounded-xl border transition-all flex flex-col gap-1 cursor-pointer ${
                          isSelected
                            ? 'bg-slate-900 border-indigo-500 shadow-md shadow-indigo-950/20'
                            : 'bg-slate-900/40 border-slate-850 hover:border-slate-700 hover:bg-slate-900/60'
                        }`}
                      >
                        <div className="font-bold text-sm text-slate-200">{emp.name}</div>
                        <div className="text-xs text-slate-400 font-medium">
                          {emp.employee_code} • {emp.position}
                        </div>
                        <div className="text-[10px] text-indigo-400 mt-1 uppercase tracking-wider font-semibold">
                          แผนก: {emp.department}
                        </div>
                      </button>
                    );
                  })
                )}
              </div>
            </div>

            {/* Right Side: Detailed Profile & History */}
            <div className="lg:col-span-8 space-y-6">
              {(() => {
                const emp = employees.find(e => e.id === selectedEmployeeId);
                if (!emp) {
                  return (
                    <div className="h-full min-h-[300px] flex flex-col items-center justify-center bg-slate-900/20 border border-slate-800 border-dashed rounded-2xl p-8 text-center text-slate-500">
                      <span className="text-4xl mb-3">👈</span>
                      <h3 className="font-bold text-slate-400 text-sm">ยังไม่ได้เลือกพนักงาน</h3>
                      <p className="text-xs text-slate-500 max-w-xs mt-1">โปรดเลือกรายชื่อพนักงานจากแถบซ้ายมือเพื่อดูข้อมูลส่วนตัว ขอบข่ายหน้าที่งาน และสิทธิ์วันลาคงเหลือ</p>
                    </div>
                  );
                }

                const empRequests = requests.filter(r => r.employee_id === emp.id);
                const sickRem = emp.total_sick_leave - emp.used_sick_leave;
                const annualRem = emp.total_annual_leave - emp.used_annual_leave;
                const personalRem = emp.total_personal_leave - emp.used_personal_leave;

                return (
                  <div className="space-y-6">
                    {/* Employee Profile Card */}
                    <div className="bg-slate-900/40 border border-slate-800 p-6 rounded-2xl space-y-6">
                      <div className="flex flex-col md:flex-row md:justify-between md:items-start border-b border-slate-850 pb-5 gap-4">
                        <div>
                          <span className="px-2 py-0.5 text-[10px] font-bold rounded bg-indigo-500/20 text-indigo-400 border border-indigo-500/30 uppercase tracking-wider">
                            รหัสพนักงาน: {emp.employee_code}
                          </span>
                          <h2 className="text-2xl font-black text-slate-100 mt-1.5">{emp.name}</h2>
                          <p className="text-slate-400 text-sm mt-0.5">{emp.position} • {emp.department}</p>
                        </div>
                        <div className="bg-slate-950/60 border border-slate-850 px-3.5 py-2 rounded-xl text-center self-start">
                          <div className="text-[10px] text-slate-500 font-bold uppercase tracking-wider">บทบาทระบบ</div>
                          <div className="text-xs font-bold text-slate-300 mt-0.5 uppercase">{emp.role}</div>
                        </div>
                      </div>

                      {/* Job Description */}
                      <div>
                        <h3 className="text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">📋 ขอบข่ายหน้าที่งาน (Job Description)</h3>
                        <div className="bg-slate-950/40 border border-slate-850 p-4 rounded-xl text-sm text-slate-300 leading-relaxed italic">
                          "{emp.job_description || 'ไม่มีรายละเอียดขอบข่ายหน้าที่งานระบุไว้'}"
                        </div>
                      </div>

                      {/* Leave Balance Indicators */}
                      <div>
                        <h3 className="text-xs font-bold text-slate-400 uppercase tracking-wider mb-3">📊 สิทธิ์วันลาคงเหลือ</h3>
                        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                          {/* Sick */}
                          <div className="bg-slate-950/30 border border-slate-850 p-3.5 rounded-xl space-y-2">
                            <div className="flex justify-between text-xs">
                              <span className="font-bold text-slate-300">🤒 ลาป่วย</span>
                              <span className="text-emerald-400 font-extrabold">{sickRem} / {emp.total_sick_leave} วัน</span>
                            </div>
                            <div className="h-2 w-full bg-slate-850 rounded-full overflow-hidden">
                              <div className="h-full bg-emerald-500 rounded-full" style={{ width: `${(sickRem/emp.total_sick_leave)*100}%` }} />
                            </div>
                          </div>

                          {/* Annual */}
                          <div className="bg-slate-950/30 border border-slate-850 p-3.5 rounded-xl space-y-2">
                            <div className="flex justify-between text-xs">
                              <span className="font-bold text-slate-300">✈️ ลาพักร้อน</span>
                              <span className="text-indigo-400 font-extrabold">{annualRem} / {emp.total_annual_leave} วัน</span>
                            </div>
                            <div className="h-2 w-full bg-slate-850 rounded-full overflow-hidden">
                              <div className="h-full bg-indigo-500 rounded-full" style={{ width: `${(annualRem/emp.total_annual_leave)*100}%` }} />
                            </div>
                          </div>

                          {/* Personal */}
                          <div className="bg-slate-950/30 border border-slate-850 p-3.5 rounded-xl space-y-2">
                            <div className="flex justify-between text-xs">
                              <span className="font-bold text-slate-300">💼 ลากิจ</span>
                              <span className="text-amber-400 font-extrabold">{personalRem} / {emp.total_personal_leave} วัน</span>
                            </div>
                            <div className="h-2 w-full bg-slate-850 rounded-full overflow-hidden">
                              <div className="h-full bg-amber-500 rounded-full" style={{ width: `${(personalRem/emp.total_personal_leave)*100}%` }} />
                            </div>
                          </div>
                        </div>
                      </div>
                    </div>

                    {/* Employee Leave History */}
                    <div className="bg-slate-900/40 border border-slate-800 rounded-2xl p-6">
                      <h3 className="text-sm font-bold text-slate-200 border-b border-slate-850 pb-3 mb-4 flex items-center gap-2">
                        📜 ประวัติการยื่นใบลาทั้งหมด
                      </h3>
                      {empRequests.length === 0 ? (
                        <p className="text-slate-500 text-sm italic py-4 text-center">พนักงานคนนี้ยังไม่มีประวัติการส่งใบลาหยุดงาน</p>
                      ) : (
                        <div className="space-y-3 max-h-[300px] overflow-y-auto pr-1">
                          {empRequests.map(req => {
                            const typeThai = req.leave_type === 'sick' ? '🤒 ลาป่วย' : req.leave_type === 'annual' ? '✈️ ลาพักร้อน' : '💼 ลากิจ';
                            return (
                              <div key={req.id} className="bg-slate-950/45 border border-slate-850 p-4 rounded-xl flex flex-col md:flex-row md:items-center justify-between gap-3 text-xs">
                                <div className="space-y-1">
                                  <div className="flex items-center gap-2">
                                    <span className="font-bold text-slate-300">{typeThai}</span>
                                    <span className="text-slate-500 font-bold">•</span>
                                    <span className="text-slate-200 font-bold">{req.days} วัน</span>
                                  </div>
                                  <div className="text-slate-400 font-mono">
                                    {req.start_date} ถึง {req.end_date}
                                  </div>
                                  <div className="text-slate-400 italic">
                                    เหตุผล: {req.reason || 'ไม่ได้ระบุ'}
                                  </div>
                                  {req.status === 'rejected' && req.reject_reason && (
                                    <div className="text-rose-400 font-medium">
                                      เหตุผลปฏิเสธ: {req.reject_reason}
                                    </div>
                                  )}
                                </div>
                                <div className="flex flex-col items-start md:items-end gap-1">
                                  {getStatusBadge(req.status)}
                                  {req.approved_by_name && (
                                    <span className="text-[9px] text-slate-500">โดย: {req.approved_by_name}</span>
                                  )}
                                </div>
                              </div>
                            );
                          })}
                        </div>
                      )}
                    </div>
                  </div>
                );
              })()}
            </div>
          </div>
        )}
      </div>
    </main>
  );
}

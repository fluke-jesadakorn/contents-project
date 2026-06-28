'use client';

import { useState, useEffect, useMemo } from 'react';

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

// ─── Calendar Helpers ───────────────────────────────────────────────────────
function getDaysInMonth(year: number, month: number) {
  return new Date(year, month + 1, 0).getDate();
}
function getFirstDayOfMonth(year: number, month: number) {
  return new Date(year, month, 1).getDay(); // 0 = Sun
}
function toYMD(date: Date): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

const THAI_MONTHS = [
  'มกราคม','กุมภาพันธ์','มีนาคม','เมษายน','พฤษภาคม','มิถุนายน',
  'กรกฎาคม','สิงหาคม','กันยายน','ตุลาคม','พฤศจิกายน','ธันวาคม',
];
const DAY_LABELS = ['อา.','จ.','อ.','พ.','พฤ.','ศ.','ส.'];

export default function HRDashboard() {
  const [hrUsers, setHrUsers] = useState<HRUser[]>([]);
  const [selectedHrId, setSelectedHrId] = useState<string>('');
  const [requests, setRequests] = useState<LeaveRequest[]>([]);
  const [employees, setEmployees] = useState<Employee[]>([]);
  const [activeTab, setActiveTab] = useState<'requests' | 'employees' | 'calendar' | 'analytics'>('requests');
  const [selectedEmployeeId, setSelectedEmployeeId] = useState<string | null>(null);
  const [stats, setStats] = useState<Stats>({ total: 0, pending: 0, approved: 0, rejected: 0 });
  const [deptStats, setDeptStats] = useState<DeptStat[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [submittingId, setSubmittingId] = useState<string | null>(null);
  const [searchTerm, setSearchTerm] = useState('');

  // Calendar state
  const [calendarDate, setCalendarDate] = useState(new Date());
  const [tooltipReq, setTooltipReq] = useState<{ req: LeaveRequest; x: number; y: number } | null>(null);

  // Export state
  const [showExportMenu, setShowExportMenu] = useState(false);

  // Quota adjustment state
  interface QuotaForm { sick: number; annual: number; personal: number; reason: string; }
  const [quotaForm, setQuotaForm] = useState<QuotaForm | null>(null);
  const [quotaSubmitting, setQuotaSubmitting] = useState(false);
  const [quotaSuccess, setQuotaSuccess] = useState<{ changes: { label: string; from: number; to: number }[] } | null>(null);

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

  // Close tooltip on outside click
  useEffect(() => {
    const handler = () => setTooltipReq(null);
    window.addEventListener('click', handler);
    return () => window.removeEventListener('click', handler);
  }, []);

  // Reset quota form when employee selection changes
  useEffect(() => {
    setQuotaForm(null);
    setQuotaSuccess(null);
  }, [selectedEmployeeId]);

  const handleQuotaAdjust = async (emp: Employee) => {
    if (!selectedHrId) { alert('โปรดเลือก HR ผู้ดำเนินการก่อน'); return; }
    if (!quotaForm) return;
    if (!quotaForm.reason.trim()) { alert('กรุณาระบุเหตุผลในการปรับสิทธิ์วันลา'); return; }
    try {
      setQuotaSubmitting(true);
      const res = await fetch('/api/employee/leave-quota', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          employeeId: emp.id,
          hrId: selectedHrId,
          totalSickLeave: quotaForm.sick,
          totalAnnualLeave: quotaForm.annual,
          totalPersonalLeave: quotaForm.personal,
          reason: quotaForm.reason,
        }),
      });
      const data = await res.json();
      if (data.success) {
        setQuotaSuccess({ changes: data.changes });
        setQuotaForm(null);
        await fetchData();
        setTimeout(() => setQuotaSuccess(null), 8000);
      } else {
        alert('เกิดข้อผิดพลาด: ' + data.error);
      }
    } catch (err: any) {
      alert('เกิดข้อผิดพลาดในการเชื่อมต่อ: ' + err.message);
    } finally {
      setQuotaSubmitting(false);
    }
  };

  const handleDecision = async (requestId: string, action: 'approve' | 'reject') => {
    if (!selectedHrId) {
      alert('โปรดเลือกผู้ใช้ HR ที่จะอนุมัติงานก่อน');
      return;
    }
    let rejectReason = '';
    if (action === 'reject') {
      const reasonInput = prompt('โปรดระบุเหตุผลในการปฏิเสธคำขอลางานนี้ (จำเป็น):');
      if (reasonInput === null) return;
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
          rejectReason: action === 'reject' ? rejectReason : undefined,
        }),
      });
      const data = await res.json();
      if (data.success) {
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
      case 'personal': return '💼 ลากิจ';
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

  const maxDeptDays = deptStats.length > 0 ? Math.max(...deptStats.map(d => d.total_days)) : 1;

  // ─── Analytics: Monthly Trend (last 6 months) ────────────────────────────
  const monthlyTrend = useMemo(() => {
    const now = new Date();
    const months: { key: string; label: string; sick: number; annual: number; personal: number }[] = [];
    for (let i = 5; i >= 0; i--) {
      const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
      const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
      const label = `${THAI_MONTHS[d.getMonth()].slice(0, 3)} ${d.getFullYear()}`;
      months.push({ key, label, sick: 0, annual: 0, personal: 0 });
    }
    for (const req of requests) {
      const created = req.created_at.slice(0, 7); // YYYY-MM
      const slot = months.find(m => m.key === created);
      if (slot) {
        if (req.leave_type === 'sick') slot.sick += req.days;
        else if (req.leave_type === 'annual') slot.annual += req.days;
        else if (req.leave_type === 'personal') slot.personal += req.days;
      }
    }
    return months;
  }, [requests]);

  const maxMonthlyDays = useMemo(() => {
    return Math.max(...monthlyTrend.map(m => m.sick + m.annual + m.personal), 1);
  }, [monthlyTrend]);

  // ─── Analytics: Leave Type Distribution (approved) ───────────────────────
  const leaveTypeCounts = useMemo(() => {
    const approved = requests.filter(r => r.status === 'approved');
    const sick = approved.filter(r => r.leave_type === 'sick').reduce((a, b) => a + b.days, 0);
    const annual = approved.filter(r => r.leave_type === 'annual').reduce((a, b) => a + b.days, 0);
    const personal = approved.filter(r => r.leave_type === 'personal').reduce((a, b) => a + b.days, 0);
    const total = sick + annual + personal || 1;
    return { sick, annual, personal, total };
  }, [requests]);

  // ─── Analytics: Burnout Risk ──────────────────────────────────────────────
  const burnoutRisk = useMemo(() => {
    return employees.filter(e => e.used_annual_leave === 0 && e.total_annual_leave > 0);
  }, [employees]);

  // ─── Calendar: Leaves for a given cell date ───────────────────────────────
  const getRequestsForDate = (cellDate: string) => {
    return requests.filter(req =>
      req.status === 'approved' &&
      req.start_date <= cellDate &&
      req.end_date >= cellDate
    );
  };

  // ─── Export handler ───────────────────────────────────────────────────────
  const handleExport = (period: 'this-month' | 'last-month' | 'all') => {
    setShowExportMenu(false);
    const now = new Date();
    if (period === 'all') {
      window.open('/api/export', '_blank');
    } else {
      const d = period === 'this-month'
        ? new Date(now.getFullYear(), now.getMonth(), 1)
        : new Date(now.getFullYear(), now.getMonth() - 1, 1);
      const month = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
      window.open(`/api/export?month=${month}`, '_blank');
    }
  };

  // ─── Calendar Tab Renderer ────────────────────────────────────────────────
  const renderCalendar = () => {
    const year = calendarDate.getFullYear();
    const month = calendarDate.getMonth();
    const daysInMonth = getDaysInMonth(year, month);
    const firstDay = getFirstDayOfMonth(year, month);
    const cells: (number | null)[] = [...Array(firstDay).fill(null), ...Array.from({ length: daysInMonth }, (_, i) => i + 1)];
    while (cells.length % 7 !== 0) cells.push(null);

    const prevMonth = () => setCalendarDate(new Date(year, month - 1, 1));
    const nextMonth = () => setCalendarDate(new Date(year, month + 1, 1));

    const leaveChipClass = (type: string) => {
      if (type === 'sick') return 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30';
      if (type === 'annual') return 'bg-indigo-500/20 text-indigo-300 border border-indigo-500/30';
      return 'bg-amber-500/20 text-amber-300 border border-amber-500/30';
    };

    return (
      <div className="space-y-6">
        {/* Calendar Header */}
        <div className="flex items-center justify-between bg-slate-900/40 border border-slate-800 px-6 py-4 rounded-2xl">
          <button
            onClick={prevMonth}
            className="px-4 py-2 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-300 hover:text-white transition font-bold text-sm cursor-pointer"
          >
            ← ก่อนหน้า
          </button>
          <div className="text-center">
            <h2 className="text-xl font-extrabold bg-gradient-to-r from-indigo-400 to-purple-400 bg-clip-text text-transparent">
              {THAI_MONTHS[month]} {year + 543}
            </h2>
            <p className="text-xs text-slate-500 mt-0.5">{year}</p>
          </div>
          <button
            onClick={nextMonth}
            className="px-4 py-2 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-300 hover:text-white transition font-bold text-sm cursor-pointer"
          >
            ถัดไป →
          </button>
        </div>

        {/* Calendar Grid */}
        <div className="bg-slate-900/30 border border-slate-800 rounded-2xl overflow-hidden">
          {/* Day headers */}
          <div className="grid grid-cols-7 border-b border-slate-800">
            {DAY_LABELS.map((d, i) => (
              <div
                key={d}
                className={`py-3 text-center text-xs font-bold uppercase tracking-wider ${i === 0 ? 'text-rose-400' : i === 6 ? 'text-indigo-400' : 'text-slate-400'}`}
              >
                {d}
              </div>
            ))}
          </div>

          {/* Day cells */}
          <div className="grid grid-cols-7">
            {cells.map((day, idx) => {
              if (day === null) {
                return <div key={`empty-${idx}`} className="min-h-[110px] border-b border-r border-slate-800/60 bg-slate-950/30" />;
              }
              const cellDate = `${year}-${String(month + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
              const todayStr = toYMD(new Date());
              const isToday = cellDate === todayStr;
              const cellRequests = getRequestsForDate(cellDate);
              const dayOfWeek = (firstDay + day - 1) % 7;
              const isWeekend = dayOfWeek === 0 || dayOfWeek === 6;

              return (
                <div
                  key={cellDate}
                  className={`min-h-[110px] p-2 border-b border-r border-slate-800/60 flex flex-col gap-1 transition-colors ${
                    isToday ? 'bg-indigo-950/40' : isWeekend ? 'bg-slate-950/50' : 'bg-transparent hover:bg-slate-900/20'
                  }`}
                >
                  <span className={`text-xs font-bold self-start px-1.5 py-0.5 rounded-md ${
                    isToday
                      ? 'bg-indigo-500 text-white'
                      : isWeekend
                      ? 'text-slate-500'
                      : 'text-slate-400'
                  }`}>
                    {day}
                  </span>
                  <div className="flex flex-col gap-0.5 flex-1">
                    {cellRequests.slice(0, 3).map(req => (
                      <button
                        key={req.id}
                        onClick={(e) => {
                          e.stopPropagation();
                          setTooltipReq({ req, x: e.clientX, y: e.clientY });
                        }}
                        title={`${req.employee_name} - ${getLeaveTypeThai(req.leave_type)}`}
                        className={`text-[10px] px-1.5 py-0.5 rounded-md truncate text-left font-semibold cursor-pointer hover:opacity-80 transition-opacity ${leaveChipClass(req.leave_type)}`}
                      >
                        {req.employee_name.split(' ')[0]}
                      </button>
                    ))}
                    {cellRequests.length > 3 && (
                      <span className="text-[10px] text-slate-500 font-semibold px-1">+{cellRequests.length - 3} เพิ่มเติม</span>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        {/* Legend */}
        <div className="flex flex-wrap gap-4 items-center bg-slate-900/30 border border-slate-800 px-5 py-3 rounded-xl">
          <span className="text-xs text-slate-400 font-bold uppercase tracking-wider">ตำนาน:</span>
          <span className="flex items-center gap-1.5 text-xs text-emerald-300 font-semibold">
            <span className="w-3 h-3 rounded-sm bg-emerald-500/40 border border-emerald-500/50 inline-block" />
            ลาป่วย
          </span>
          <span className="flex items-center gap-1.5 text-xs text-indigo-300 font-semibold">
            <span className="w-3 h-3 rounded-sm bg-indigo-500/40 border border-indigo-500/50 inline-block" />
            ลาพักร้อน
          </span>
          <span className="flex items-center gap-1.5 text-xs text-amber-300 font-semibold">
            <span className="w-3 h-3 rounded-sm bg-amber-500/40 border border-amber-500/50 inline-block" />
            ลากิจ
          </span>
          <span className="ml-auto text-xs text-slate-500 italic">คลิกที่ชิปเพื่อดูรายละเอียด</span>
        </div>
      </div>
    );
  };

  // ─── Analytics Tab Renderer ───────────────────────────────────────────────
  const renderAnalytics = () => {
    const sickPct = Math.round((leaveTypeCounts.sick / leaveTypeCounts.total) * 360);
    const annualPct = Math.round((leaveTypeCounts.annual / leaveTypeCounts.total) * 360);
    const conicGrad = `conic-gradient(
      #10b981 0deg ${sickPct}deg,
      #6366f1 ${sickPct}deg ${sickPct + annualPct}deg,
      #f59e0b ${sickPct + annualPct}deg 360deg
    )`;

    return (
      <div className="space-y-8">
        {/* KPI Row */}
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
          <div className="bg-slate-900/60 backdrop-blur-md border border-slate-800 p-5 rounded-2xl flex flex-col justify-between">
            <span className="text-slate-400 text-xs font-bold uppercase tracking-wider">คำขอทั้งหมด</span>
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

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Monthly Trend Bar Chart */}
          <div className="lg:col-span-2 bg-slate-900/40 border border-slate-800 p-6 rounded-2xl">
            <h2 className="text-base font-bold text-slate-200 mb-1 flex items-center gap-2">
              📈 แนวโน้มการลา (6 เดือนล่าสุด)
            </h2>
            <p className="text-xs text-slate-500 mb-5">นับจากวันที่ส่งคำขอ (ทุกสถานะ) หน่วย: วัน</p>
            <div className="flex items-end gap-3 h-40">
              {monthlyTrend.map(m => {
                const total = m.sick + m.annual + m.personal;
                const pct = (total / maxMonthlyDays) * 100;
                const sickH = total > 0 ? (m.sick / total) * pct : 0;
                const annualH = total > 0 ? (m.annual / total) * pct : 0;
                const personalH = total > 0 ? (m.personal / total) * pct : 0;
                return (
                  <div key={m.key} className="flex-1 flex flex-col items-center gap-1 group">
                    <span className="text-[10px] text-slate-400 font-semibold opacity-0 group-hover:opacity-100 transition-opacity">{total > 0 ? `${total}ว` : '-'}</span>
                    <div
                      className="w-full flex flex-col-reverse rounded-t-lg overflow-hidden"
                      style={{ height: `${Math.max(pct, total > 0 ? 4 : 0)}%`, minHeight: total > 0 ? '4px' : '0' }}
                    >
                      <div style={{ height: `${sickH}%` }} className="bg-emerald-500/70 w-full transition-all duration-500" />
                      <div style={{ height: `${annualH}%` }} className="bg-indigo-500/70 w-full transition-all duration-500" />
                      <div style={{ height: `${personalH}%` }} className="bg-amber-500/70 w-full transition-all duration-500" />
                    </div>
                    <span className="text-[10px] text-slate-500 text-center leading-tight">{m.label}</span>
                  </div>
                );
              })}
            </div>
            <div className="flex gap-4 mt-4 pt-4 border-t border-slate-800">
              <span className="flex items-center gap-1.5 text-xs text-emerald-300"><span className="w-2.5 h-2.5 rounded-sm bg-emerald-500/70 inline-block" />ลาป่วย</span>
              <span className="flex items-center gap-1.5 text-xs text-indigo-300"><span className="w-2.5 h-2.5 rounded-sm bg-indigo-500/70 inline-block" />ลาพักร้อน</span>
              <span className="flex items-center gap-1.5 text-xs text-amber-300"><span className="w-2.5 h-2.5 rounded-sm bg-amber-500/70 inline-block" />ลากิจ</span>
            </div>
          </div>

          {/* Pie Chart: Leave Type Distribution */}
          <div className="bg-slate-900/40 border border-slate-800 p-6 rounded-2xl flex flex-col items-center justify-center">
            <h2 className="text-base font-bold text-slate-200 mb-1 self-start">🍰 สัดส่วนประเภทการลา</h2>
            <p className="text-xs text-slate-500 mb-5 self-start">เฉพาะที่อนุมัติแล้ว (วันสะสม)</p>
            <div
              className="w-36 h-36 rounded-full shadow-2xl shadow-indigo-950/50"
              style={{ background: conicGrad }}
            />
            <div className="mt-5 space-y-2 w-full">
              {[
                { label: 'ลาป่วย', days: leaveTypeCounts.sick, color: 'bg-emerald-500', text: 'text-emerald-300' },
                { label: 'ลาพักร้อน', days: leaveTypeCounts.annual, color: 'bg-indigo-500', text: 'text-indigo-300' },
                { label: 'ลากิจ', days: leaveTypeCounts.personal, color: 'bg-amber-500', text: 'text-amber-300' },
              ].map(item => (
                <div key={item.label} className="flex items-center justify-between text-xs">
                  <span className="flex items-center gap-1.5 font-semibold text-slate-300">
                    <span className={`w-2.5 h-2.5 rounded-sm ${item.color} inline-block opacity-80`} />
                    {item.label}
                  </span>
                  <span className={`font-extrabold ${item.text}`}>
                    {item.days} วัน ({Math.round((item.days / leaveTypeCounts.total) * 100)}%)
                  </span>
                </div>
              ))}
            </div>
          </div>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Department Horizontal Bar Chart */}
          <div className="bg-slate-900/40 border border-slate-800 p-6 rounded-2xl">
            <h2 className="text-base font-bold text-slate-200 mb-1 flex items-center gap-2">
              🏢 วันลาตามแผนก (อนุมัติแล้ว)
            </h2>
            <p className="text-xs text-slate-500 mb-5">วันลาสะสมทุกประเภทที่ได้รับการอนุมัติ</p>
            {deptStats.length === 0 ? (
              <p className="text-slate-500 text-sm italic text-center py-8">ยังไม่มีข้อมูล</p>
            ) : (
              <div className="space-y-4">
                {deptStats.map(dept => {
                  const pct = (dept.total_days / maxDeptDays) * 100;
                  return (
                    <div key={dept.department} className="space-y-1.5">
                      <div className="flex justify-between text-xs">
                        <span className="font-semibold text-slate-300">{dept.department}</span>
                        <span className="text-purple-400 font-bold">{dept.total_days} วัน</span>
                      </div>
                      <div className="h-2.5 w-full bg-slate-800 rounded-full overflow-hidden">
                        <div
                          className="h-full bg-gradient-to-r from-indigo-500 via-purple-500 to-pink-500 rounded-full transition-all duration-700"
                          style={{ width: `${pct}%` }}
                        />
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>

          {/* Burnout Risk Alert */}
          <div className="bg-slate-900/40 border border-slate-800 p-6 rounded-2xl">
            <h2 className="text-base font-bold text-slate-200 mb-1 flex items-center gap-2">
              🔥 ความเสี่ยง Burnout
            </h2>
            <p className="text-xs text-slate-500 mb-5">พนักงานที่ยังไม่ได้ใช้วันพักร้อนเลย (0/{'>'}0 วัน)</p>
            {burnoutRisk.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-8 text-center">
                <span className="text-3xl mb-2">✅</span>
                <p className="text-emerald-400 font-semibold text-sm">พนักงานทุกคนใช้วันพักร้อนแล้ว</p>
                <p className="text-slate-500 text-xs mt-1">ไม่พบความเสี่ยง Burnout</p>
              </div>
            ) : (
              <div className="space-y-2.5 max-h-[240px] overflow-y-auto pr-1">
                {burnoutRisk.map(emp => (
                  <div
                    key={emp.id}
                    className="bg-rose-950/30 border border-rose-500/25 px-4 py-3 rounded-xl flex items-center justify-between gap-3"
                  >
                    <div>
                      <div className="font-bold text-sm text-rose-200">{emp.name}</div>
                      <div className="text-[11px] text-rose-400/70 mt-0.5">{emp.department} · {emp.position}</div>
                    </div>
                    <div className="text-right shrink-0">
                      <div className="text-xs font-bold text-rose-400">0 / {emp.total_annual_leave} วัน</div>
                      <div className="text-[10px] text-rose-500/60 mt-0.5">ลาพักร้อนสะสม</div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>
    );
  };

  return (
    <main className="min-h-screen bg-slate-950 text-slate-100 p-6 md:p-12 font-sans selection:bg-indigo-500 selection:text-white">
      {/* Tooltip Overlay for calendar chips */}
      {tooltipReq && (
        <div
          className="fixed z-50 bg-slate-800 border border-slate-700 text-slate-100 text-xs px-3 py-2 rounded-xl shadow-2xl pointer-events-none max-w-xs"
          style={{ top: tooltipReq.y + 12, left: tooltipReq.x + 8 }}
        >
          <div className="font-bold text-sm text-indigo-300">{tooltipReq.req.employee_name}</div>
          <div className="mt-0.5 text-slate-400">{getLeaveTypeThai(tooltipReq.req.leave_type)}</div>
          <div className="text-slate-500 mt-0.5 font-mono">{tooltipReq.req.start_date} → {tooltipReq.req.end_date}</div>
          <div className="text-slate-300 font-bold mt-0.5">{tooltipReq.req.days} วัน</div>
        </div>
      )}

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
      <div className="max-w-7xl mx-auto flex flex-wrap gap-3 border-b border-slate-800 pb-3 mb-8">
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
        <button
          onClick={() => { setActiveTab('calendar'); }}
          className={`px-4 py-2 text-sm font-bold rounded-lg transition border cursor-pointer ${
            activeTab === 'calendar'
              ? 'bg-indigo-600 border-indigo-500 text-white shadow-lg shadow-indigo-950/45'
              : 'bg-slate-900 border-slate-800 text-slate-400 hover:text-slate-200'
          }`}
        >
          📅 ปฏิทินการลา
        </button>
        <button
          onClick={() => { setActiveTab('analytics'); }}
          className={`px-4 py-2 text-sm font-bold rounded-lg transition border cursor-pointer ${
            activeTab === 'analytics'
              ? 'bg-indigo-600 border-indigo-500 text-white shadow-lg shadow-indigo-950/45'
              : 'bg-slate-900 border-slate-800 text-slate-400 hover:text-slate-200'
          }`}
        >
          📊 วิเคราะห์ข้อมูล
        </button>
      </div>

      <div className="max-w-7xl mx-auto space-y-8">
        {loading && requests.length === 0 ? (
          <div className="flex justify-center py-20">
            <div className="animate-spin rounded-full h-10 w-10 border-t-2 border-b-2 border-indigo-500" />
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
              <div className="px-6 py-4 border-b border-slate-800 bg-slate-900/50 flex justify-between items-center gap-3">
                <h2 className="text-lg font-bold text-slate-200">
                  📋 รายการขอลาหยุดทั้งหมด
                </h2>
                <div className="flex items-center gap-2">
                  {/* Export Button */}
                  <div className="relative">
                    <button
                      id="export-btn"
                      onClick={() => setShowExportMenu(v => !v)}
                      className="px-3 py-1.5 text-xs font-semibold rounded-lg bg-emerald-700/70 hover:bg-emerald-700 border border-emerald-600/30 text-white transition cursor-pointer flex items-center gap-1.5"
                    >
                      ⬇️ ส่งออก CSV
                    </button>
                    {showExportMenu && (
                      <div className="absolute right-0 top-full mt-1.5 z-30 bg-slate-800 border border-slate-700 rounded-xl shadow-2xl overflow-hidden min-w-[180px]">
                        <button
                          id="export-this-month"
                          onClick={() => handleExport('this-month')}
                          className="w-full text-left px-4 py-2.5 text-sm text-slate-200 hover:bg-slate-700 transition cursor-pointer"
                        >
                          เดือนนี้
                        </button>
                        <button
                          id="export-last-month"
                          onClick={() => handleExport('last-month')}
                          className="w-full text-left px-4 py-2.5 text-sm text-slate-200 hover:bg-slate-700 transition cursor-pointer"
                        >
                          เดือนที่แล้ว
                        </button>
                        <button
                          id="export-all"
                          onClick={() => handleExport('all')}
                          className="w-full text-left px-4 py-2.5 text-sm text-slate-200 hover:bg-slate-700 transition cursor-pointer border-t border-slate-700"
                        >
                          ทั้งหมด
                        </button>
                      </div>
                    )}
                  </div>
                  <button
                    id="refresh-btn"
                    onClick={fetchData}
                    className="px-3 py-1.5 text-xs font-semibold rounded-lg bg-indigo-600/80 hover:bg-indigo-600 border border-indigo-500/20 text-white transition cursor-pointer"
                  >
                    โหลดข้อมูลใหม่
                  </button>
                </div>
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
        ) : activeTab === 'employees' ? (
          /* Tab 2: Employees Directory */
          <div className="grid grid-cols-1 lg:grid-cols-12 gap-8">
            {/* Left Side: Employee List */}
            <div className="lg:col-span-4 bg-slate-900/30 border border-slate-800 rounded-2xl p-5 space-y-4 flex flex-col">
              <h2 className="text-lg font-bold text-slate-200 flex items-center gap-2 border-b border-slate-800 pb-3 mb-2">
                👥 รายชื่อพนักงาน
              </h2>
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

                      <div>
                        <h3 className="text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">📋 ขอบข่ายหน้าที่งาน (Job Description)</h3>
                        <div className="bg-slate-950/40 border border-slate-850 p-4 rounded-xl text-sm text-slate-300 leading-relaxed italic">
                          &ldquo;{emp.job_description || 'ไม่มีรายละเอียดขอบข่ายหน้าที่งานระบุไว้'}&rdquo;
                        </div>
                      </div>

                      <div>
                        <h3 className="text-xs font-bold text-slate-400 uppercase tracking-wider mb-3">📊 สิทธิ์วันลาคงเหลือ</h3>
                        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                          <div className="bg-slate-950/30 border border-slate-850 p-3.5 rounded-xl space-y-2">
                            <div className="flex justify-between text-xs">
                              <span className="font-bold text-slate-300">🤒 ลาป่วย</span>
                              <span className="text-emerald-400 font-extrabold">{sickRem} / {emp.total_sick_leave} วัน</span>
                            </div>
                            <div className="h-2 w-full bg-slate-850 rounded-full overflow-hidden">
                              <div className="h-full bg-emerald-500 rounded-full" style={{ width: `${(sickRem / emp.total_sick_leave) * 100}%` }} />
                            </div>
                          </div>
                          <div className="bg-slate-950/30 border border-slate-850 p-3.5 rounded-xl space-y-2">
                            <div className="flex justify-between text-xs">
                              <span className="font-bold text-slate-300">✈️ ลาพักร้อน</span>
                              <span className="text-indigo-400 font-extrabold">{annualRem} / {emp.total_annual_leave} วัน</span>
                            </div>
                            <div className="h-2 w-full bg-slate-850 rounded-full overflow-hidden">
                              <div className="h-full bg-indigo-500 rounded-full" style={{ width: `${(annualRem / emp.total_annual_leave) * 100}%` }} />
                            </div>
                          </div>
                          <div className="bg-slate-950/30 border border-slate-850 p-3.5 rounded-xl space-y-2">
                            <div className="flex justify-between text-xs">
                              <span className="font-bold text-slate-300">💼 ลากิจ</span>
                              <span className="text-amber-400 font-extrabold">{personalRem} / {emp.total_personal_leave} วัน</span>
                            </div>
                            <div className="h-2 w-full bg-slate-850 rounded-full overflow-hidden">
                              <div className="h-full bg-amber-500 rounded-full" style={{ width: `${(personalRem / emp.total_personal_leave) * 100}%` }} />
                            </div>
                          </div>
                        </div>
                      </div>

                      {/* ── Quota Adjustment Section (HR Only) ─────────────── */}
                      <div className="border-t border-slate-800 pt-5">
                        <div className="flex items-center justify-between mb-3">
                          <h3 className="text-xs font-bold text-slate-400 uppercase tracking-wider">⚙️ ปรับโควตาวันลา (HR)</h3>
                          {!quotaForm ? (
                            <button
                              onClick={() => setQuotaForm({ sick: emp.total_sick_leave, annual: emp.total_annual_leave, personal: emp.total_personal_leave, reason: '' })}
                              className="px-3 py-1.5 text-xs font-bold rounded-lg bg-indigo-600/70 hover:bg-indigo-600 border border-indigo-500/30 text-white transition cursor-pointer flex items-center gap-1.5"
                            >
                              ✏️ แก้ไขโควตา
                            </button>
                          ) : (
                            <button
                              onClick={() => setQuotaForm(null)}
                              className="px-3 py-1.5 text-xs font-bold rounded-lg bg-slate-700 hover:bg-slate-600 border border-slate-600 text-slate-300 transition cursor-pointer"
                            >
                              ✕ ยกเลิก
                            </button>
                          )}
                        </div>

                        {/* Success Banner */}
                        {quotaSuccess && (
                          <div className="mb-4 bg-emerald-500/10 border border-emerald-500/30 rounded-xl p-4 space-y-2">
                            <p className="text-emerald-400 font-bold text-sm flex items-center gap-2">✅ ปรับโควตาสำเร็จแล้ว!</p>
                            {quotaSuccess.changes.map(c => {
                              const delta = c.to - c.from;
                              return (
                                <div key={c.label} className="flex items-center gap-2 text-xs">
                                  <span className="text-slate-300 font-semibold w-20">{c.label}</span>
                                  <span className="text-slate-400">{c.from} → {c.to} วัน</span>
                                  <span className={`font-bold ml-1 ${delta > 0 ? 'text-emerald-400' : 'text-rose-400'}`}>
                                    {delta > 0 ? `▲ +${delta}` : `▼ ${delta}`}
                                  </span>
                                </div>
                              );
                            })}
                            <p className="text-emerald-500/70 text-[11px] mt-1">📲 แจ้งเตือนถูกส่งไปยัง LINE ของพนักงานแล้ว</p>
                          </div>
                        )}

                        {/* Edit Form */}
                        {quotaForm && (() => {
                          const rows: { key: 'sick' | 'annual' | 'personal'; emoji: string; label: string; color: string; ring: string }[] = [
                            { key: 'sick',     emoji: '🤒', label: 'ลาป่วย',    color: 'text-emerald-400', ring: 'focus:ring-emerald-500/40 focus:border-emerald-500' },
                            { key: 'annual',   emoji: '✈️', label: 'ลาพักร้อน', color: 'text-indigo-400',  ring: 'focus:ring-indigo-500/40 focus:border-indigo-500' },
                            { key: 'personal', emoji: '💼', label: 'ลากิจ',     color: 'text-amber-400',   ring: 'focus:ring-amber-500/40 focus:border-amber-500' },
                          ];
                          return (
                            <div className="space-y-4">
                              {/* Leave type rows */}
                              <div className="grid grid-cols-1 gap-3">
                                {rows.map(row => {
                                  const original = row.key === 'sick' ? emp.total_sick_leave : row.key === 'annual' ? emp.total_annual_leave : emp.total_personal_leave;
                                  const current = quotaForm[row.key];
                                  const delta = current - original;
                                  return (
                                    <div key={row.key} className="flex items-center gap-3 bg-slate-950/40 border border-slate-800 rounded-xl px-4 py-3">
                                      <span className="text-slate-300 text-xs font-bold w-24 shrink-0">{row.emoji} {row.label}</span>
                                      <span className="text-slate-500 text-xs w-16 shrink-0">เดิม: <span className="text-slate-300 font-semibold">{original}</span> วัน</span>
                                      {/* Decrement */}
                                      <button
                                        onClick={() => setQuotaForm(prev => prev ? { ...prev, [row.key]: Math.max(0, prev[row.key] - 1) } : prev)}
                                        className="w-7 h-7 rounded-lg bg-rose-600/30 hover:bg-rose-600/60 border border-rose-500/30 text-rose-300 font-bold text-base leading-none flex items-center justify-center transition cursor-pointer shrink-0"
                                      >−</button>
                                      {/* Input */}
                                      <input
                                        type="number"
                                        min={0}
                                        max={365}
                                        value={current}
                                        onChange={e => setQuotaForm(prev => prev ? { ...prev, [row.key]: Math.max(0, parseInt(e.target.value) || 0) } : prev)}
                                        className={`w-16 text-center bg-slate-900 border border-slate-700 rounded-lg py-1 text-sm font-bold text-slate-100 focus:outline-none focus:ring-1 ${row.ring} transition`}
                                      />
                                      {/* Increment */}
                                      <button
                                        onClick={() => setQuotaForm(prev => prev ? { ...prev, [row.key]: prev[row.key] + 1 } : prev)}
                                        className="w-7 h-7 rounded-lg bg-emerald-600/30 hover:bg-emerald-600/60 border border-emerald-500/30 text-emerald-300 font-bold text-base leading-none flex items-center justify-center transition cursor-pointer shrink-0"
                                      >+</button>
                                      <span className="text-xs font-bold ml-1 shrink-0">
                                        {delta === 0 ? <span className="text-slate-600">—</span> : delta > 0 ? <span className="text-emerald-400">▲ +{delta}</span> : <span className="text-rose-400">▼ {delta}</span>}
                                      </span>
                                    </div>
                                  );
                                })}
                              </div>

                              {/* Reason textarea */}
                              <div>
                                <label className="text-xs font-bold text-slate-400 uppercase tracking-wider block mb-1.5">📝 เหตุผลในการปรับ <span className="text-rose-400">*</span></label>
                                <textarea
                                  rows={2}
                                  placeholder="เช่น ปรับตามนโยบายใหม่ประจำปี / พนักงานได้รับสิทธิ์เพิ่มพิเศษ..."
                                  value={quotaForm.reason}
                                  onChange={e => setQuotaForm(prev => prev ? { ...prev, reason: e.target.value } : prev)}
                                  className="w-full bg-slate-950 border border-slate-700 rounded-xl px-4 py-2.5 text-sm text-slate-200 placeholder-slate-600 focus:outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500/40 transition resize-none"
                                />
                              </div>

                              {/* Save button */}
                              <button
                                onClick={() => handleQuotaAdjust(emp)}
                                disabled={quotaSubmitting || !quotaForm.reason.trim()}
                                className="w-full py-2.5 rounded-xl text-sm font-bold bg-gradient-to-r from-indigo-600 to-purple-600 hover:from-indigo-500 hover:to-purple-500 text-white disabled:opacity-40 disabled:cursor-not-allowed transition-all shadow-lg shadow-indigo-950/40 flex items-center justify-center gap-2 cursor-pointer"
                              >
                                {quotaSubmitting ? (
                                  <><span className="animate-spin inline-block w-4 h-4 border-2 border-white/30 border-t-white rounded-full" />กำลังบันทึก...</>
                                ) : (
                                  <>💾 บันทึกและแจ้งเตือนพนักงาน</>
                                )}
                              </button>
                            </div>
                          );
                        })()}

                        {/* Placeholder when form is closed */}
                        {!quotaForm && !quotaSuccess && (
                          <p className="text-slate-600 text-xs italic">คลิก "แก้ไขโควตา" เพื่อปรับสิทธิ์วันลาสำหรับพนักงานคนนี้</p>
                        )}
                      </div>
                    </div>

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
                                  <div className="text-slate-400 font-mono">{req.start_date} ถึง {req.end_date}</div>
                                  <div className="text-slate-400 italic">เหตุผล: {req.reason || 'ไม่ได้ระบุ'}</div>
                                  {req.status === 'rejected' && req.reject_reason && (
                                    <div className="text-rose-400 font-medium">เหตุผลปฏิเสธ: {req.reject_reason}</div>
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
        ) : activeTab === 'calendar' ? (
          renderCalendar()
        ) : (
          renderAnalytics()
        )}
      </div>
    </main>
  );
}

import React from 'react';

interface StaffWorkspaceProps {
  currentUser: any;
  ocrPresets: any[];
  onOcrSubmit: (preset: any) => Promise<void>;
  expenses: any[];
  onSelectExpense: (exp: any) => void;
  selectedExpense?: any;
  loading: boolean;
  getStatusBadge: (status: string) => React.ReactNode;
}

export const StaffWorkspace: React.FC<StaffWorkspaceProps> = ({
  currentUser,
  ocrPresets,
  onOcrSubmit,
  expenses,
  onSelectExpense,
  selectedExpense,
  loading,
  getStatusBadge
}) => {
  // Filter expenses submitted by current user or show all if demo
  const userExpenses = expenses.filter(e => e.submitter_id === currentUser.id || true);

  return (
    <div className="space-y-8 animate-fade-in">
      {/* HERO BANNER FOR STAFF */}
      <div className="glass-panel p-6 sm:p-8 rounded-3xl bg-gradient-to-br from-emerald-950/40 via-slate-950 to-slate-950 border-emerald-500/20 relative overflow-hidden shadow-2xl">
        <div className="absolute -right-10 -bottom-10 w-60 h-60 bg-emerald-500/10 rounded-full blur-3xl pointer-events-none"></div>
        
        <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-6 relative z-10">
          <div>
            <div className="flex items-center gap-2 mb-2">
              <span className="px-2.5 py-0.5 rounded-full bg-emerald-500/20 text-emerald-400 text-[10px] font-mono font-bold uppercase border border-emerald-500/30">
                พนักงานผู้เบิกจ่าย (Staff Requester)
              </span>
              <span className="text-slate-400 text-xs">LINE OA Connected</span>
            </div>
            <h2 className="text-2xl font-black text-white tracking-tight">
              สวัสดีคุณ {currentUser.fullname} 👋
            </h2>
            <p className="text-xs text-slate-300 mt-1 max-w-xl font-sans leading-relaxed">
              จำลองขั้นตอนที่ 1: เลือกพรีเซ็ตใบเสร็จด้านล่างเพื่อสแกนผ่านระบบ AI OCR อัตโนมัติใน LINE Official Account ระบบจะดึงยอดเงินและรายการสินค้าเพื่อส่งต่อให้นักบัญชีตรวจสอบ
            </p>
          </div>

          <div className="bg-slate-900/80 p-4 rounded-2xl border border-slate-800 text-center min-w-[160px]">
            <span className="text-[10px] text-slate-400 uppercase font-mono font-bold block">คำขอที่กำลังดำเนินการ</span>
            <span className="text-2xl font-black text-emerald-400 font-mono mt-1 block">
              {userExpenses.filter(e => e.status !== 'paid' && e.status !== 'rejected').length} รายการ
            </span>
          </div>
        </div>

        {/* OCR PRESETS GRID */}
        <div className="mt-8 pt-6 border-t border-slate-800/80">
          <h3 className="text-xs font-bold text-slate-200 uppercase tracking-wider mb-4 flex items-center gap-2 font-mono">
            <span>📸</span> แตะเพื่อจำลองสแกนใบเสร็จใหม่ (LINE OA OCR Simulation)
          </h3>

          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
            {ocrPresets.map((preset, idx) => (
              <button
                key={idx}
                onClick={() => onOcrSubmit(preset)}
                disabled={loading}
                className="text-left bg-slate-900/60 hover:bg-emerald-950/30 p-4 rounded-2xl border border-slate-800 hover:border-emerald-500/50 transition-all flex flex-col justify-between h-44 relative group cursor-pointer shadow-lg hover:shadow-emerald-950"
              >
                <div className="absolute top-2 right-2 px-2 py-0.5 text-[8px] font-bold bg-emerald-500/10 text-emerald-400 rounded-md group-hover:bg-emerald-500 group-hover:text-slate-950 transition-all font-mono uppercase">
                  TAP TO SCAN
                </div>
                <div>
                  <span className="text-2xl block mb-2">{idx === 0 ? '☕' : idx === 1 ? '🚕' : idx === 2 ? '☁️' : '📄'}</span>
                  <h4 className="text-xs font-bold text-white pr-14 line-clamp-2 leading-snug">{preset.name}</h4>
                  <p className="text-[10px] text-slate-400 mt-1 truncate font-mono">ร้าน: {preset.vendorName}</p>
                </div>

                <div className="pt-3 border-t border-slate-800/80 flex justify-between items-center w-full mt-2 font-mono">
                  <span className="text-[10px] text-slate-500">{preset.items.length} สินค้า</span>
                  <span className="text-sm font-black text-emerald-400">
                    {preset.totalAmount.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿
                  </span>
                </div>
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* ACTIVE SUBMISSIONS LIST */}
      <div className="glass-panel p-6 rounded-3xl border-slate-800">
        <div className="flex justify-between items-center mb-6 pb-4 border-b border-slate-800">
          <div>
            <h3 className="text-base font-bold text-white flex items-center gap-2">
              <span>⏳</span> ประวัติเบิกเงินทดรองจ่ายของฉัน (My Reimbursements Tracker)
            </h3>
            <p className="text-xs text-slate-400 mt-0.5">ติดตามสถานะการตรวจสอบบัญชี การอนุมัติงบจากผู้จัดการ และรอบโอนเงินคืน</p>
          </div>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse">
            <thead>
              <tr className="border-b border-slate-800 text-[10px] font-bold uppercase tracking-wider text-slate-500 font-mono">
                <th className="py-3 px-4">เลขที่เอกสาร / วันที่</th>
                <th className="py-3 px-4">ร้านค้า / รายการ</th>
                <th className="py-3 px-4 text-right">ยอดเบิก (THB)</th>
                <th className="py-3 px-4 text-center">สถานะปัจจุบัน (Status)</th>
                <th className="py-3 px-4 text-center">ขั้นตอนต่อไป</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-900/60">
              {userExpenses.length === 0 ? (
                <tr>
                  <td colSpan={5} className="text-center py-12 text-xs text-slate-500 font-mono">
                    ยังไม่มีรายการเบิกเงิน กรุณาเลือกสแกนใบเสร็จจำลองด้านบนเพื่อเริ่มต้น
                  </td>
                </tr>
              ) : (
                userExpenses.map((exp) => {
                  const isSelected = selectedExpense?.id === exp.id;
                  return (
                    <tr
                      key={exp.id}
                      onClick={() => onSelectExpense(exp)}
                      className={`text-xs hover:bg-slate-900/50 cursor-pointer transition-all ${
                        isSelected ? 'bg-emerald-500/10 border-l-4 border-l-emerald-500 font-medium' : ''
                      }`}
                    >
                      <td className="py-4 px-4 font-mono">
                        <span className="text-white font-bold block">EXP-{exp.id}</span>
                        <span className="text-[10px] text-slate-500">
                          {new Date(exp.transaction_date).toLocaleDateString('th-TH', { day: '2-digit', month: 'short', year: 'numeric' })}
                        </span>
                      </td>
                      <td className="py-4 px-4">
                        <span className="text-slate-200 font-bold block truncate max-w-[200px]">{exp.vendor_name}</span>
                        <span className="text-[10px] text-slate-400 font-mono truncate max-w-[250px] block">
                          {exp.items ? exp.items.map((i: any) => i.description).join(', ') : ''}
                        </span>
                      </td>
                      <td className="py-4 px-4 text-right font-black text-white font-mono text-sm">
                        {parseFloat(exp.total_amount).toLocaleString('th-TH', { minimumFractionDigits: 2 })}
                      </td>
                      <td className="py-4 px-4 text-center">
                        {getStatusBadge(exp.status)}
                      </td>
                      <td className="py-4 px-4 text-center text-[11px] text-slate-400 font-sans">
                        {exp.status === 'ocr_extracted' && 'รอฝ่ายบัญชีตรวจความถูกต้อง'}
                        {exp.status === 'accountant_reviewed' && 'รอผู้จัดการอนุมัติจ่าย'}
                        {exp.status === 'approved' && 'รอโอนเงินชำระคืนเข้าบัญชี'}
                        {exp.status === 'paid' && <span className="text-emerald-400 font-bold">✨ โอนเงินคืนเรียบร้อย</span>}
                        {exp.status === 'rejected' && <span className="text-rose-400 font-bold">กรุณาติดต่อฝ่ายบัญชี</span>}
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};

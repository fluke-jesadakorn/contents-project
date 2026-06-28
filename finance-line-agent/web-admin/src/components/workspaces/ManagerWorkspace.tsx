import React from 'react';

interface ManagerWorkspaceProps {
  currentUser: any;
  expenses: any[];
  selectedExpense: any;
  onSelectExpense: (exp: any) => void;
  actionComment: string;
  setActionComment: (c: string) => void;
  onStatusChange: (status: string, customComment?: string) => Promise<void>;
  loading: boolean;
  getStatusBadge: (status: string) => React.ReactNode;
}

export const ManagerWorkspace: React.FC<ManagerWorkspaceProps> = ({
  currentUser,
  expenses,
  selectedExpense,
  onSelectExpense,
  actionComment,
  setActionComment,
  onStatusChange,
  loading,
  getStatusBadge
}) => {
  const pendingClaims = expenses.filter(e => e.status === 'accountant_reviewed');
  const allClaims = expenses;

  // Calculate department spend total
  const deptSpend = expenses
    .filter(e => e.status === 'approved' || e.status === 'paid')
    .reduce((acc, curr) => acc + (parseFloat(curr.total_amount) || 0), 0);

  const budgetLimit = 50000; // Mock department budget limit THB
  const burnRate = Math.min(100, (deptSpend / budgetLimit) * 100);

  return (
    <div className="space-y-8 animate-fade-in">
      {/* MANAGER KPI BUDGET CARDS */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <div className="glass-panel p-6 rounded-3xl border-amber-500/30 bg-gradient-to-br from-amber-950/20 to-slate-950 relative overflow-hidden">
          <div className="absolute top-0 right-0 p-4 bg-amber-500/10 text-amber-400 rounded-bl-3xl text-xl">💰</div>
          <span className="text-[10px] text-slate-400 uppercase tracking-widest font-black block font-mono">
            งบประมาณประจำแผนก (Dept. Budget Limit)
          </span>
          <span className="text-2xl font-black text-white font-mono mt-2 block">
            {budgetLimit.toLocaleString('th-TH')} ฿
          </span>
          <span className="text-[10px] text-slate-500 font-mono mt-1 block">ประจำเดือนนี้ (Current Month Allocation)</span>
        </div>

        <div className="glass-panel p-6 rounded-3xl border-amber-500/30 relative overflow-hidden">
          <span className="text-[10px] text-slate-400 uppercase tracking-widest font-black block font-mono">
            ใช้ไปแล้ว (Month-to-Date Spend)
          </span>
          <span className="text-2xl font-black text-amber-400 font-mono mt-2 block">
            {deptSpend.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿
          </span>
          <div className="w-full bg-slate-900 rounded-full h-2 mt-3 overflow-hidden border border-slate-800">
            <div className="bg-gradient-to-r from-amber-500 to-rose-500 h-2 rounded-full transition-all duration-500" style={{ width: `${burnRate}%` }}></div>
          </div>
          <span className="text-[9px] text-slate-400 font-mono mt-1 block">อัตราการใช้งบ (Burn Rate): {burnRate.toFixed(1)}%</span>
        </div>

        <div className="glass-panel p-6 rounded-3xl border-indigo-500/30 relative overflow-hidden">
          <div className="absolute top-0 right-0 p-4 bg-indigo-500/10 text-indigo-400 rounded-bl-3xl text-xl">⏳</div>
          <span className="text-[10px] text-slate-400 uppercase tracking-widest font-black block font-mono">
            รอผู้อำนวยการอนุมัติ (Pending Authorizations)
          </span>
          <span className="text-2xl font-black text-indigo-400 font-mono mt-2 block">
            {pendingClaims.length} คำขอ
          </span>
          <span className="text-[10px] text-slate-500 font-sans mt-1 block">ฝ่ายบัญชีตรวจสอบความถูกต้องเรียบร้อยแล้ว</span>
        </div>
      </div>

      {/* TWO COLUMN AUTHORIZATION WORKBENCH */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-8">
        {/* LEFT: CLAIMS WAITING APPROVAL */}
        <div className="lg:col-span-6 glass-panel p-6 rounded-3xl border-slate-800">
          <div className="flex justify-between items-center mb-6 pb-4 border-b border-slate-800">
            <div>
              <h3 className="text-base font-bold text-white flex items-center gap-2">
                <span>🛡️</span> รายการเบิกขออนุมัติงบ (Pending Approval Desk)
              </h3>
              <p className="text-xs text-slate-400 mt-0.5">คลิกเลือกรายการเพื่อพิจารณาคำอธิบายจากนักบัญชีและอนุมัติสั่งจ่าย</p>
            </div>
          </div>

          <div className="space-y-3 max-h-[550px] overflow-y-auto pr-1">
            {allClaims.length === 0 ? (
              <p className="text-center py-10 text-xs text-slate-500 font-mono">ไม่มีรายการเบิกจ่ายในระบบ</p>
            ) : (
              allClaims.map((exp) => {
                const isSelected = selectedExpense?.id === exp.id;
                const isReady = exp.status === 'accountant_reviewed';
                return (
                  <div
                    key={exp.id}
                    onClick={() => onSelectExpense(exp)}
                    className={`p-4 rounded-2xl border transition-all cursor-pointer ${
                      isSelected
                        ? 'bg-amber-500/15 border-amber-500 shadow-xl shadow-amber-950/40 ring-1 ring-amber-500/50'
                        : isReady
                          ? 'bg-slate-950/80 border-amber-500/30 hover:border-amber-500/60'
                          : 'bg-slate-950/40 border-slate-900 opacity-60'
                    }`}
                  >
                    <div className="flex justify-between items-start mb-2 font-mono">
                      <div className="flex items-center gap-2">
                        <span className="font-bold text-white text-xs">EXP-{exp.id}</span>
                        {isReady && <span className="px-1.5 py-0.2 bg-amber-500 text-slate-950 text-[8px] font-black rounded animate-pulse">ACTION REQ</span>}
                      </div>
                      {getStatusBadge(exp.status)}
                    </div>

                    <div className="text-xs mb-2">
                      <span className="font-bold text-slate-200 block truncate">{exp.vendor_name}</span>
                      <span className="text-[10px] text-slate-400 font-mono block truncate">
                        ผู้เบิก: {exp.submitter_name} ({exp.submitter_dept})
                      </span>
                    </div>

                    <div className="flex justify-between items-center pt-2 border-t border-slate-900 font-mono">
                      <span className="text-[10px] text-slate-500">
                        {new Date(exp.transaction_date).toLocaleDateString('en-GB')}
                      </span>
                      <span className="text-sm font-black text-amber-400">
                        {parseFloat(exp.total_amount).toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿
                      </span>
                    </div>
                  </div>
                );
              })
            )}
          </div>
        </div>

        {/* RIGHT: AUTHORIZATION ACTION MODAL */}
        <div className="lg:col-span-6">
          {selectedExpense ? (
            <div className="glass-panel p-6 sm:p-8 rounded-3xl border-amber-500/40 space-y-6 animate-fade-in shadow-2xl relative">
              <div className="flex justify-between items-center pb-4 border-b border-slate-800">
                <div>
                  <span className="text-[10px] font-mono font-bold uppercase text-amber-400 tracking-wider">
                    Executive Decision Console
                  </span>
                  <h3 className="text-lg font-bold text-white mt-0.5">
                    พิจารณาอนุมัติบิล EXP-{selectedExpense.id}
                  </h3>
                </div>
                <span className="text-2xl">👩‍💼</span>
              </div>

              {/* CLAIM DETAILS SUMMARY */}
              <div className="bg-slate-950/80 p-5 rounded-2xl border border-slate-900 space-y-3 text-xs font-mono">
                <div className="flex justify-between border-b border-slate-900 pb-2">
                  <span className="text-slate-400">ร้านค้า (Merchant):</span>
                  <span className="font-bold text-white font-sans">{selectedExpense.vendor_name}</span>
                </div>
                <div className="flex justify-between border-b border-slate-900 pb-2">
                  <span className="text-slate-400">พนักงานผู้เบิก (Requester):</span>
                  <span className="text-slate-200 font-sans">{selectedExpense.submitter_name} ({selectedExpense.submitter_dept})</span>
                </div>
                <div className="flex justify-between border-b border-slate-900 pb-2">
                  <span className="text-slate-400">ยอดเบิกสุทธิ (Total Amount):</span>
                  <span className="text-base font-black text-amber-400">{parseFloat(selectedExpense.total_amount).toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-slate-400">สถานะจากนักบัญชี:</span>
                  <span className={selectedExpense.is_corrupted ? 'text-rose-400 font-bold font-sans' : 'text-emerald-400 font-bold font-sans'}>
                    {selectedExpense.is_corrupted ? '⚠️ มีประวัติแก้ไขตัวเลขคลาดเคลื่อน' : '✅ ผลรวมตัวเลขถูกต้องสมดุล'}
                  </span>
                </div>
              </div>

              {/* ACCOUNTANT AUDIT NOTE BOX */}
              {selectedExpense.correction_notes && (
                <div className="p-4 bg-indigo-950/30 border border-indigo-500/30 rounded-2xl text-xs text-indigo-200 leading-relaxed font-sans">
                  <span className="font-bold text-indigo-400 block mb-1 font-mono">📌 ความเห็นจากนักตรวจสอบบัญชี (Auditor Notes):</span>
                  "{selectedExpense.correction_notes}"
                </div>
              )}

              {/* MANDATORY MANAGER COMMENT INPUT */}
              <div className="space-y-2">
                <label className="block text-xs font-bold text-slate-300">
                  📝 ระบุเหตุผล / คำสั่งของผู้จัดการ (Authorizer Reasoning Comment) <span className="text-rose-400">*</span>
                </label>
                <input
                  type="text"
                  value={actionComment}
                  onChange={(e) => setActionComment(e.target.value)}
                  placeholder="เช่น อนุมัติตามระเบียบเบิกจ่ายค่ารับรองลูกค้า หรือ ไม่อนุมัติเนื่องจากเกินวงเงิน..."
                  className="w-full bg-slate-950 border border-slate-800 focus:border-amber-500 rounded-xl px-4 py-3 text-xs text-white focus:outline-none transition-all"
                />
              </div>

              {/* APPROVE OR REJECT BUTTONS */}
              {selectedExpense.status === 'accountant_reviewed' ? (
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 pt-4 border-t border-slate-800">
                  <button
                    onClick={() => onStatusChange('approved', actionComment || 'อนุมัติสั่งจ่ายตามสิทธิ์งบประมาณ')}
                    disabled={loading}
                    className="bg-gradient-to-r from-emerald-600 to-teal-600 hover:from-emerald-500 hover:to-teal-500 text-white font-extrabold py-3.5 px-4 rounded-2xl text-xs transition-all shadow-xl shadow-emerald-950/50 cursor-pointer flex items-center justify-center gap-2"
                  >
                    <span>✅</span>
                    <span>อนุมัติสั่งจ่าย (Authorize & Post Accrual)</span>
                  </button>

                  <button
                    onClick={() => {
                      if (!actionComment) {
                        alert('กรุณาระบุเหตุผลในการปฏิเสธคำขอในช่องความคิดเห็น');
                        return;
                      }
                      onStatusChange('rejected', actionComment);
                    }}
                    disabled={loading}
                    className="bg-gradient-to-r from-rose-600 to-red-600 hover:from-rose-500 hover:to-red-500 text-white font-extrabold py-3.5 px-4 rounded-2xl text-xs transition-all shadow-xl shadow-rose-950/50 cursor-pointer flex items-center justify-center gap-2"
                  >
                    <span>❌</span>
                    <span>ไม่อนุมัติ (Reject Claim)</span>
                  </button>
                </div>
              ) : (
                <div className="p-4 bg-slate-900/60 rounded-xl border border-slate-800 text-center text-xs text-slate-400 font-mono">
                  บิลนี้อยู่ในสถานะ [{selectedExpense.status.toUpperCase()}] ดำเนินการเสร็จสิ้นแล้ว
                </div>
              )}
            </div>
          ) : (
            <div className="glass-panel p-12 rounded-3xl border border-slate-800 border-dashed text-center flex flex-col items-center justify-center h-[500px] text-slate-500">
              <span className="text-5xl mb-4">🛡️</span>
              <h3 className="text-sm font-bold text-white">โต๊ะอนุมัติงานยังว่าง (Workbench Idle)</h3>
              <p className="text-xs text-slate-400 mt-1 max-w-sm font-sans">
                คลิกเลือกรายการจากคิวด้านซ้ายมือเพื่อพิจารณารายละเอียด ตรวจสอบงบประมาณ และสั่งอนุมัติจ่ายเงิน
              </p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

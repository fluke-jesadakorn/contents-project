import React from 'react';

interface ExecutiveWorkspaceProps {
  execReport: any;
  activeSubTab: 'income' | 'cashflow' | 'assets' | 'liabilities' | 'equity' | 'expenses';
  setActiveSubTab: (tab: 'income' | 'cashflow' | 'assets' | 'liabilities' | 'equity' | 'expenses') => void;
}

export const ExecutiveWorkspace: React.FC<ExecutiveWorkspaceProps> = ({
  execReport,
  activeSubTab,
  setActiveSubTab
}) => {
  if (!execReport) {
    return (
      <div className="flex justify-center items-center py-20">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-indigo-500"></div>
        <span className="ml-3 text-xs font-mono text-slate-400">Loading C-Level Financial Engine...</span>
      </div>
    );
  }

  return (
    <div className="space-y-8 animate-fade-in">
      {/* C-SUITE HERO BANNER */}
      <div className="glass-panel p-6 sm:p-8 rounded-3xl bg-gradient-to-br from-purple-950/40 via-slate-950 to-indigo-950/40 border-purple-500/20 relative overflow-hidden shadow-2xl">
        <div className="absolute top-0 right-0 w-80 h-80 bg-purple-500/10 rounded-full blur-3xl pointer-events-none"></div>
        
        <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-6 relative z-10">
          <div>
            <div className="flex items-center gap-2 mb-2">
              <span className="px-3 py-1 rounded-full bg-purple-500/20 text-purple-300 text-[10px] font-mono font-black uppercase border border-purple-500/30">
                👑 C-Suite Command Center (CFO / CEO Cockpit)
              </span>
              <span className="text-slate-400 text-xs font-mono">TFRS / GAAP Compliance</span>
            </div>
            <h2 className="text-3xl font-black text-white tracking-tight">
              ศูนย์บัญชาการงบการเงินและสภาพคล่ององค์กร
            </h2>
            <p className="text-xs text-slate-300 mt-1 max-w-2xl font-sans leading-relaxed">
              รายงานสถานะทางการเงินแบบเรียลไทม์ ดึงข้อมูลตรงจากสมุดบัญชีแยกประเภททั่วไป (Double-Entry General Ledger) รองรับการตรวจสอบสมการบัญชี สินทรัพย์ = หนี้สิน + ทุน ตามมาตรฐานสากล
            </p>
          </div>
        </div>

        {/* 4 MACRO KPI CARDS */}
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mt-8 pt-6 border-t border-slate-800/80">
          <div className="bg-slate-900/60 p-5 rounded-2xl border border-indigo-500/30 relative">
            <span className="text-[10px] text-slate-400 uppercase tracking-widest font-black block font-mono">
              🏛️ สภาพคล่องเงินสด (Cash Position)
            </span>
            <span className="text-2xl font-black text-white font-mono mt-2 block">
              {execReport.kpis.totalCash.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿
            </span>
            <span className="text-[9px] text-slate-500 font-mono mt-1 block">[110100 + 110200 + 110300] เงินสดและเงินฝากธนาคาร</span>
          </div>

          <div className="bg-slate-900/60 p-5 rounded-2xl border border-amber-500/30 relative">
            <span className="text-[10px] text-slate-400 uppercase tracking-widest font-black block font-mono">
              ⏳ หนี้สินรอค้างจ่าย (Unpaid Liabilities)
            </span>
            <span className="text-2xl font-black text-amber-400 font-mono mt-2 block">
              {execReport.kpis.outstandingLiabilities.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿
            </span>
            <span className="text-[9px] text-slate-500 font-mono mt-1 block">[210500] เงินทดรองจ่ายค้างชำระพนักงาน</span>
          </div>

          <div className="bg-slate-900/60 p-5 rounded-2xl border border-purple-500/30 relative">
            <span className="text-[10px] text-slate-400 uppercase tracking-widest font-black block font-mono">
              📅 ค่าใช้จ่ายเดือนนี้ (MTD Expenses)
            </span>
            <span className="text-2xl font-black text-purple-400 font-mono mt-2 block">
              {execReport.kpis.mtdExpenses.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿
            </span>
            <span className="text-[9px] text-slate-500 font-mono mt-1 block">รวมบัญชีหมวด 5xxxxx ในเดือนปัจจุบัน</span>
          </div>

          <div className="bg-slate-900/60 p-5 rounded-2xl border border-emerald-500/30 relative">
            <span className="text-[10px] text-slate-400 uppercase tracking-widest font-black block font-mono">
              📈 กำไร/ขาดทุนสุทธิ (Net Income)
            </span>
            <span className={`text-2xl font-black font-mono mt-2 block ${execReport.incomeStatement.netIncome >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>
              {execReport.incomeStatement.netIncome.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿
            </span>
            <span className="text-[9px] text-slate-500 font-mono mt-1 block">รายได้ดำเนินงาน ลบ ค่าใช้จ่ายดำเนินงาน</span>
          </div>
        </div>
      </div>

      {/* STANDARDISED FINANCIAL STATEMENTS SUB-TABS */}
      <div className="flex flex-wrap bg-slate-900/80 p-1.5 rounded-2xl border border-slate-800 gap-1">
        <button
          onClick={() => setActiveSubTab('income')}
          className={`flex-1 min-w-[140px] px-4 py-3 text-xs font-bold rounded-xl transition-all flex items-center justify-center gap-2 cursor-pointer ${
            activeSubTab === 'income' ? 'bg-indigo-600 text-white shadow-lg shadow-indigo-500/20' : 'text-slate-400 hover:text-white hover:bg-slate-800/50'
          }`}
        >
          <span>📈</span>
          <span>Income Statement</span>
        </button>

        <button
          onClick={() => setActiveSubTab('cashflow')}
          className={`flex-1 min-w-[140px] px-4 py-3 text-xs font-bold rounded-xl transition-all flex items-center justify-center gap-2 cursor-pointer ${
            activeSubTab === 'cashflow' ? 'bg-indigo-600 text-white shadow-lg shadow-indigo-500/20' : 'text-slate-400 hover:text-white hover:bg-slate-800/50'
          }`}
        >
          <span>💸</span>
          <span>Cash Flow</span>
        </button>

        <button
          onClick={() => setActiveSubTab('assets')}
          className={`flex-1 min-w-[140px] px-4 py-3 text-xs font-bold rounded-xl transition-all flex items-center justify-center gap-2 cursor-pointer ${
            activeSubTab === 'assets' ? 'bg-indigo-600 text-white shadow-lg shadow-indigo-500/20' : 'text-slate-400 hover:text-white hover:bg-slate-800/50'
          }`}
        >
          <span>🏛️</span>
          <span>Assets (สินทรัพย์)</span>
        </button>

        <button
          onClick={() => setActiveSubTab('liabilities')}
          className={`flex-1 min-w-[140px] px-4 py-3 text-xs font-bold rounded-xl transition-all flex items-center justify-center gap-2 cursor-pointer ${
            activeSubTab === 'liabilities' ? 'bg-indigo-600 text-white shadow-lg shadow-indigo-500/20' : 'text-slate-400 hover:text-white hover:bg-slate-800/50'
          }`}
        >
          <span>⏳</span>
          <span>Liabilities (หนี้สิน)</span>
        </button>

        <button
          onClick={() => setActiveSubTab('equity')}
          className={`flex-1 min-w-[140px] px-4 py-3 text-xs font-bold rounded-xl transition-all flex items-center justify-center gap-2 cursor-pointer ${
            activeSubTab === 'equity' ? 'bg-indigo-600 text-white shadow-lg shadow-indigo-500/20' : 'text-slate-400 hover:text-white hover:bg-slate-800/50'
          }`}
        >
          <span>👑</span>
          <span>Equity (ส่วนของเจ้าของ)</span>
        </button>

        <button
          onClick={() => setActiveSubTab('expenses')}
          className={`flex-1 min-w-[140px] px-4 py-3 text-xs font-bold rounded-xl transition-all flex items-center justify-center gap-2 cursor-pointer ${
            activeSubTab === 'expenses' ? 'bg-indigo-600 text-white shadow-lg shadow-indigo-500/20' : 'text-slate-400 hover:text-white hover:bg-slate-800/50'
          }`}
        >
          <span>📊</span>
          <span>Expense Analytics</span>
        </button>
      </div>

      {/* SUB-TAB CONTENTS RENDERER */}
      <div className="relative">
        {/* SUB-TAB: INCOME STATEMENT */}
        {activeSubTab === 'income' && (
          <div className="glass-panel p-8 rounded-3xl space-y-6 animate-fade-in max-w-4xl mx-auto border-indigo-500/30">
            <div className="flex justify-between items-center border-b border-slate-800 pb-4">
              <div>
                <h3 className="text-lg font-bold text-white flex items-center gap-2">
                  <span>📈</span> งบกำไรขาดทุน (Income Statement - Standardised P&L)
                </h3>
                <p className="text-xs text-slate-400 mt-0.5">แสดงรายได้และค่าใช้จ่ายดำเนินงานของบริษัทประจำงวดบัญชีปัจจุบัน</p>
              </div>
              <span className="text-[10px] px-2.5 py-1 rounded bg-slate-800 text-slate-300 font-mono font-bold">GAAP / TFRS</span>
            </div>

            <div className="space-y-6 text-sm font-mono">
              {/* REVENUE */}
              <div className="space-y-2">
                <span className="font-extrabold text-slate-300 block uppercase tracking-wider text-xs border-b border-slate-900 pb-1.5 font-sans">
                  1. รายได้จากการดำเนินงาน (Operating Revenues - 4xxxxx)
                </span>
                {execReport.incomeStatement.revenue.length === 0 ? (
                  <div className="flex justify-between pl-4 text-slate-500 italic text-xs font-sans">
                    <span>ไม่มีบันทึกรายได้ในงวดนี้</span>
                    <span>0.00 ฿</span>
                  </div>
                ) : (
                  execReport.incomeStatement.revenue.map((r: any) => (
                    <div key={r.code} className="flex justify-between pl-4 text-xs">
                      <span className="font-sans text-slate-300">[{r.code}] {r.name_th}</span>
                      <span className="font-bold text-white">{r.balance.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿</span>
                    </div>
                  ))
                )}
                <div className="flex justify-between font-black border-t border-slate-800 pt-2 text-indigo-300 text-xs font-sans">
                  <span>รวมรายได้ (Total Operating Revenue)</span>
                  <span className="font-mono text-sm">{execReport.incomeStatement.totalRevenue.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿</span>
                </div>
              </div>

              {/* EXPENSE */}
              <div className="space-y-2">
                <span className="font-extrabold text-slate-300 block uppercase tracking-wider text-xs border-b border-slate-900 pb-1.5 font-sans">
                  2. ค่าใช้จ่ายในการดำเนินงาน (Operating Expenses - 5xxxxx)
                </span>
                {execReport.incomeStatement.expense.length === 0 ? (
                  <div className="flex justify-between pl-4 text-slate-500 italic text-xs font-sans">
                    <span>ไม่มีบันทึกค่าใช้จ่าย</span>
                    <span>0.00 ฿</span>
                  </div>
                ) : (
                  execReport.incomeStatement.expense.map((e: any) => (
                    <div key={e.code} className="flex justify-between pl-4 text-xs">
                      <span className="font-sans text-slate-300">[{e.code}] {e.name_th}</span>
                      <span className="text-rose-300 font-semibold">{e.balance.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿</span>
                    </div>
                  ))
                )}
                <div className="flex justify-between font-black border-t border-slate-800 pt-2 text-indigo-300 text-xs font-sans">
                  <span>รวมค่าใช้จ่ายดำเนินงาน (Total Operating Expenses)</span>
                  <span className="font-mono text-rose-400 text-sm">-{execReport.incomeStatement.totalExpense.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿</span>
                </div>
              </div>

              {/* NET P&L */}
              <div className="flex justify-between font-black text-base border-t-2 border-double border-slate-700 pt-4 text-white font-sans">
                <span>กำไร (ขาดทุน) สุทธิประจำงวด (Net Income / Loss)</span>
                <span className={`font-mono text-xl ${execReport.incomeStatement.netIncome >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>
                  {execReport.incomeStatement.netIncome.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿
                </span>
              </div>
            </div>
          </div>
        )}

        {/* SUB-TAB: CASH FLOW */}
        {activeSubTab === 'cashflow' && (
          <div className="glass-panel p-8 rounded-3xl space-y-6 animate-fade-in max-w-4xl mx-auto border-indigo-500/30">
            <div className="flex justify-between items-center border-b border-slate-800 pb-4">
              <div>
                <h3 className="text-lg font-bold text-white flex items-center gap-2">
                  <span>💸</span> งบกระแสเงินสด (Statement of Cash Flows - Direct Method)
                </h3>
                <p className="text-xs text-slate-400 mt-0.5">วิเคราะห์กระแสเงินสดรับและจ่ายจริงจากกิจกรรมดำเนินงานขององค์กร</p>
              </div>
              <span className="text-[10px] px-2.5 py-1 rounded bg-emerald-950 text-emerald-400 font-mono font-bold border border-emerald-500/30">
                DIRECT METHOD
              </span>
            </div>

            <div className="space-y-6 text-sm font-mono">
              <div className="space-y-2">
                <span className="font-extrabold text-slate-300 block uppercase tracking-wider text-xs border-b border-slate-900 pb-1.5 font-sans">
                  1. กระแสเงินสดรับจากกิจกรรมดำเนินงาน (Operating Cash Receipts)
                </span>
                <div className="flex justify-between pl-4 text-xs font-sans">
                  <span className="text-slate-300">รับชำระเงินจากลูกค้า (Cash Received from Customers)</span>
                  <span className="text-emerald-400 font-mono font-bold">+{execReport.cashFlowStatement.customerReceipts.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿</span>
                </div>
                <div className="flex justify-between font-black border-t border-slate-800 pt-2 text-indigo-300 text-xs font-sans">
                  <span>รวมกระแสเงินสดรับ (Total Cash Inflows)</span>
                  <span className="font-mono text-emerald-400 text-sm">+{execReport.cashFlowStatement.totalInflows.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿</span>
                </div>
              </div>

              <div className="space-y-2">
                <span className="font-extrabold text-slate-300 block uppercase tracking-wider text-xs border-b border-slate-900 pb-1.5 font-sans">
                  2. กระแสเงินสดจ่ายจากกิจกรรมดำเนินงาน (Operating Cash Disbursements)
                </span>
                <div className="flex justify-between pl-4 text-xs font-sans">
                  <span className="text-slate-300">จ่ายคืนเงินทดรองจ่ายพนักงาน (Employee Reimbursements Disbursed)</span>
                  <span className="text-rose-400 font-mono font-semibold">-{execReport.cashFlowStatement.employeeReimbursementsPaid.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿</span>
                </div>
                <div className="flex justify-between font-black border-t border-slate-800 pt-2 text-indigo-300 text-xs font-sans">
                  <span>รวมกระแสเงินสดจ่าย (Total Cash Outflows)</span>
                  <span className="font-mono text-rose-400 text-sm">-{execReport.cashFlowStatement.totalOutflows.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿</span>
                </div>
              </div>

              <div className="flex justify-between font-black text-base border-t border-slate-700 pt-4 text-white font-sans">
                <span>กระแสเงินสดสุทธิจากกิจกรรมดำเนินงาน (Net Operating Cash Flow)</span>
                <span className={`font-mono text-xl ${execReport.cashFlowStatement.netCashFlow >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>
                  {execReport.cashFlowStatement.netCashFlow.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿
                </span>
              </div>

              <div className="bg-slate-950 p-4 rounded-2xl border border-slate-900 space-y-2 mt-4 text-xs">
                <div className="flex justify-between text-slate-400 font-sans">
                  <span>เงินสดคงเหลือต้นงวด (Beginning Cash Balance):</span>
                  <span className="font-mono">0.00 ฿</span>
                </div>
                <div className="flex justify-between font-black text-white border-t border-slate-900 pt-2 text-sm font-sans">
                  <span>เงินสดคงเหลือปลายงวด (Ending Cash Balance):</span>
                  <span className="font-mono text-emerald-400">{execReport.cashFlowStatement.endingBalance.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿</span>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* SUB-TAB: ASSETS */}
        {activeSubTab === 'assets' && (
          <div className="glass-panel p-6 sm:p-8 rounded-3xl space-y-6 animate-fade-in border-indigo-500/30">
            <div>
              <h3 className="text-lg font-bold text-white flex items-center gap-2">
                <span>🏛️</span> บัญชีหมวดสินทรัพย์ (Assets Balance Sheet - 1xxxxx)
              </h3>
              <p className="text-xs text-slate-400 mt-0.5">แสดงรายการสินทรัพย์หมุนเวียน เงินสดในมือ และภาษีซื้อรอตัดบัญชี</p>
            </div>

            <div className="overflow-x-auto">
              <table className="w-full text-left border-collapse text-xs font-mono">
                <thead>
                  <tr className="border-b border-slate-800 text-[10px] font-bold uppercase tracking-wider text-slate-500 font-sans">
                    <th className="py-3 px-4">รหัสบัญชี (Code)</th>
                    <th className="py-3 px-4">ชื่อผังบัญชี (Account Description)</th>
                    <th className="py-3 px-4 text-right">เดบิตรวม (Debit Dr)</th>
                    <th className="py-3 px-4 text-right">เครดิตรวม (Credit Cr)</th>
                    <th className="py-3 px-4 text-right">ยอดคงเหลือสุทธิ (Net Balance)</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-900/60">
                  {execReport.balanceSheet.assets.map((a: any) => (
                    <tr key={a.code} className="hover:bg-slate-900/40 transition-all">
                      <td className="py-4 px-4 font-bold text-indigo-400">{a.code}</td>
                      <td className="py-4 px-4 font-sans">
                        <span className="block font-bold text-white">{a.name_th}</span>
                        <span className="text-[10px] text-slate-500 font-mono">{a.name}</span>
                      </td>
                      <td className="py-4 px-4 text-right text-slate-400">{a.total_debit.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿</td>
                      <td className="py-4 px-4 text-right text-slate-400">{a.total_credit.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿</td>
                      <td className="py-4 px-4 text-right font-black text-emerald-400 text-sm">{a.balance.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿</td>
                    </tr>
                  ))}
                  <tr className="bg-slate-900/40 font-black text-white font-sans border-t border-slate-800">
                    <td colSpan={2} className="py-4 px-4 uppercase">รวมสินทรัพย์ทั้งสิ้น (Total Assets)</td>
                    <td colSpan={3} className="py-4 px-4 text-right font-mono text-base text-emerald-400">
                      {execReport.balanceSheet.totalAssets.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        )}

        {/* SUB-TAB: LIABILITIES */}
        {activeSubTab === 'liabilities' && (
          <div className="glass-panel p-6 sm:p-8 rounded-3xl space-y-6 animate-fade-in border-amber-500/30">
            <div>
              <h3 className="text-lg font-bold text-white flex items-center gap-2">
                <span>⏳</span> บัญชีหมวดหนี้สิน (Liabilities Balance Sheet - 2xxxxx)
              </h3>
              <p className="text-xs text-slate-400 mt-0.5">แสดงภาระผูกพันทางการเงินและเจ้าหนี้เงินทดรองจ่ายพนักงานรอเคลียร์</p>
            </div>

            <div className="overflow-x-auto">
              <table className="w-full text-left border-collapse text-xs font-mono">
                <thead>
                  <tr className="border-b border-slate-800 text-[10px] font-bold uppercase tracking-wider text-slate-500 font-sans">
                    <th className="py-3 px-4">รหัสบัญชี (Code)</th>
                    <th className="py-3 px-4">ชื่อผังบัญชี (Account Description)</th>
                    <th className="py-3 px-4 text-right">เดบิตรวม (Debit Dr)</th>
                    <th className="py-3 px-4 text-right">เครดิตรวม (Credit Cr)</th>
                    <th className="py-3 px-4 text-right">ยอดคงเหลือสุทธิ (Net Balance)</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-900/60">
                  {execReport.balanceSheet.liabilities.length === 0 ? (
                    <tr><td colSpan={5} className="py-8 text-center text-slate-500 font-sans">ไม่มีหนี้สินค้างชำระในปัจจุบัน</td></tr>
                  ) : (
                    execReport.balanceSheet.liabilities.map((l: any) => (
                      <tr key={l.code} className="hover:bg-slate-900/40 transition-all">
                        <td className="py-4 px-4 font-bold text-amber-400">{l.code}</td>
                        <td className="py-4 px-4 font-sans">
                          <span className="block font-bold text-white">{l.name_th}</span>
                          <span className="text-[10px] text-slate-500 font-mono">{l.name}</span>
                        </td>
                        <td className="py-4 px-4 text-right text-slate-400">{l.total_debit.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿</td>
                        <td className="py-4 px-4 text-right text-slate-400">{l.total_credit.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿</td>
                        <td className="py-4 px-4 text-right font-black text-amber-400 text-sm">{l.balance.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿</td>
                      </tr>
                    ))
                  )}
                  <tr className="bg-slate-900/40 font-black text-white font-sans border-t border-slate-800">
                    <td colSpan={2} className="py-4 px-4 uppercase">รวมหนี้สินทั้งสิ้น (Total Liabilities)</td>
                    <td colSpan={3} className="py-4 px-4 text-right font-mono text-base text-amber-400">
                      {execReport.balanceSheet.totalLiabilities.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        )}

        {/* SUB-TAB: EQUITY */}
        {activeSubTab === 'equity' && (
          <div className="glass-panel p-6 sm:p-8 rounded-3xl space-y-6 animate-fade-in border-purple-500/30">
            <div>
              <h3 className="text-lg font-bold text-white flex items-center gap-2">
                <span>👑</span> บัญชีหมวดทุน (Owner's Equity - 3xxxxx)
              </h3>
              <p className="text-xs text-slate-400 mt-0.5">ทุนจดทะเบียน กำไรสะสม และกำไรสุทธิประจำงวด</p>
            </div>

            <div className="overflow-x-auto">
              <table className="w-full text-left border-collapse text-xs font-mono">
                <thead>
                  <tr className="border-b border-slate-800 text-[10px] font-bold uppercase tracking-wider text-slate-500 font-sans">
                    <th className="py-3 px-4">รหัสบัญชี (Code)</th>
                    <th className="py-3 px-4">ชื่อผังบัญชี (Account Description)</th>
                    <th className="py-3 px-4 text-right">เดบิตรวม (Dr)</th>
                    <th className="py-3 px-4 text-right">เครดิตรวม (Cr)</th>
                    <th className="py-3 px-4 text-right">ยอดคงเหลือสุทธิ (Net Balance)</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-900/60">
                  {execReport.balanceSheet.equity.map((eq: any) => (
                    <tr key={eq.code} className="hover:bg-slate-900/40 transition-all">
                      <td className="py-4 px-4 font-bold text-purple-400">{eq.code}</td>
                      <td className="py-4 px-4 font-sans">
                        <span className="block font-bold text-white">{eq.name_th}</span>
                        <span className="text-[10px] text-slate-500 font-mono">{eq.name}</span>
                      </td>
                      <td className="py-4 px-4 text-right text-slate-400">{eq.total_debit.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿</td>
                      <td className="py-4 px-4 text-right text-slate-400">{eq.total_credit.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿</td>
                      <td className="py-4 px-4 text-right font-black text-purple-300 text-sm">{eq.balance.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿</td>
                    </tr>
                  ))}
                  <tr className="bg-purple-950/20 font-bold text-emerald-400">
                    <td className="py-4 px-4 font-mono">-</td>
                    <td className="py-4 px-4 font-sans">
                      <span className="block">+ กำไรสุทธิประจำงวด (Current Net Income)</span>
                    </td>
                    <td className="py-4 px-4 text-right">-</td>
                    <td className="py-4 px-4 text-right">-</td>
                    <td className="py-4 px-4 text-right font-black font-mono text-sm">
                      {execReport.balanceSheet.netIncome.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿
                    </td>
                  </tr>
                  <tr className="bg-slate-900/40 font-black text-white font-sans border-t border-slate-800">
                    <td colSpan={2} className="py-4 px-4 uppercase">รวมส่วนของเจ้าของทั้งสิ้น (Total Equity)</td>
                    <td colSpan={3} className="py-4 px-4 text-right font-mono text-base text-purple-400">
                      {(execReport.balanceSheet.totalEquity + execReport.balanceSheet.netIncome).toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            {/* EQUATION CHECK BOX */}
            <div className="p-5 bg-slate-950 rounded-2xl border border-indigo-500/30 text-xs flex flex-col sm:flex-row justify-between items-center gap-2">
              <span className="font-bold text-slate-300 font-sans">⚖️ ตรวจสอบความสมดุลสมการบัญชี (Accounting Equation Validation):</span>
              <div className="font-mono text-white font-bold">
                <span className="text-emerald-400">Assets</span> ({execReport.balanceSheet.totalAssets.toLocaleString()} ฿) 
                <span className="text-slate-500"> == </span> 
                <span className="text-amber-400">Liabilities</span> ({execReport.balanceSheet.totalLiabilities.toLocaleString()} ฿) + 
                <span className="text-purple-400"> Equity</span> ({(execReport.balanceSheet.totalEquity + execReport.balanceSheet.netIncome).toLocaleString()} ฿)
              </div>
            </div>
          </div>
        )}

        {/* SUB-TAB: EXPENSES */}
        {activeSubTab === 'expenses' && (
          <div className="glass-panel p-6 sm:p-8 rounded-3xl space-y-6 animate-fade-in">
            <div>
              <h3 className="text-lg font-bold text-white flex items-center gap-2">
                <span>📊</span> สถิติสัดส่วนค่าใช้จ่ายองค์กร (Operating Expenses Analytics)
              </h3>
              <p className="text-xs text-slate-400 mt-0.5">แจกแจงสัดส่วนงบประมาณค่าใช้จ่ายตามหมวดหมู่บัญชี</p>
            </div>

            <div className="space-y-4 max-w-3xl mx-auto py-4">
              {execReport.incomeStatement.expense.length === 0 ? (
                <p className="text-center py-12 text-xs text-slate-500 font-mono">ยังไม่มีบันทึกค่าใช้จ่าย</p>
              ) : (
                execReport.incomeStatement.expense.map((exp: any) => {
                  const maxVal = Math.max(...execReport.incomeStatement.expense.map((e: any) => e.balance));
                  const percent = maxVal > 0 ? (exp.balance / maxVal) * 100 : 0;
                  return (
                    <div key={exp.code} className="space-y-1.5 font-mono">
                      <div className="flex justify-between text-xs">
                        <span className="font-sans font-bold text-slate-200">[{exp.code}] {exp.name_th} ({exp.name})</span>
                        <span className="font-black text-rose-400">{exp.balance.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿</span>
                      </div>
                      <div className="w-full bg-slate-950 rounded-full h-3 overflow-hidden border border-slate-900">
                        <div className="bg-gradient-to-r from-indigo-500 via-purple-500 to-pink-500 h-3 rounded-full transition-all duration-700" style={{ width: `${percent}%` }}></div>
                      </div>
                    </div>
                  );
                })
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

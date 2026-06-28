'use client';

import React, { useState, useEffect } from 'react';
import { 
  getDashboardData, 
  submitMockExpense, 
  reviewAndCorrectExpense, 
  changeExpenseStatus, 
  getSemanticSuggestions,
  getLedgerEntries,
  getExecutiveReport
} from './actions';

import { canAccessTab, getDefaultTab, type TabName } from '@/lib/permissions';
import { AccessDenied } from '../components/AccessDenied';

import { Navbar } from '../components/Navbar';
import { WorkflowStepper } from '../components/WorkflowStepper';
import { StaffWorkspace } from '../components/workspaces/StaffWorkspace';
import { AccountantWorkspace } from '../components/workspaces/AccountantWorkspace';
import { ManagerWorkspace } from '../components/workspaces/ManagerWorkspace';
import { ExecutiveWorkspace } from '../components/workspaces/ExecutiveWorkspace';

export default function Home() {
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState<'workbench' | 'ledger' | 'cockpit'>('workbench');
  const [activeSubTab, setActiveSubTab] = useState<'income' | 'cashflow' | 'assets' | 'liabilities' | 'equity' | 'expenses'>('income');
  const [users, setUsers] = useState<any[]>([]);
  const [coa, setCoa] = useState<any[]>([]);
  const [expenses, setExpenses] = useState<any[]>([]);
  const [journals, setJournals] = useState<any[]>([]);
  const [execReport, setExecReport] = useState<any>(null);
  
  // Simulation control
  const [currentUser, setCurrentUser] = useState<any>(null);
  
  // Selection control
  const [selectedExpense, setSelectedExpense] = useState<any>(null);
  const [editForm, setEditForm] = useState<any>(null);

  // Suggestion states
  const [suggestions, setSuggestions] = useState<Record<number, any[]>>({});
  const [loadingSuggestion, setLoadingSuggestion] = useState<Record<number, boolean>>({});

  // Manager action comment
  const [actionComment, setActionComment] = useState('');

  // OCR Simulator presets
  const ocrPresets = [
    {
      name: "Starbucks (ใบเสร็จค่ารับรองลูกค้า)",
      vendorName: "Starbucks Coffee (Thailand)",
      transactionDate: new Date().toISOString().split('T')[0],
      subtotal: 299.07,
      vatAmount: 20.93,
      totalAmount: 320.00,
      paymentMethod: "cash",
      isCorrupted: false,
      correctionNotes: "",
      items: [
        { description: "1x Cold Brew Coffee Large", amount: 140.00 },
        { description: "1x Ham & Cheese Croissant", amount: 180.00 }
      ]
    },
    {
      name: "Grab Taxi (ใบเสร็จเดินทางพบลูกค้า)",
      vendorName: "GrabTaxi (Thailand) Co., Ltd.",
      transactionDate: new Date().toISOString().split('T')[0],
      subtotal: 450.00,
      vatAmount: 0.00,
      totalAmount: 450.00,
      paymentMethod: "credit_card",
      isCorrupted: false,
      correctionNotes: "",
      items: [
        { description: "GrabCar Premium service from Head Office to True Digital Park", amount: 450.00 }
      ]
    },
    {
      name: "AWS Hosting (ซอฟต์แวร์ระบบคลาวด์)",
      vendorName: "Amazon Web Services Inc.",
      transactionDate: new Date(Date.now() - 4 * 24 * 3600 * 1000).toISOString().split('T')[0],
      subtotal: 1000.00,
      vatAmount: 70.00,
      totalAmount: 1070.00,
      paymentMethod: "transfer",
      isCorrupted: false,
      correctionNotes: "",
      items: [
        { description: "AWS Cloud Infrastructure charges (EC2, RDS Monthly Billing)", amount: 1000.00 }
      ]
    },
    {
      name: "Office Depot (พบผลรวมเลขคลาดเคลื่อน)",
      vendorName: "Office Depot (Thailand)",
      transactionDate: new Date(Date.now() - 6 * 24 * 3600 * 1000).toISOString().split('T')[0],
      subtotal: 500.00,
      vatAmount: 35.00,
      totalAmount: 650.00, // OCR error
      paymentMethod: "cash",
      isCorrupted: true,
      correctionNotes: "Math Mismatch: Subtotal 500.00 + VAT 35.00 is 535.00, but OCR extracted total amount is 650.00 (Discrepancy: 115.00 THB). Needs manual accountant adjustment.",
      items: [
        { description: "A4 Double A Copier Paper 5 Reams", amount: 300.00 },
        { description: "Stationery pack (Notebooks, Pens, Folders)", amount: 200.00 }
      ]
    }
  ];

  const refreshData = async () => {
    setLoading(true);
    const data = await getDashboardData();
    const ledgerData = await getLedgerEntries();
    const execData = await getExecutiveReport();
    
    if (data.success) {
      setUsers(data.users || []);
      setCoa(data.coa || []);
      setExpenses(data.expenses || []);
      
      if (data.users && data.users.length > 0) {
        if (!currentUser) {
          const defaultUser = data.users.find((u: any) => u.employee_code === 'EMP003') || data.users[0];
          setCurrentUser(defaultUser);
        } else {
          const updatedUser = data.users.find((u: any) => u.id === currentUser.id);
          if (updatedUser) setCurrentUser(updatedUser);
        }
      }
    }

    if (ledgerData.success) {
      setJournals(ledgerData.journals || []);
    }

    if (execData.success) {
      setExecReport(execData.report || null);
    }
    setLoading(false);
  };

  useEffect(() => {
    refreshData();
  }, []);

  // Set active tab based on role changes — enforce permission boundaries
  useEffect(() => {
    if (currentUser) {
      const defaultTab = getDefaultTab(currentUser.role_name);
      // If current tab is not accessible by the new role, reset to default
      if (!canAccessTab(currentUser.role_name, activeTab as TabName)) {
        setActiveTab(defaultTab);
      } else if (activeTab === 'workbench' && defaultTab !== 'workbench') {
        // Auto-switch to default tab only on initial role change
        setActiveTab(defaultTab);
      }
    }
  }, [currentUser]);

  // Update selected expense form state when selection changes
  useEffect(() => {
    if (selectedExpense) {
      setEditForm({
        vendorName: selectedExpense.vendor_name || '',
        transactionDate: selectedExpense.transaction_date ? new Date(selectedExpense.transaction_date).toISOString().split('T')[0] : '',
        subtotal: parseFloat(selectedExpense.subtotal) || 0,
        vatAmount: parseFloat(selectedExpense.vat_amount) || 0,
        totalAmount: parseFloat(selectedExpense.total_amount) || 0,
        paymentMethod: selectedExpense.payment_method || 'cash',
        isCorrupted: selectedExpense.is_corrupted || false,
        correctionNotes: selectedExpense.correction_notes || '',
        items: selectedExpense.items ? selectedExpense.items.map((it: any) => ({
          id: it.id,
          description: it.description,
          amount: parseFloat(it.amount) || 0,
          code: it.mapped_account_code || ''
        })) : []
      });
      setSuggestions({});
    } else {
      setEditForm(null);
    }
  }, [selectedExpense]);

  const handleUserChange = (userId: string) => {
    const selected = users.find(u => u.id.toString() === userId);
    if (selected) {
      setCurrentUser(selected);
      setSelectedExpense(null);
    }
  };

  const handleOcrSubmit = async (preset: any) => {
    if (!currentUser) return;
    setLoading(true);
    const payload = {
      submitterId: currentUser.id,
      vendorName: preset.vendorName,
      transactionDate: preset.transactionDate,
      subtotal: preset.subtotal,
      vatAmount: preset.vatAmount,
      totalAmount: preset.totalAmount,
      paymentMethod: preset.paymentMethod,
      items: preset.items,
      isCorrupted: preset.isCorrupted,
      correctionNotes: preset.correctionNotes
    };
    
    const res = await submitMockExpense(payload);
    if (res.success) {
      alert(`จำลองการส่งใบเสร็จสำเร็จ! ID: EXP-${res.expenseId}`);
      await refreshData();
    } else {
      alert(`เกิดข้อผิดพลาด: ${res.error}`);
    }
    setLoading(false);
  };

  const fetchCoaSuggestions = async (itemIndex: number, description: string) => {
    if (!description) return;
    setLoadingSuggestion(prev => ({ ...prev, [itemIndex]: true }));
    const res = await getSemanticSuggestions(description);
    if (res.success) {
      setSuggestions(prev => ({ ...prev, [itemIndex]: res.suggestions || [] }));
    }
    setLoadingSuggestion(prev => ({ ...prev, [itemIndex]: false }));
  };

  const handleAccountantSave = async () => {
    if (!selectedExpense || !currentUser) return;
    
    const sum = parseFloat((editForm.subtotal + editForm.vatAmount).toFixed(2));
    const total = parseFloat(editForm.totalAmount.toFixed(2));
    const matchesMath = Math.abs(sum - total) < 0.01;

    const payload = {
      vendorName: editForm.vendorName,
      transactionDate: editForm.transactionDate,
      subtotal: editForm.subtotal,
      vatAmount: editForm.vatAmount,
      totalAmount: editForm.totalAmount,
      paymentMethod: editForm.paymentMethod,
      isCorrupted: !matchesMath,
      correctionNotes: matchesMath 
        ? (editForm.correctionNotes ? `[แก้ไขและยืนยันสมการตัวเลข] ${editForm.correctionNotes}` : 'ตรวจสอบความถูกต้องและจัดผังบัญชีเรียบร้อย')
        : `[ตรวจพบข้อขัดแย้งตัวเลข] ${editForm.correctionNotes}`,
      items: editForm.items
    };

    setLoading(true);
    const res = await reviewAndCorrectExpense(selectedExpense.id, currentUser.id, payload);
    if (res.success) {
      alert('บันทึกการปรับปรุงและจัดประเภทบัญชีเสร็จสิ้น! ส่งต่อให้ผู้จัดการอนุมัติจ่าย');
      setSelectedExpense(null);
      await refreshData();
    } else {
      alert(`เกิดข้อผิดพลาด: ${res.error}`);
    }
    setLoading(false);
  };

  const handleStatusChange = async (status: string, customComment?: string) => {
    if (!selectedExpense || !currentUser) return;
    setLoading(true);
    const comment = customComment !== undefined ? customComment : actionComment;
    const res = await changeExpenseStatus(selectedExpense.id, currentUser.id, status, comment);
    if (res.success) {
      alert(`อัปเดตสถานะธุรกรรมเป็น [${status.toUpperCase()}] สำเร็จ!`);
      setSelectedExpense(null);
      setActionComment('');
      await refreshData();
    } else {
      alert(`ไม่สามารถทำรายการได้: ${res.error}`);
    }
    setLoading(false);
  };

  const getTrialBalance = () => {
    let totalDebit = 0;
    let totalCredit = 0;
    journals.forEach(j => {
      j.lines?.forEach((l: any) => {
        totalDebit += parseFloat(l.debit) || 0;
        totalCredit += parseFloat(l.credit) || 0;
      });
    });
    return {
      debit: totalDebit,
      credit: totalCredit,
      isBalanced: Math.abs(totalDebit - totalCredit) < 0.01
    };
  };

  const trialBalance = getTrialBalance();

  const getStatusBadge = (status: string) => {
    const badges: Record<string, string> = {
      ocr_extracted: 'bg-amber-500/10 text-amber-400 border border-amber-500/20',
      accountant_reviewed: 'bg-indigo-500/10 text-indigo-400 border border-indigo-500/20',
      approved: 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20',
      paid: 'bg-blue-500/10 text-blue-400 border border-blue-500/20',
      rejected: 'bg-rose-500/10 text-rose-400 border border-rose-500/20',
      draft: 'bg-slate-500/10 text-slate-400 border border-slate-500/20'
    };
    const labels: Record<string, string> = {
      ocr_extracted: 'รอนักบัญชีตรวจ',
      accountant_reviewed: 'บัญชีผ่านการตรวจสอบ',
      approved: 'อนุมัติสั่งจ่ายแล้ว',
      paid: 'จ่ายชำระแล้ว (GL)',
      rejected: 'ปฏิเสธรายการ',
      draft: 'ร่าง'
    };
    return (
      <span className={`px-2.5 py-1 rounded-full text-[10px] font-bold tracking-wide uppercase font-mono ${badges[status] || badges.draft}`}>
        {labels[status] || status}
      </span>
    );
  };

  // Determine ambient glow color based on active role
  const getAmbientGlow = (role?: string) => {
    switch (role) {
      case 'staff': return 'from-emerald-600/15 via-teal-600/5 to-transparent';
      case 'accountant': return 'from-indigo-600/20 via-purple-600/5 to-transparent';
      case 'manager': return 'from-amber-600/15 via-orange-600/5 to-transparent';
      case 'admin': return 'from-purple-600/20 via-pink-600/10 to-transparent';
      default: return 'from-indigo-600/10 to-transparent';
    }
  };

  return (
    <div className="min-h-screen relative text-slate-100 selection:bg-indigo-500 selection:text-white pb-16">
      {/* DYNAMIC ROLE-BASED AMBIENT GLOW */}
      <div className={`fixed inset-0 pointer-events-none bg-gradient-to-br ${getAmbientGlow(currentUser?.role_name)} z-0 transition-all duration-1000`} />
      
      <div className="absolute top-10 left-10 w-96 h-96 bg-indigo-500/10 rounded-full blur-3xl pointer-events-none z-0" />
      <div className="absolute top-60 right-10 w-96 h-96 bg-purple-500/10 rounded-full blur-3xl pointer-events-none z-0" />

      {/* TOP NAVBAR WITH TOP-RIGHT ROLE SWITCHER */}
      <Navbar
        users={users}
        currentUser={currentUser}
        onUserChange={handleUserChange}
        activeTab={activeTab}
        setActiveTab={setActiveTab}
        journalsCount={journals.length}
      />

      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
        {loading && (
          <div className="flex justify-center items-center py-6 glass-panel rounded-2xl mb-8 border-indigo-500/20 animate-pulse">
            <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-indigo-500"></div>
            <span className="ml-3 text-xs font-mono text-slate-300">Synchronising database ledgers...</span>
          </div>
        )}

        {/* STEPPER WIDGET FOR GUIDANCE */}
        {activeTab === 'workbench' && currentUser && (
          <WorkflowStepper
            currentStatus={selectedExpense ? selectedExpense.status : 'ocr_extracted'}
            activeRole={currentUser.role_name}
            expenseId={selectedExpense?.id}
          />
        )}

        {/* TAB 1: ROLE WORKBENCH */}
        {activeTab === 'workbench' && currentUser && (
          <>
            {currentUser.role_name === 'staff' && (
              <StaffWorkspace
                currentUser={currentUser}
                ocrPresets={ocrPresets}
                onOcrSubmit={handleOcrSubmit}
                expenses={expenses}
                onSelectExpense={setSelectedExpense}
                selectedExpense={selectedExpense}
                loading={loading}
                getStatusBadge={getStatusBadge}
              />
            )}

            {currentUser.role_name === 'accountant' && (
              <AccountantWorkspace
                currentUser={currentUser}
                expenses={expenses}
                selectedExpense={selectedExpense}
                onSelectExpense={setSelectedExpense}
                editForm={editForm}
                setEditForm={setEditForm}
                coa={coa}
                suggestions={suggestions}
                loadingSuggestion={loadingSuggestion}
                onFetchCoaSuggestions={fetchCoaSuggestions}
                onAccountantSave={handleAccountantSave}
                onStatusChange={handleStatusChange}
                loading={loading}
                getStatusBadge={getStatusBadge}
              />
            )}

            {currentUser.role_name === 'manager' && (
              <ManagerWorkspace
                currentUser={currentUser}
                expenses={expenses}
                selectedExpense={selectedExpense}
                onSelectExpense={setSelectedExpense}
                actionComment={actionComment}
                setActionComment={setActionComment}
                onStatusChange={handleStatusChange}
                loading={loading}
                getStatusBadge={getStatusBadge}
              />
            )}

            {currentUser.role_name === 'admin' && (
              <ExecutiveWorkspace
                execReport={execReport}
                activeSubTab={activeSubTab}
                setActiveSubTab={setActiveSubTab}
              />
            )}
          </>
        )}

        {/* TAB 2: GENERAL LEDGER */}
        {activeTab === 'ledger' && (
          canAccessTab(currentUser?.role_name, 'ledger') ? (
          <div className="space-y-8 animate-fade-in">
            {/* TRIAL BALANCE CARD */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
              <div className="glass-panel p-6 rounded-3xl border-emerald-500/20 relative">
                <span className="text-[10px] text-slate-400 uppercase font-black tracking-widest block font-mono">Trial Balance Debits</span>
                <span className="text-3xl font-black text-emerald-400 font-mono mt-2 block">
                  {trialBalance.debit.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿
                </span>
              </div>
              <div className="glass-panel p-6 rounded-3xl border-indigo-500/20 relative">
                <span className="text-[10px] text-slate-400 uppercase font-black tracking-widest block font-mono">Trial Balance Credits</span>
                <span className="text-3xl font-black text-indigo-400 font-mono mt-2 block">
                  {trialBalance.credit.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿
                </span>
              </div>
              <div className="glass-panel p-6 rounded-3xl flex flex-col justify-between">
                <span className="text-[10px] text-slate-400 uppercase font-black tracking-widest block font-mono">Ledger Verification</span>
                <div className="mt-3 flex items-center gap-2">
                  {trialBalance.isBalanced ? (
                    <span className="px-4 py-1.5 bg-emerald-500/10 border border-emerald-500/30 text-emerald-300 rounded-full font-bold text-xs flex items-center gap-2 shadow-lg shadow-emerald-950">
                      <span>⚖️</span> Double-Entry Balanced
                    </span>
                  ) : (
                    <span className="px-4 py-1.5 bg-rose-500/10 border border-rose-500/30 text-rose-300 rounded-full font-bold text-xs flex items-center gap-2 animate-pulse">
                      <span>🚨</span> Unbalanced Discrepancy
                    </span>
                  )}
                </div>
              </div>
            </div>

            {/* LEDGER JOURNAL BOOK */}
            <div className="glass-panel p-6 sm:p-8 rounded-3xl">
              <h2 className="text-xl font-bold text-white mb-6 flex items-center gap-2">
                <span>📒</span> สมุดรายวันทั่วไป (Double-Entry Ledger Book)
              </h2>

              {journals.length === 0 ? (
                <p className="text-center py-12 text-xs text-slate-500 font-mono">ยังไม่มีบันทึกบัญชีลง General Ledger</p>
              ) : (
                <div className="space-y-6">
                  {journals.map((j) => (
                    <div key={j.id} className="bg-slate-950/60 rounded-2xl border border-slate-900 overflow-hidden shadow-lg">
                      <div className="bg-slate-900/50 px-5 py-3.5 border-b border-slate-900 flex flex-col sm:flex-row justify-between items-start sm:items-center gap-2 font-mono">
                        <div>
                          <span className="px-2.5 py-0.5 rounded bg-indigo-600/20 text-indigo-300 border border-indigo-500/30 text-[10px] font-black mr-3">
                            JRN-{j.id}
                          </span>
                          <span className="text-xs font-bold text-white font-sans">{j.description}</span>
                        </div>
                        <div className="text-[10px] text-slate-400">
                          <span>POSTED BY: {j.submitter_name || 'SYSTEM'}</span>
                          <span className="mx-2">•</span>
                          <span>{new Date(j.entry_date).toLocaleDateString('en-GB')}</span>
                        </div>
                      </div>

                      <div className="p-4 overflow-x-auto">
                        <div className="min-w-[600px]">
                          <div className="grid grid-cols-12 text-[10px] uppercase font-bold text-slate-500 pb-2 px-2 border-b border-slate-900 font-mono">
                            <div className="col-span-2">Account Code</div>
                            <div className="col-span-5">Account Description</div>
                            <div className="col-span-2">Memo</div>
                            <div className="col-span-1.5 text-right">Debit (Dr)</div>
                            <div className="col-span-1.5 text-right">Credit (Cr)</div>
                          </div>

                          <div className="divide-y divide-slate-900/30 font-mono">
                            {j.lines?.map((line: any) => (
                              <div key={line.id} className="grid grid-cols-12 text-xs py-3 px-2 hover:bg-slate-900/20">
                                <div className="col-span-2 text-indigo-400 font-bold">{line.account_code}</div>
                                <div className="col-span-5 text-slate-200 font-sans">
                                  <span className="block font-bold">{line.account_name_th}</span>
                                  <span className="text-[10px] text-slate-500 font-mono">{line.account_name_en} ({line.account_type})</span>
                                </div>
                                <div className="col-span-2 text-slate-500 truncate text-[11px] font-sans pr-2" title={line.description}>
                                  {line.description}
                                </div>
                                <div className="col-span-1.5 text-right font-bold text-emerald-400">
                                  {parseFloat(line.debit) > 0 ? parseFloat(line.debit).toLocaleString('th-TH', { minimumFractionDigits: 2 }) + ' ฿' : '-'}
                                </div>
                                <div className="col-span-1.5 text-right font-bold text-purple-400">
                                  {parseFloat(line.credit) > 0 ? parseFloat(line.credit).toLocaleString('th-TH', { minimumFractionDigits: 2 }) + ' ฿' : '-'}
                                </div>
                              </div>
                            ))}
                          </div>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
          ) : (
            <AccessDenied roleName={currentUser?.role_name} requiredAccess="Accountant / Manager / Admin" />
          )
        )}

        {/* TAB 3: EXECUTIVE COCKPIT */}
        {activeTab === 'cockpit' && (
          canAccessTab(currentUser?.role_name, 'cockpit') ? (
            <ExecutiveWorkspace
              execReport={execReport}
              activeSubTab={activeSubTab}
              setActiveSubTab={setActiveSubTab}
            />
          ) : (
            <AccessDenied roleName={currentUser?.role_name} requiredAccess="Admin / Executive" />
          )
        )}
      </main>
    </div>
  );
}

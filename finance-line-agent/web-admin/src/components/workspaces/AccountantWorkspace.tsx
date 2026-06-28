import React from 'react';

interface AccountantWorkspaceProps {
  currentUser: any;
  expenses: any[];
  selectedExpense: any;
  onSelectExpense: (exp: any) => void;
  editForm: any;
  setEditForm: React.Dispatch<React.SetStateAction<any>>;
  coa: any[];
  suggestions: Record<number, any[]>;
  loadingSuggestion: Record<number, boolean>;
  onFetchCoaSuggestions: (itemIndex: number, description: string) => Promise<void>;
  onAccountantSave: () => Promise<void>;
  onStatusChange: (status: string, customComment?: string) => Promise<void>;
  loading: boolean;
  getStatusBadge: (status: string) => React.ReactNode;
}

export const AccountantWorkspace: React.FC<AccountantWorkspaceProps> = ({
  currentUser,
  expenses,
  selectedExpense,
  onSelectExpense,
  editForm,
  setEditForm,
  coa,
  suggestions,
  loadingSuggestion,
  onFetchCoaSuggestions,
  onAccountantSave,
  onStatusChange,
  loading,
  getStatusBadge
}) => {
  const pendingQueue = expenses.filter(e => e.status === 'ocr_extracted' || e.status === 'approved' || true);

  // Check math mismatch if editForm exists
  const isMathMismatch = editForm ? Math.abs((editForm.subtotal + editForm.vatAmount) - editForm.totalAmount) > 0.01 : false;

  return (
    <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 animate-fade-in">
      {/* LEFT COLUMN: CLAIMS QUEUE LISTING */}
      <div className="lg:col-span-5 space-y-6">
        <div className="glass-panel p-6 rounded-3xl border-indigo-500/30 relative overflow-hidden">
          <div className="flex justify-between items-center mb-4 pb-3 border-b border-slate-800">
            <div>
              <span className="text-[10px] font-mono font-bold uppercase text-indigo-400 block tracking-wider">
                Auditor Desk (ฝ่ายตรวจสอบบัญชี)
              </span>
              <h2 className="text-lg font-bold text-white flex items-center gap-2">
                <span>📑</span> คิวตรวจสอบใบเสร็จ (Audit Queue)
              </h2>
            </div>
            <span className="px-2.5 py-1 rounded-full bg-indigo-500/20 text-indigo-300 font-mono font-bold text-[10px] border border-indigo-500/30">
              {expenses.filter(e => e.status === 'ocr_extracted').length} รอตราจ
            </span>
          </div>

          <div className="space-y-2.5 max-h-[650px] overflow-y-auto pr-1">
            {expenses.length === 0 ? (
              <p className="text-center py-8 text-xs text-slate-500 font-mono">ไม่มีรายการเบิกจ่ายในระบบ</p>
            ) : (
              expenses.map((exp) => {
                const isSelected = selectedExpense?.id === exp.id;
                return (
                  <div
                    key={exp.id}
                    onClick={() => onSelectExpense(exp)}
                    className={`p-4 rounded-2xl border transition-all cursor-pointer ${
                      isSelected
                        ? 'bg-indigo-600/15 border-indigo-500 shadow-xl shadow-indigo-950 ring-1 ring-indigo-500/50'
                        : 'bg-slate-950/60 hover:bg-slate-900 border-slate-900 hover:border-slate-800 text-slate-300'
                    }`}
                  >
                    <div className="flex justify-between items-start mb-2 font-mono">
                      <span className="font-bold text-white text-xs">EXP-{exp.id}</span>
                      {getStatusBadge(exp.status)}
                    </div>

                    <div className="text-xs mb-2">
                      <span className="font-bold block truncate text-slate-200">{exp.vendor_name}</span>
                      <span className="text-[10px] text-slate-400 block truncate font-mono">
                        ผู้เบิก: {exp.submitter_name} ({exp.submitter_dept})
                      </span>
                    </div>

                    <div className="flex justify-between items-center pt-2 border-t border-slate-900/80 font-mono">
                      <span className="text-[10px] text-slate-500">
                        {new Date(exp.transaction_date).toLocaleDateString('en-GB')}
                      </span>
                      <span className="text-sm font-black text-white">
                        {parseFloat(exp.total_amount).toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿
                      </span>
                    </div>

                    {exp.is_corrupted && (
                      <div className="mt-2 text-[10px] bg-rose-500/10 border border-rose-500/20 text-rose-400 px-2 py-1 rounded font-bold flex items-center gap-1">
                        ⚠️ ตรวจพบผลรวมตัวเลขไม่ตรงสมการบัญชี
                      </div>
                    )}
                  </div>
                );
              })
            )}
          </div>
        </div>
      </div>

      {/* RIGHT COLUMN: DUAL-PANE AUDIT & COA WORKSTATION */}
      <div className="lg:col-span-7">
        {selectedExpense && editForm ? (
          <div className="space-y-6 animate-fade-in">
            {/* WORKSTATION HEADER */}
            <div className="glass-panel-heavy p-6 rounded-3xl border-indigo-500/40 relative overflow-hidden shadow-2xl">
              <div className="flex justify-between items-center pb-4 border-b border-slate-800 mb-6">
                <div>
                  <span className="text-[10px] font-mono font-black uppercase text-indigo-400 tracking-widest">
                    Double-Entry Auditor Workstation
                  </span>
                  <h3 className="text-base font-bold text-white mt-0.5 flex items-center gap-2">
                    <span>🔎</span> ตรวจสอบและจัดผังบัญชี (EXP-{selectedExpense.id})
                  </h3>
                </div>
                <span className="px-3 py-1 rounded-full bg-purple-500/10 text-purple-300 font-mono font-bold text-[10px] border border-purple-500/20">
                  ROLE: ACCOUNTANT
                </span>
              </div>

              {/* MATH DISCREPANCY SENTINEL BANNER */}
              {isMathMismatch && (
                <div className="p-4 bg-rose-950/40 border-2 border-rose-500 rounded-2xl text-rose-300 text-xs mb-6 animate-pulse shadow-lg shadow-rose-950">
                  <div className="flex items-center gap-2 font-black text-sm text-rose-400 mb-1">
                    <span>🚨</span> คำเตือน: ผลรวมคณิตศาสตร์คลาดเคลื่อน (Arithmetic Discrepancy)
                  </div>
                  <p className="font-sans leading-relaxed">
                    ยอด Subtotal ({editForm.subtotal.toLocaleString()} ฿) + VAT ({editForm.vatAmount.toLocaleString()} ฿) เท่ากับ <b>{(editForm.subtotal + editForm.vatAmount).toFixed(2)} ฿</b> แต่ยอดชำระจริงในบิลคือ <b>{editForm.totalAmount.toLocaleString()} ฿</b> (ส่วนต่าง {Math.abs((editForm.subtotal + editForm.vatAmount) - editForm.totalAmount).toFixed(2)} THB) กรุณาปรับยอดด้านล่างให้สมดุล
                  </p>
                </div>
              )}

              {/* DUAL PANE: RECEIPT RECONSTRUCTION + INPUT FORM */}
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
                {/* PANE 1: AI RECONSTRUCTED SLIP CANVAS */}
                <div className="bg-amber-50 text-slate-900 p-5 rounded-2xl font-mono shadow-2xl border-l-4 border-indigo-600 text-xs relative flex flex-col justify-between">
                  <div>
                    <div className="flex justify-between items-center border-b border-dashed border-slate-300 pb-2 mb-3">
                      <span className="font-black text-[10px] tracking-wider text-indigo-900 uppercase">LINE OCR RAW SLIP</span>
                      <span className="text-[9px] bg-indigo-100 text-indigo-800 px-1.5 py-0.5 font-bold rounded">AI EXTRACTED</span>
                    </div>
                    <div className="text-center font-black text-sm text-slate-950 mb-3 pb-2 border-b border-slate-200 truncate">
                      {editForm.vendorName || 'EXTRACTED MERCHANT'}
                    </div>
                    <div className="space-y-1.5 text-[11px] mb-4">
                      <div className="flex justify-between"><span className="text-slate-500">วันที่:</span> <span className="font-bold">{editForm.transactionDate || '--/--/----'}</span></div>
                      <div className="flex justify-between"><span className="text-slate-500">ชำระผ่าน:</span> <span className="uppercase font-bold">{editForm.paymentMethod}</span></div>
                    </div>

                    <div className="border-b border-dashed border-slate-300 pb-1 mb-2 font-bold text-[10px] text-slate-700">
                      รายการสินค้า (LINE ITEMS)
                    </div>
                    <div className="space-y-1.5 mb-4">
                      {editForm.items.map((item: any, i: number) => (
                        <div key={i} className="flex justify-between text-slate-900 text-[11px]">
                          <span className="truncate pr-2">{item.description}</span>
                          <span className="font-bold">{parseFloat(item.amount).toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿</span>
                        </div>
                      ))}
                    </div>
                  </div>

                  <div className="border-t border-dashed border-slate-300 pt-3 space-y-1 text-slate-800">
                    <div className="flex justify-between text-[11px]"><span className="text-slate-500">SUBTOTAL:</span> <span>{editForm.subtotal.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿</span></div>
                    <div className="flex justify-between text-[11px]"><span className="text-slate-500">VAT (7%):</span> <span>{editForm.vatAmount.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿</span></div>
                    <div className="flex justify-between font-black text-sm border-t border-slate-900 pt-2 mt-1 text-indigo-950">
                      <span>TOTAL PAID:</span> <span>{editForm.totalAmount.toLocaleString('th-TH', { minimumFractionDigits: 2 })} ฿</span>
                    </div>
                  </div>
                </div>

                {/* PANE 2: AUDITOR CORRECTION FIELDS */}
                <div className="space-y-3.5 bg-slate-950/70 p-4 rounded-2xl border border-slate-900 text-xs">
                  <span className="text-[10px] font-mono font-bold uppercase text-indigo-400 block mb-1">
                    ⚡ แก้ไขยอดบัญชีและสมการ (Audit Adjustments)
                  </span>

                  <div>
                    <label className="block text-[10px] text-slate-400 mb-1">ชื่อผู้จำหน่าย (Merchant)</label>
                    <input
                      type="text"
                      value={editForm.vendorName}
                      onChange={(e) => setEditForm({ ...editForm, vendorName: e.target.value })}
                      className="w-full bg-slate-900 border border-slate-800 rounded-lg px-3 py-1.5 text-xs text-white focus:outline-none focus:border-indigo-500"
                    />
                  </div>

                  <div>
                    <label className="block text-[10px] text-slate-400 mb-1">วันที่ทำรายการ</label>
                    <input
                      type="date"
                      value={editForm.transactionDate}
                      onChange={(e) => setEditForm({ ...editForm, transactionDate: e.target.value })}
                      className="w-full bg-slate-900 border border-slate-800 rounded-lg px-3 py-1.5 text-xs text-white focus:outline-none focus:border-indigo-500 font-mono"
                    />
                  </div>

                  <div className="grid grid-cols-3 gap-2 pt-1 font-mono">
                    <div>
                      <label className="block text-[9px] text-slate-400 mb-1">Subtotal</label>
                      <input
                        type="number"
                        step="0.01"
                        value={editForm.subtotal}
                        onChange={(e) => setEditForm({ ...editForm, subtotal: parseFloat(e.target.value) || 0 })}
                        className="w-full bg-slate-900 border border-slate-800 rounded px-2 py-1.5 text-xs text-white"
                      />
                    </div>
                    <div>
                      <label className="block text-[9px] text-slate-400 mb-1">VAT</label>
                      <input
                        type="number"
                        step="0.01"
                        value={editForm.vatAmount}
                        onChange={(e) => setEditForm({ ...editForm, vatAmount: parseFloat(e.target.value) || 0 })}
                        className="w-full bg-slate-900 border border-slate-800 rounded px-2 py-1.5 text-xs text-white"
                      />
                    </div>
                    <div>
                      <label className="block text-[9px] text-slate-400 mb-1">Total</label>
                      <input
                        type="number"
                        step="0.01"
                        value={editForm.totalAmount}
                        onChange={(e) => setEditForm({ ...editForm, totalAmount: parseFloat(e.target.value) || 0 })}
                        className="w-full bg-slate-900 border border-slate-800 rounded px-2 py-1.5 text-xs text-white font-bold"
                      />
                    </div>
                  </div>

                  <div>
                    <label className="block text-[10px] text-slate-400 mb-1">บันทึกคำอธิบายผู้ตรวจสอบ (Auditor Notes)</label>
                    <textarea
                      rows={2}
                      value={editForm.correctionNotes}
                      onChange={(e) => setEditForm({ ...editForm, correctionNotes: e.target.value })}
                      placeholder="ระบุเหตุผลในการแก้ไขสมการตัวเลขหรือเปลี่ยนรหัสผังบัญชี..."
                      className="w-full bg-slate-900 border border-slate-800 rounded-lg px-3 py-1.5 text-xs text-white focus:outline-none focus:border-indigo-500 font-sans"
                    />
                  </div>
                </div>
              </div>

              {/* SEMANTIC COA MAPPING WORKBENCH */}
              <div className="border-t border-slate-800 pt-6 space-y-4">
                <div className="flex justify-between items-center">
                  <div>
                    <h4 className="text-xs font-black text-white uppercase tracking-wider flex items-center gap-2 font-mono">
                      <span>🧠</span> ผังบัญชีคู่สมุทัย (Semantic COA Double-Entry Mapping)
                    </h4>
                    <p className="text-[11px] text-slate-400 mt-0.5">ใช้ AI BGE-M3 วิเคราะห์ชื่อสินค้าและแนะนำรหัสหมวดหมู่บัญชีที่ถูกต้องตามมาตรฐานการบัญชี</p>
                  </div>
                </div>

                <div className="space-y-3">
                  {editForm.items.map((item: any, idx: number) => (
                    <div key={idx} className="bg-slate-950/80 p-4 rounded-2xl border border-slate-900 space-y-3">
                      <div className="flex justify-between items-center font-mono">
                        <span className="text-xs font-bold text-indigo-400">รายการที่ #{idx + 1}: {item.amount.toLocaleString()} ฿</span>
                        <span className="text-[10px] text-slate-500">Dr. 5xxxxx Operating Expense</span>
                      </div>

                      <div className="grid grid-cols-1 md:grid-cols-12 gap-3 items-center">
                        <div className="md:col-span-5">
                          <input
                            type="text"
                            value={item.description}
                            onChange={(e) => {
                              const updated = [...editForm.items];
                              updated[idx].description = e.target.value;
                              setEditForm({ ...editForm, items: updated });
                            }}
                            className="w-full bg-slate-900 border border-slate-800 rounded px-3 py-2 text-xs text-slate-200"
                          />
                        </div>

                        <div className="md:col-span-5">
                          <select
                            value={item.code}
                            onChange={(e) => {
                              const updated = [...editForm.items];
                              updated[idx].code = e.target.value;
                              setEditForm({ ...editForm, items: updated });
                            }}
                            className="w-full bg-slate-900 border border-slate-800 text-xs rounded px-3 py-2 text-slate-200 font-mono"
                          >
                            <option value="">-- แนะนำเลือกผังบัญชี --</option>
                            {coa.map(c => (
                              <option key={c.code} value={c.code}>
                                [{c.code}] {c.name_th} ({c.name})
                              </option>
                            ))}
                          </select>
                        </div>

                        <div className="md:col-span-2">
                          <button
                            type="button"
                            onClick={() => onFetchCoaSuggestions(idx, item.description)}
                            disabled={loadingSuggestion[idx]}
                            className="w-full px-3 py-2 bg-gradient-to-r from-indigo-600 to-purple-600 hover:from-indigo-500 hover:to-purple-500 text-white rounded-lg text-[11px] font-bold transition-all shadow-md flex items-center justify-center gap-1 cursor-pointer"
                          >
                            <span>{loadingSuggestion[idx] ? '⏳' : '🤖'}</span>
                            <span>{loadingSuggestion[idx] ? 'วิเคราะห์...' : 'AI แนะนำ'}</span>
                          </button>
                        </div>
                      </div>

                      {/* VECTOR SUGGESTIONS RESULT */}
                      {suggestions[idx] && suggestions[idx].length > 0 && (
                        <div className="p-2.5 bg-indigo-950/30 rounded-xl border border-indigo-500/20 space-y-1.5 animate-fade-in">
                          <span className="text-[10px] text-indigo-300 font-bold block font-mono">
                            ✨ แนะนำผังบัญชีที่มีความหมายใกล้เคียง (Semantic Cosine Similarity):
                          </span>
                          <div className="grid grid-cols-1 sm:grid-cols-2 gap-1.5">
                            {suggestions[idx].map((sugg) => (
                              <button
                                key={sugg.code}
                                type="button"
                                onClick={() => {
                                  const updated = [...editForm.items];
                                  updated[idx].code = sugg.code;
                                  setEditForm({ ...editForm, items: updated });
                                }}
                                className="text-left p-2 bg-slate-950 hover:bg-indigo-900/50 border border-slate-800 hover:border-indigo-500 rounded-lg flex justify-between items-center transition-all cursor-pointer"
                              >
                                <span className="text-[11px] text-slate-200 truncate font-sans pr-2">[{sugg.code}] {sugg.name_th}</span>
                                <span className="text-[10px] text-indigo-400 font-mono font-bold">{sugg.similarity}%</span>
                              </button>
                            ))}
                          </div>
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              </div>

              {/* ACTION BUTTONS FOR ACCOUNTANT */}
              <div className="mt-8 pt-6 border-t border-slate-800 flex flex-col sm:flex-row gap-4">
                {selectedExpense.status === 'ocr_extracted' && (
                  <button
                    onClick={onAccountantSave}
                    disabled={loading}
                    className="flex-1 bg-gradient-to-r from-indigo-600 via-purple-600 to-pink-600 hover:from-indigo-500 hover:to-pink-500 text-white font-extrabold py-3.5 rounded-2xl text-xs transition-all shadow-xl shadow-indigo-500/20 cursor-pointer text-center"
                  >
                    💾 ยืนยันสมการบัญชีและส่งต่อให้ผู้จัดการอนุมัติ (Verify & Send to Manager)
                  </button>
                )}

                {selectedExpense.status === 'approved' && (
                  <button
                    onClick={() => onStatusChange('paid', 'โอนเงินชำระคืนพนักงานและบันทึกลงสมุดบัญชีแยกประเภทเรียบร้อย')}
                    disabled={loading}
                    className="flex-1 bg-gradient-to-r from-blue-600 to-indigo-600 hover:from-blue-500 hover:to-indigo-500 text-white font-extrabold py-3.5 rounded-2xl text-xs transition-all shadow-xl shadow-blue-500/20 cursor-pointer text-center"
                  >
                    💳 ดำเนินการจ่ายเงินและโพสต์ลง General Ledger (Settle Payment & Post GL)
                  </button>
                )}
              </div>
            </div>
          </div>
        ) : (
          <div className="glass-panel p-12 rounded-3xl border border-slate-800 border-dashed text-center flex flex-col items-center justify-center h-[500px] text-slate-500">
            <span className="text-5xl mb-4">👩‍🔬</span>
            <h3 className="text-sm font-bold text-white">โต๊ะทำงานนักบัญชียังว่างอยู่ (Auditor Idle)</h3>
            <p className="text-xs text-slate-400 mt-1 max-w-sm font-sans">
              คลิกเลือกรายการเบิกจ่ายจากคิวทางซ้ายมือเพื่อตรวจสอบผลรวมตัวเลข จัดกลุ่มผังบัญชี COA และโพสต์รายการลง GL
            </p>
          </div>
        )}
      </div>
    </div>
  );
};

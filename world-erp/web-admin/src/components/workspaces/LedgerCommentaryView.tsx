'use client';

import React, { useMemo, useState } from 'react';
import { AiActionButton } from '@/components/ai/AiActionButton';

interface JournalLine {
  id: number;
  account_code: string;
  account_name_th?: string;
  account_name_en?: string;
  account_type?: string;
  description?: string;
  debit: string | number;
  credit: string | number;
}

interface Journal {
  id: number;
  description: string;
  entry_date: string;
  submitter_name?: string;
  lines?: JournalLine[];
}

interface LedgerCommentaryViewProps {
  journals: Journal[];
}

const fmt = (n: any) =>
  parseFloat(n || 0).toLocaleString('th-TH', { minimumFractionDigits: 2 });

export const LedgerCommentaryView: React.FC<LedgerCommentaryViewProps> = ({ journals }) => {
  const [selectedLine, setSelectedLine] = useState<JournalLine | null>(null);

  // Compute top-10 lines by absolute amount as variance candidates
  const topLines = useMemo(() => {
    const all: Array<JournalLine & { journalId: number; journalDate: string; journalDesc: string }> = [];
    for (const j of journals) {
      for (const l of j.lines || []) {
        all.push({
          ...l,
          journalId: j.id,
          journalDate: j.entry_date,
          journalDesc: j.description,
        });
      }
    }
    return all
      .map((l) => ({
        ...l,
        _abs: Math.max(parseFloat(String(l.debit)) || 0, parseFloat(String(l.credit)) || 0),
      }))
      .sort((a, b) => b._abs - a._abs)
      .slice(0, 10);
  }, [journals]);

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="glass-panel p-6 rounded-3xl border-indigo-500/30 bg-gradient-to-br from-indigo-950/20 to-slate-950">
        <span className="text-[10px] font-mono font-black uppercase text-indigo-400 block tracking-wider">
          📒 GL Commentary Engine
        </span>
        <h2 className="text-xl font-bold text-white">Variance Analysis & Line-by-Line AI Commentary</h2>
        <p className="text-xs text-slate-400 mt-1">
          AI explains unusual ledger lines in plain language. Pick any high-value line below to ask for an explanation.
        </p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="glass-panel p-5 rounded-3xl border-slate-800">
          <h3 className="text-sm font-bold text-white mb-3 flex items-center gap-2">
            <span>🔍</span> Top 10 Lines by Amount
          </h3>
          <div className="space-y-1.5 max-h-[600px] overflow-y-auto">
            {topLines.length === 0 ? (
              <p className="text-center py-8 text-xs text-slate-500 font-mono">No ledger lines yet</p>
            ) : (
              topLines.map((l) => {
                const isSel = selectedLine?.id === l.id;
                const isDebit = parseFloat(String(l.debit)) > 0;
                return (
                  <button
                    key={l.id}
                    type="button"
                    onClick={() => setSelectedLine(l)}
                    className={`w-full text-left p-2.5 rounded-xl border transition-all ${
                      isSel
                        ? 'bg-indigo-600/15 border-indigo-500 ring-1 ring-indigo-500/40'
                        : 'bg-slate-950/60 border-slate-900 hover:border-slate-800'
                    }`}
                  >
                    <div className="flex items-center justify-between text-[11px] font-mono">
                      <span className="text-indigo-400 font-bold">[{l.account_code}] {l.account_name_th || l.account_name_en || l.account_code}</span>
                      <span className={isDebit ? 'text-emerald-300 font-bold' : 'text-purple-300 font-bold'}>
                        {fmt(isDebit ? l.debit : l.credit)} THB
                      </span>
                    </div>
                    <div className="text-[10px] text-slate-500 mt-1 truncate">
                      {l.description || l.journalDesc}
                    </div>
                    <div className="text-[9px] text-slate-600 mt-0.5 font-mono">
                      JRN-{l.journalId} · {new Date(l.journalDate).toLocaleDateString('en-GB')}
                    </div>
                  </button>
                );
              })
            )}
          </div>
        </div>

        <div className="glass-panel p-5 rounded-3xl border-slate-800">
          <h3 className="text-sm font-bold text-white mb-3 flex items-center gap-2">
            <span>💬</span> AI Commentary
          </h3>
          {!selectedLine ? (
            <p className="text-center py-12 text-xs text-slate-500 font-mono">
              Select a line on the left to generate an explanation.
            </p>
          ) : (
            <div className="space-y-3">
              <div className="p-3 rounded-2xl bg-slate-950/60 border border-slate-900 text-[11px] font-mono">
                <div className="text-indigo-300 font-bold mb-1">
                  [{selectedLine.account_code}] {selectedLine.account_name_th || selectedLine.account_name_en}
                </div>
                <div className="text-slate-300">
                  {selectedLine.description || '(no memo)'}
                </div>
                <div className="flex justify-between mt-2 text-[10px]">
                  <span className="text-slate-500">
                    Dr {fmt(selectedLine.debit)} · Cr {fmt(selectedLine.credit)}
                  </span>
                  <span className="text-slate-500">Type: {selectedLine.account_type || '—'}</span>
                </div>
              </div>
              <AiActionButton
                sectionKey="ledger:commentary"
                task="chat"
                systemPrompt="You are a senior accountant explaining a single GL line to a non-finance stakeholder. Output 2-3 short sentences: (1) what this line represents in plain language, (2) what kind of business activity usually produces it, (3) one thing to verify or watch. No bullet points, no markdown. Match the language of the input."
                input={`Account: [${selectedLine.account_code}] ${selectedLine.account_name_th || selectedLine.account_name_en || ''}\nAccount type: ${selectedLine.account_type || 'unknown'}\nMemo: ${selectedLine.description || '(none)'}\nDebit: ${fmt(selectedLine.debit)} THB\nCredit: ${fmt(selectedLine.credit)} THB`}
                buttonLabel="Explain this line"
                resultTitle="AI Commentary"
                tone="indigo"
                glyph="💬"
                size="md"
              />
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

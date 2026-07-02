'use client';

import React, { useState } from 'react';
import { AiActionButton } from './AiActionButton';

interface NotificationItem {
  id?: string | number;
  type: string;
  message: string;
  createdAt: string;
  severityClass?: string;
}

interface NotificationDigestProps {
  items: NotificationItem[];
}

export const NotificationDigest: React.FC<NotificationDigestProps> = ({ items }) => {
  const [open, setOpen] = useState(false);

  if (items.length === 0) return null;

  const recent = items.slice(0, 15);
  const input = recent
    .map((it, i) => `${i + 1}. [${it.type}] ${it.message}`)
    .join('\n');

  return (
    <div className="mt-3 pt-3 border-t border-slate-800/80">
      <div className="flex items-center justify-between mb-1.5">
        <div className="text-[10px] font-mono uppercase tracking-wide text-indigo-300">
          🧠 AI Digest
        </div>
        <button
          type="button"
          onClick={() => setOpen((v) => !v)}
          className="text-[10px] text-slate-500 hover:text-slate-300 font-mono"
        >
          {open ? '▲ Hide' : '▼ Show'}
        </button>
      </div>
      {open && (
        <AiActionButton
          sectionKey="notification:digest"
          task="chat"
          systemPrompt="You summarize a stream of recent business events for a manager who has been away. Given a list of timestamped domain events (expense.submitted, pr.advanced, etc.), output 2-3 short sentences: (1) overall activity volume, (2) anything that stands out (rejections, overrides, large amounts), (3) one action the manager should consider. Same language as the input messages. No bullet points, no markdown."
          input={`Recent ${recent.length} events (most recent first):\n${input}`}
          buttonLabel="Summarize recent activity"
          resultTitle="Activity Digest"
          tone="indigo"
          glyph="🧠"
        />
      )}
    </div>
  );
};

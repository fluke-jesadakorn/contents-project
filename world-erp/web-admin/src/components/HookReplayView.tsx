'use client';

import React, { useEffect, useState } from 'react';
import { useToast } from '@/components/ui/Toast';

interface HookEvent {
  id: number;
  providerId: string;
  externalId: string | null;
  eventType: string;
  receivedAt: string;
  status: 'received' | 'processed' | 'failed' | 'rejected';
  signatureOk: boolean;
  replayCount: number;
}

const STATUS_TONE: Record<HookEvent['status'], string> = {
  received: 'bg-cyan-500/15 text-cyan-200 border-cyan-500/40',
  processed: 'bg-emerald-500/15 text-emerald-200 border-emerald-500/40',
  failed: 'bg-rose-500/15 text-rose-200 border-rose-500/40',
  rejected: 'bg-slate-500/15 text-slate-200 border-slate-500/40',
};

export const HookReplayView: React.FC<{ currentUser: any }> = ({ currentUser: _currentUser }) => {
  const toast = useToast();
  const [events, setEvents] = useState<HookEvent[]>([]);
  const [filter, setFilter] = useState<'all' | 'received' | 'failed' | 'rejected'>('all');
  const [loading, setLoading] = useState(false);
  const [busyId, setBusyId] = useState<number | null>(null);

  async function load() {
    setLoading(true);
    try {
      const qs = filter === 'all' ? '' : `?status=${filter}`;
      const res = await fetch(`/api/hook/events${qs}`).then((r) => r.json());
      if (res.error) toast.error(res.error);
      else setEvents(res.events || []);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filter]);

  async function replay(id: number) {
    setBusyId(id);
    try {
      const res = await fetch(`/api/hook/events/${id}/replay`, { method: 'POST' }).then((r) => r.json());
      if (res.ok) {
        toast.success(`Replayed #${id}`, 'Hook');
        load();
      } else {
        toast.error(`Cannot replay: ${res.reason || 'unknown'}`);
      }
    } finally {
      setBusyId(null);
    }
  }

  return (
    <div className="space-y-4 animate-fade-in">
      <div className="glass-panel p-6 rounded-3xl border-slate-700/40 bg-gradient-to-br from-slate-900/40 to-slate-950">
        <span className="text-xs font-mono font-black uppercase text-slate-400 block tracking-wider">
          🪝 Hook Inbox
        </span>
        <h2 className="text-xl font-bold text-white">Webhook Events</h2>
        <p className="text-xs text-slate-400 mt-1">
          Recent inbound webhooks from LINE and generic providers. Replay failed events to re-run the side effect.
        </p>
        <div className="flex gap-1 p-1 rounded-xl bg-slate-950/60 border border-slate-800 text-xs font-mono uppercase tracking-wider mt-4 w-fit">
          {(['all', 'received', 'failed', 'rejected'] as const).map((f) => (
            <button
              key={f}
              type="button"
              onClick={() => setFilter(f)}
              className={[
                'px-2.5 py-1 rounded-lg transition-all',
                filter === f
                  ? 'bg-cyan-500/25 border border-cyan-500/50 text-cyan-100'
                  : 'border border-transparent text-slate-400 hover:text-white',
              ].join(' ')}
            >
              {f}
            </button>
          ))}
        </div>
      </div>

      {loading && (
        <div className="glass-panel rounded-2xl px-4 py-3 text-xs text-slate-400">Loading…</div>
      )}

      {!loading && events.length === 0 && (
        <div className="glass-panel rounded-2xl px-4 py-6 text-center text-xs text-slate-500">
          No {filter === 'all' ? '' : filter} webhook events.
        </div>
      )}

      {!loading && events.length > 0 && (
        <div className="space-y-2">
          {events.map((e) => (
            <div
              key={e.id}
              className="glass-panel rounded-2xl px-4 py-3 border-slate-800 flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between"
            >
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="text-xs font-mono text-slate-500">#{e.id}</span>
                  <span className="text-xs text-white font-mono">{e.eventType}</span>
                  <span className={`inline-flex items-center gap-1 px-1.5 py-0.5 rounded-full border text-xs font-mono uppercase tracking-wider ${STATUS_TONE[e.status]}`}>
                    {e.status}
                  </span>
                  {e.replayCount > 0 && (
                    <span className="text-xs font-mono text-amber-300">
                      ↻ {e.replayCount}× replay
                    </span>
                  )}
                </div>
                <div className="mt-1 text-xs font-mono text-slate-500 truncate">
                  {e.providerId} · {e.externalId || '—'} · {new Date(e.receivedAt).toLocaleString()}
                </div>
              </div>
              <div className="flex gap-2 shrink-0">
                <button
                  type="button"
                  disabled={busyId === e.id || !e.signatureOk || e.status === 'rejected'}
                  onClick={() => replay(e.id)}
                  className="px-3 py-1.5 rounded-lg bg-cyan-500/20 border border-cyan-500/40 text-cyan-100 text-xs font-mono uppercase tracking-wider hover:bg-cyan-500/30 disabled:opacity-40"
                >
                  {busyId === e.id ? '…' : '↻ Replay'}
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};

export default HookReplayView;
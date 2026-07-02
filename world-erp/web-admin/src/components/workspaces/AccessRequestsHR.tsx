'use client';

import React, { useEffect, useState } from 'react';
import { useToast } from '@/components/ui/Toast';
import { useCan } from '@/lib/rbac/client';

interface AccessRequestsHRProps {
  currentUser: any;
}

export const AccessRequestsHR: React.FC<AccessRequestsHRProps> = ({ currentUser }) => {
  const toast = useToast();
  const [requests, setRequests] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState<'pending' | 'approved' | 'denied' | 'all'>('pending');
  const [busyId, setBusyId] = useState<number | null>(null);

  const rbacRoleId = currentUser?.rbac_role_id ?? null;
  const canResolveFlag = useCan(rbacRoleId, 'access-request-resolve', 'update');
  const canResolve = canResolveFlag !== false;

  async function load() {
    setLoading(true);
    try {
      const status = filter === 'all' ? undefined : filter;
      const url = status ? `/api/access-requests?status=${status}` : '/api/access-requests';
      const res = await fetch(url).then((r) => r.json());
      if (res.error) toast.error(res.error);
      else setRequests(res.requests || []);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filter]);

  async function resolve(id: number, decision: 'approved' | 'denied') {
    setBusyId(id);
    try {
      const res = await fetch(`/api/access-requests/${id}/resolve`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ decision }),
      }).then((r) => r.json());
      if (res.updated) {
        toast.success(decision === 'approved' ? 'Approved' : 'Denied');
        load();
      } else {
        toast.error(res.error || 'No change');
      }
    } finally {
      setBusyId(null);
    }
  }

  const isHrManager = canResolve;

  return (
    <div className="space-y-3 animate-fade-in">
      <div className="flex items-center gap-2">
        <h2 className="text-sm font-black uppercase tracking-wider text-slate-200">
          ✉ Access Requests
        </h2>
        <span className="text-[10px] font-mono text-slate-500">
          {requests.length} item{requests.length === 1 ? '' : 's'}
        </span>
        <div className="flex-1" />
        <div className="flex gap-1 p-1 rounded-xl bg-slate-950/60 border border-slate-800 text-[10px] font-mono uppercase tracking-wider">
          {(['pending', 'approved', 'denied', 'all'] as const).map((f) => (
            <button
              key={f}
              type="button"
              onClick={() => setFilter(f)}
              aria-current={filter === f ? 'page' : undefined}
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

      {!loading && requests.length === 0 && (
        <div className="glass-panel rounded-2xl px-4 py-6 text-center text-xs text-slate-500">
          No {filter === 'all' ? '' : filter} access requests.
        </div>
      )}

      {!loading && requests.length > 0 && (
        <ul className="space-y-2">
          {requests.map((r) => (
            <li
              key={r.id}
              className="glass-panel rounded-2xl px-4 py-3 border-slate-800 flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between"
            >
              <div className="min-w-0">
                <div className="flex items-center gap-2">
                  <span className="text-[10px] font-mono uppercase tracking-wider text-slate-500">
                    {new Date(r.created_at).toLocaleString()}
                  </span>
                  <StatusBadge status={r.status} />
                </div>
                <div className="mt-1 text-sm text-white font-bold">
                  {r.actor_name} <span className="text-slate-500 font-normal">wants</span> {r.tile_title || r.tile_id}
                </div>
                {r.actor_department && (
                  <div className="text-[11px] text-slate-400">Dept: {r.actor_department}</div>
                )}
                {r.note && (
                  <div className="mt-1 text-[12px] text-slate-300 whitespace-pre-wrap">{r.note}</div>
                )}
                <div className="mt-1 text-[10px] font-mono text-slate-500">
                  Routed to: {r.target_name || '—'} ({r.target_role})
                </div>
                {r.resolved_at && (
                  <div className="mt-1 text-[10px] font-mono text-slate-500">
                    {r.status === 'approved' ? '✓' : '✗'} {r.resolver_name || '—'} · {r.resolved_note || ''}
                  </div>
                )}
              </div>
              {isHrManager && r.status === 'pending' && (
                <div className="flex gap-2 shrink-0">
                  <button
                    type="button"
                    disabled={busyId === r.id}
                    onClick={() => resolve(r.id, 'approved')}
                    className="px-3 py-1.5 rounded-lg bg-emerald-500/20 border border-emerald-500/40 text-emerald-100 text-[10px] font-mono uppercase tracking-wider hover:bg-emerald-500/30 disabled:opacity-50"
                  >
                    ✓ Approve
                  </button>
                  <button
                    type="button"
                    disabled={busyId === r.id}
                    onClick={() => resolve(r.id, 'denied')}
                    className="px-3 py-1.5 rounded-lg bg-rose-500/20 border border-rose-500/40 text-rose-100 text-[10px] font-mono uppercase tracking-wider hover:bg-rose-500/30 disabled:opacity-50"
                  >
                    ✗ Deny
                  </button>
                </div>
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
};

const StatusBadge: React.FC<{ status: string }> = ({ status }) => {
  const tone =
    status === 'pending'
      ? 'bg-amber-500/15 text-amber-200 border-amber-500/40'
      : status === 'approved'
        ? 'bg-emerald-500/15 text-emerald-200 border-emerald-500/40'
        : 'bg-rose-500/15 text-rose-200 border-rose-500/40';
  return (
    <span className={`inline-flex items-center gap-1 px-1.5 py-0.5 rounded-full border text-[9px] font-mono uppercase tracking-wider ${tone}`}>
      {status}
    </span>
  );
};
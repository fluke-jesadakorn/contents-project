'use client';

import React, { useEffect, useMemo, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { UserAvatar, roleGlyph, roleLabel, roleBadge, type StaffLevel } from './UserAvatar';
import { ROLE_RANK, ROLE_LEVEL as ROLE_LEVEL_DISPLAY, type DisplayRoleName } from '@/lib/roles/display';

const LEVEL_ORDER: StaffLevel[] = [1, 2, 3, 4, 5];

const LEVEL_META: Record<StaffLevel, { th: string; icon: string; accent: string }> = {
  1: { th: 'P1 · Executive',         icon: '👑', accent: 'bg-rose-500/10 text-rose-200 border-rose-500/40' },
  2: { th: 'P2 · Senior Management', icon: '🛡️', accent: 'bg-purple-500/10 text-purple-200 border-purple-500/40' },
  3: { th: 'P3 · Middle Management', icon: '🧭', accent: 'bg-amber-500/10 text-amber-200 border-amber-500/40' },
  4: { th: 'P4 · Senior Staff',      icon: '👥', accent: 'bg-cyan-500/10 text-cyan-200 border-cyan-500/40' },
  5: { th: 'P5 · Staff',             icon: '📋', accent: 'bg-emerald-500/10 text-emerald-200 border-emerald-500/40' },
};

const ROLE_ORDER = ROLE_RANK;

function staffLevelOf(u: any): StaffLevel {
  const lv = u.staff_level;
  if (lv === 1 || lv === 2 || lv === 3 || lv === 4 || lv === 5) return lv;
  const role = u.role_name || '';
  return ROLE_LEVEL_DISPLAY[role as DisplayRoleName] ?? 5;
}

interface PersonaMenuProps {
  users: any[];
  currentUser: any;
}

export const PersonaMenu: React.FC<PersonaMenuProps> = ({ users, currentUser }) => {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [highlight, setHighlight] = useState(0);
  const buttonRef = useRef<HTMLButtonElement | null>(null);
  const rootRef = useRef<HTMLDivElement | null>(null);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return users;
    return users.filter(
      (u) =>
        u.fullname?.toLowerCase().includes(q) ||
        u.employee_code?.toLowerCase().includes(q) ||
        u.role_name?.toLowerCase().includes(q)
    );
  }, [users, query]);

  const levelBuckets = useMemo(() => {
    const buckets: Record<StaffLevel, any[]> = { 1: [], 2: [], 3: [], 4: [], 5: [] };
    for (const u of filtered) {
      const lv = staffLevelOf(u);
      buckets[lv].push(u);
    }
    for (const lv of LEVEL_ORDER) {
      buckets[lv].sort(
        (a, b) =>
          (ROLE_ORDER[a.role_name as DisplayRoleName] ?? 99) - (ROLE_ORDER[b.role_name as DisplayRoleName] ?? 99) ||
          (a.fullname || '').localeCompare(b.fullname || '')
      );
    }
    return buckets;
  }, [filtered]);

  const grouped = useMemo(() => {
    const out: { level: StaffLevel; role: string; items: any[] }[] = [];
    for (const level of LEVEL_ORDER) {
      const byRole: Record<string, any[]> = {};
      for (const u of levelBuckets[level]) {
        const k = u.role_name || 'other';
        if (!byRole[k]) byRole[k] = [];
        byRole[k].push(u);
      }
      const rolesInLevel = Object.keys(byRole).sort(
        (a, b) => (ROLE_ORDER[a as DisplayRoleName] ?? 99) - (ROLE_ORDER[b as DisplayRoleName] ?? 99)
      );
      for (const role of rolesInLevel) {
        if (byRole[role]?.length) {
          out.push({ level, role, items: byRole[role] });
        }
      }
    }
    return out;
  }, [levelBuckets]);

  const flat = useMemo(() => grouped.flatMap((g) => g.items), [grouped]);

  const selectUser = async (u: any) => {
    setOpen(false);
    try {
      await fetch('/api/actor', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ id: u.id }),
      });
    } catch {}
    router.refresh();
  };

  useEffect(() => {
    if (!open) {
      setQuery('');
      setHighlight(0);
    }
  }, [open]);

  useEffect(() => {
    function onExternal() { setOpen(true); }
    window.addEventListener('world-erp:open-persona', onExternal);
    return () => window.removeEventListener('world-erp:open-persona', onExternal);
  }, []);

  useEffect(() => {
    if (!open) return;
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        setOpen(false);
        buttonRef.current?.focus();
      } else if (e.key === 'ArrowDown') {
        e.preventDefault();
        setHighlight((h) => Math.min(h + 1, flat.length - 1));
      } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        setHighlight((h) => Math.max(h - 1, 0));
      } else if (e.key === 'Enter') {
        const u = flat[highlight];
        if (u) {
          selectUser(u);
        }
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, flat.length, highlight]);

  useEffect(() => {
    if (open && flat.length) setHighlight(0);
  }, [query, open, flat.length]);

  return (
    <div className="relative" ref={rootRef}>
      <button
        ref={buttonRef}
        type="button"
        onClick={() => setOpen((v) => !v)}
        aria-haspopup="menu"
        aria-expanded={open}
        className={[
          'flex items-center gap-2.5 pl-1.5 pr-3 py-1.5 rounded-2xl border transition-all cursor-pointer shadow-xl',
          open
            ? 'bg-slate-900 border-indigo-500 ring-2 ring-indigo-500/20'
            : 'bg-slate-900/60 hover:bg-slate-900 border-slate-800 hover:border-slate-700',
        ].join(' ')}
      >
        <UserAvatar fullname={currentUser?.fullname} role={currentUser?.role_name} size="sm" />
        <div className="text-left hidden md:block">
          <span className="block text-xs font-bold text-white leading-tight">
            {currentUser?.fullname?.split(' ')[0] || 'User'}
          </span>
          <span
            className={[
              'inline-block px-1.5 py-0.2 rounded text-[8px] font-mono font-bold uppercase mt-0.5 border',
              roleBadge(currentUser?.role_name),
            ].join(' ')}
          >
            {roleLabel(currentUser?.role_name)}
          </span>
        </div>
        <span
          className="text-slate-400 text-[10px] ml-1 transition-transform duration-200"
          style={{ transform: open ? 'rotate(180deg)' : 'rotate(0deg)' }}
          aria-hidden
        >
          ▼
        </span>
      </button>

      {open && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => setOpen(false)} aria-hidden />
          <div
            role="menu"
            className="absolute right-0 mt-2 w-80 glass-panel-heavy rounded-2xl shadow-2xl shadow-black p-2 z-50 animate-fade-in flex flex-col max-h-[70vh]"
          >
            <div className="px-3 pt-2 pb-1 text-[10px] font-mono font-bold uppercase tracking-wider text-slate-400 flex items-center justify-between">
              <span>Switch User Role</span>
              <span className="text-slate-500 normal-case font-normal">{flat.length}/{users.length}</span>
            </div>
            <div className="px-1 pt-1 pb-2">
              <input
                autoFocus
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="Search by name, code, or role…"
                className="w-full px-3 py-2 rounded-xl bg-slate-950/80 border border-slate-800 text-xs text-white placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30 focus:border-indigo-500/60"
              />
            </div>

            <div className="flex-1 min-h-0 overflow-y-auto pb-1">
              {grouped.length === 0 ? (
                <div className="px-4 py-8 text-center text-xs text-slate-500 font-mono">
                  No users matching &quot;{query}&quot;
                </div>
              ) : (
                (() => {
                  let lastLevel: StaffLevel | null = null;
                  return grouped.map((g) => {
                    const showLevelHeader = lastLevel !== g.level;
                    lastLevel = g.level;
                    return (
                      <React.Fragment key={`${g.level}-${g.role}`}>
                        {showLevelHeader && (
                          <div
                            className={[
                              'mt-2 mb-1 mx-1 px-2 py-1 text-[9px] uppercase tracking-widest font-mono border rounded-md flex items-center gap-1.5',
                              LEVEL_META[g.level].accent,
                            ].join(' ')}
                          >
                            <span>{LEVEL_META[g.level].icon}</span>
                            <span>{LEVEL_META[g.level].th}</span>
                          </div>
                        )}
                        <div className="space-y-0.5">
                          {g.items.map((u) => {
                            const idx = flat.findIndex((f) => f.id === u.id);
                            const selected = currentUser?.id === u.id;
                            const focused = idx === highlight;
                            return (
                              <button
                                key={u.id}
                                role="menuitem"
                                type="button"
                                onClick={() => selectUser(u)}
                                onMouseEnter={() => setHighlight(idx)}
                                className={[
                                  'w-full flex items-center gap-3 px-2 py-2 rounded-xl text-left transition-all',
                                  focused ? 'bg-slate-900' : 'bg-transparent',
                                  selected ? 'border border-indigo-500/40' : 'border border-transparent hover:border-slate-800',
                                ].join(' ')}
                              >
                                <UserAvatar fullname={u.fullname} role={u.role_name} level={u.level} size="sm" />
                                <div className="flex-1 min-w-0">
                                  <div className="flex items-center justify-between">
                                    <span className="text-xs font-bold truncate text-white">{u.fullname}</span>
                                    {selected && <span className="text-indigo-400 text-xs font-bold ml-1">✓</span>}
                                  </div>
                                  <div className="flex items-center gap-1.5 mt-0.5 flex-wrap">
                                    <span className="text-[9px] text-slate-500 font-mono">{u.employee_code}</span>
                                    {typeof u.level === 'number' && (
                                      <span className="text-[9px] text-slate-600 font-mono">L{u.level}</span>
                                    )}
                                    <span
                                      className={[
                                        'px-1.5 py-0.5 rounded text-[8px] font-mono font-bold uppercase border',
                                        roleBadge(u.role_name),
                                      ].join(' ')}
                                    >
                                      {roleLabel(u.role_name)}
                                    </span>
                                  </div>
                                </div>
                                <span className="text-base leading-none opacity-70">{roleGlyph(u.role_name)}</span>
                              </button>
                            );
                          })}
                        </div>
                      </React.Fragment>
                    );
                  });
                })()
              )}
            </div>

            <div className="px-3 py-2 border-t border-slate-800/80 flex items-center justify-between text-[9px] text-slate-500 font-mono">
              <span>↑↓ Select · Enter Confirm · Esc Close</span>
              <span className={['px-1.5 py-0.5 rounded border', roleBadge(currentUser?.role_name)].join(' ')}>
                ● {roleLabel(currentUser?.role_name)}
              </span>
            </div>
          </div>
        </>
      )}
    </div>
  );
};

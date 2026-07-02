'use client';

import React, { useState } from 'react';
import { NotificationDigest } from './NotificationDigest';

export interface NotificationItem {
  id: string | number;
  type: string;
  message: string;
  createdAt: string;
  severityClass?: string;
  readAt?: string | null;
}

export interface NotificationPanelProps {
  items: NotificationItem[];
  onClose: () => void;
  onToggleRead?: (id: string | number, currentlyRead: boolean) => void;
  onClear?: (id: string | number) => void;
  onMarkAllRead?: () => void;
  onClearAll?: () => void;
  filter?: 'all' | 'unread';
  onFilterChange?: (next: 'all' | 'unread') => void;
  scoped?: boolean;
}

const noopClose = () => {};

const GLYPH_BY_TYPE: Record<string, string> = {
  'expense.submitted': '🧾',
  'expense.advanced': '🛡️',
  'expense.paid': '💳',
  'expense.rejected': '⛔',
  'ceo.override': '⚡',
  'pr.submitted': '🛒',
  'pr.advanced': '🛒',
  'pr.rejected': '⛔',
  'po.created': '📦',
  'po.advanced': '📦',
  'po.settled': '✅',
  'policy.updated': '⚙️',
};

function relTime(iso: string): string {
  const ms = Date.now() - new Date(iso).getTime();
  const s = Math.floor(ms / 1000);
  if (s < 60) return `${s}s ago`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h ago`;
  const d = Math.floor(h / 24);
  return `${d}d ago`;
}

export const NotificationPanel: React.FC<NotificationPanelProps> = ({
  items,
  onClose,
  onToggleRead,
  onClear,
  onMarkAllRead,
  onClearAll,
  filter = 'all',
  onFilterChange,
  scoped = false,
}) => {
  const closable = onClose !== noopClose;
  const [hoverId, setHoverId] = useState<string | number | null>(null);

  const visible = filter === 'unread' ? items.filter((it) => !it.readAt) : items;
  const unreadCount = items.filter((it) => !it.readAt).length;

  return (
    <>
      {closable && (
        <div
          className="fixed inset-0 z-40"
          onClick={onClose}
          aria-hidden
        />
      )}
      <div className="absolute right-0 top-full mt-2 w-96 z-50 glass-panel-heavy rounded-2xl shadow-2xl shadow-black border border-slate-800 p-3 max-h-[70vh] flex flex-col animate-fade-in">
        <div className="flex items-center justify-between mb-2 px-1">
          <div className="flex items-center gap-2">
            <div className="text-[10px] font-mono uppercase tracking-wide text-slate-500">
              Notifications
            </div>
            <span className="text-[9px] font-mono px-1.5 py-0.5 rounded-full bg-slate-800 text-slate-400">
              {scoped ? 'Mine' : 'All'}
            </span>
            {unreadCount > 0 && (
              <span className="text-[9px] font-mono px-1.5 py-0.5 rounded-full bg-rose-500/20 text-rose-300 border border-rose-500/30">
                {unreadCount} new
              </span>
            )}
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close notifications"
            title="Close"
            className="w-5 h-5 inline-flex items-center justify-center rounded text-slate-500 hover:text-white hover:bg-slate-800 text-xs"
          >
            ✕
          </button>
        </div>

        {scoped && (
          <div className="flex items-center gap-1 mb-2 px-1">
            {(['all', 'unread'] as const).map((f) => (
              <button
                key={f}
                type="button"
                onClick={() => onFilterChange?.(f)}
                className={[
                  'px-2 py-1 rounded-md text-[10px] font-mono uppercase tracking-wide transition-colors',
                  filter === f
                    ? 'bg-indigo-500/20 text-indigo-200 border border-indigo-500/40'
                    : 'bg-slate-900/40 text-slate-400 border border-transparent hover:text-white hover:border-slate-700',
                ].join(' ')}
              >
                {f === 'all' ? 'All' : 'Unread'}
              </button>
            ))}
          </div>
        )}

        <div className="flex-1 min-h-0 overflow-y-auto pb-1">
          {visible.length === 0 ? (
            <div className="text-xs text-slate-500 font-sans py-6 text-center">
              {filter === 'unread' ? 'No unread notifications.' : 'No activity yet.'}
            </div>
          ) : (
            <ul className="space-y-1.5">
              {visible.map((it) => {
                const isUnread = !it.readAt;
                const idKey = String(it.id);
                return (
                  <li
                    key={idKey}
                    onMouseEnter={() => setHoverId(it.id)}
                    onMouseLeave={() => setHoverId((h) => (h === it.id ? null : h))}
                    className={[
                      'group relative p-2 rounded-xl border transition-colors',
                      it.severityClass || 'border-slate-800',
                      isUnread ? 'bg-slate-900/40' : 'bg-slate-950/40 opacity-70',
                      hoverId === it.id ? 'ring-1 ring-slate-700' : '',
                    ].join(' ')}
                  >
                    <div className="flex items-start gap-2">
                      <button
                        type="button"
                        onClick={(e) => {
                          e.stopPropagation();
                          if (scoped) onToggleRead?.(it.id, !!it.readAt);
                        }}
                        disabled={!scoped}
                        title={scoped ? (isUnread ? 'Mark as read' : 'Mark as unread') : ''}
                        aria-label={isUnread ? 'Mark as read' : 'Mark as unread'}
                        className={[
                          'mt-1 w-3 h-3 rounded-full border transition-colors shrink-0',
                          isUnread
                            ? 'bg-rose-500 border-rose-400 hover:bg-rose-400'
                            : 'bg-transparent border-slate-600 hover:border-slate-400',
                          scoped ? 'cursor-pointer' : 'cursor-default',
                        ].join(' ')}
                      />
                      <span className="text-base leading-none">{GLYPH_BY_TYPE[it.type] ?? '•'}</span>
                      <div className="flex-1 min-w-0">
                        <div className={[
                          'text-xs truncate',
                          isUnread ? 'font-bold text-slate-100' : 'font-medium text-slate-300',
                        ].join(' ')}>
                          {it.message}
                        </div>
                        <div className="text-[10px] font-mono text-slate-500 mt-0.5">
                          {relTime(it.createdAt)}
                          {it.readAt && <span className="ml-1.5 text-slate-600">· read</span>}
                        </div>
                      </div>
                      {scoped && (
                        <button
                          type="button"
                          onClick={(e) => {
                            e.stopPropagation();
                            onClear?.(it.id);
                          }}
                          title="Clear"
                          aria-label="Clear"
                          className={[
                            'w-5 h-5 inline-flex items-center justify-center rounded text-slate-500 hover:text-rose-300 hover:bg-rose-500/15 text-xs shrink-0',
                            hoverId === it.id ? 'opacity-100' : 'opacity-0',
                          ].join(' ')}
                        >
                          ✕
                        </button>
                      )}
                    </div>
                  </li>
                );
              })}
            </ul>
          )}
          <NotificationDigest items={visible} />
        </div>

        {scoped && items.length > 0 && (
          <div className="mt-2 pt-2 border-t border-slate-800/80 flex items-center justify-between gap-2 px-1">
            <button
              type="button"
              onClick={onMarkAllRead}
              disabled={unreadCount === 0}
              className={[
                'px-2.5 py-1.5 rounded-lg text-[10px] font-mono uppercase tracking-wide transition-colors',
                unreadCount === 0
                  ? 'bg-slate-900/40 text-slate-600 cursor-not-allowed'
                  : 'bg-slate-800 text-slate-200 hover:bg-slate-700 border border-slate-700',
              ].join(' ')}
            >
              Read all
            </button>
            <button
              type="button"
              onClick={onClearAll}
              className="px-2.5 py-1.5 rounded-lg text-[10px] font-mono uppercase tracking-wide bg-slate-900/40 text-slate-400 hover:text-rose-300 hover:bg-rose-500/15 border border-transparent hover:border-rose-500/30 transition-colors"
            >
              Clear all
            </button>
          </div>
        )}
      </div>
    </>
  );
};
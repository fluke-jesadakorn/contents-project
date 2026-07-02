'use client';

import React from 'react';
import Link from 'next/link';
import { Kpi } from './ui/Kpi';
import { HubAmbient } from './HubAmbient';
import { Tile } from './tiles/Tile';
import { TileTooltipProvider } from './TileTooltip';
import {
  GROUP_LABEL,
  type TileWithMeta,
} from './tile-config';
import {
  roleLabel,
  roleBadge,
  roleGlyph,
  staffLevelLabel,
  staffLevelGlyph,
} from './UserAvatar';
import {
  greetingLine,
  kpiSummary,
  metaLine,
  pickFeaturedTile,
  timeGreeting,
  type GreetingKey,
} from '@/lib/hero';

interface HubHeroProps {
  actor: {
    id?: number;
    fullname?: string | null;
    role_name?: string | null;
    department?: string | null;
    dept_group_name?: string | null;
    employee_code?: string | null;
    staff_level?: number | null;
  } | null;
  tiles: TileWithMeta[];
  isLocked: (t: TileWithMeta) => boolean;
  onOpenTile: (t: TileWithMeta) => void;
  onOpenCommand: () => void;
  onOpenPersona?: () => void;
  onOpenNotifications?: () => void;
  unreadCount?: number;
}

const QUICK_ACTIONS: Array<{
  key: 'search' | 'dashboard' | 'persona' | 'notifications';
  label: string;
  hint: string;
  icon: string;
  tone: string;
  href?: string;
  isButton: boolean;
}> = [
  { key: 'search',       label: 'Quick search',    hint: '⌘K',          icon: '🔍', tone: 'from-indigo-500/20 to-indigo-900/20 border-indigo-500/30', isButton: true },
  { key: 'dashboard',    label: 'Dashboard',       hint: 'overview',    icon: '📊', tone: 'from-cyan-500/20 to-cyan-900/20 border-cyan-500/30',     isButton: false, href: '/dashboard' },
  { key: 'persona',      label: 'Switch persona',  hint: 'dev tool',    icon: '👤', tone: 'from-purple-500/20 to-purple-900/20 border-purple-500/30', isButton: true },
  { key: 'notifications',label: 'Notifications',   hint: 'inbox',       icon: '🔔', tone: 'from-amber-500/20 to-amber-900/20 border-amber-500/30',   isButton: true },
];

export const HubHero: React.FC<HubHeroProps> = ({
  actor,
  tiles,
  isLocked,
  onOpenTile,
  onOpenCommand,
  onOpenPersona,
  onOpenNotifications,
  unreadCount,
}) => {
  const kpis = kpiSummary(tiles, isLocked);
  const featured = pickFeaturedTile(tiles, isLocked);

  const fullname = (actor?.fullname || '').trim() || 'there';
  const greetingKey: GreetingKey = timeGreeting();
  const greet = greetingLine(fullname, greetingKey);
  const role = actor?.role_name ?? undefined;
  const dept = actor?.dept_group_name || actor?.department || null;
  const level = actor?.staff_level ?? null;
  const levelLabel = level != null ? staffLevelLabel(level) : null;
  const levelGlyph = level != null ? staffLevelGlyph(level) : '·';

  const greetingEmoji =
    greetingKey === 'morning' ? '☀️'
    : greetingKey === 'afternoon' ? '🌤️'
    : '🌙';

  return (
    <TileTooltipProvider>
      <section
        aria-label="Hub hero"
        className="relative overflow-hidden rounded-3xl border border-slate-800/80 glass-panel-heavy shadow-2xl shadow-black/50 animate-fade-in"
      >
        <HubAmbient variant="hero" />

        <div className="relative z-10 p-5 sm:p-7 lg:p-9 space-y-6">
        <div className="flex items-center justify-between gap-3 flex-wrap">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="inline-flex items-center gap-1.5 rounded-full border border-indigo-500/30 bg-indigo-500/10 px-2.5 py-1 text-[10px] font-mono font-bold uppercase tracking-widest text-indigo-200">
              <span className="w-1.5 h-1.5 rounded-full bg-indigo-400 shadow-[0_0_8px_currentcolor] animate-pulse" />
              Live · World ERP
            </span>
            {role && (
              <span className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-[10px] font-mono font-bold uppercase tracking-widest ${roleBadge(role)}`}>
                <span aria-hidden>{roleGlyph(role)}</span>
                <span>{roleLabel(role)}</span>
              </span>
            )}
            {level != null && levelLabel && (
              <span className="inline-flex items-center gap-1 rounded-full border border-slate-700 bg-slate-900/60 px-2 py-0.5 text-[10px] font-mono font-bold uppercase tracking-widest text-slate-300">
                <span aria-hidden>{levelGlyph}</span>
                <span>L{level} · {levelLabel}</span>
              </span>
            )}
          </div>
          <div className="text-[10px] font-mono text-slate-500 hidden sm:flex items-center gap-1.5">
            <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 shadow-[0_0_8px_currentcolor]" />
            <span>RBAC-aware · {kpis.open} of {kpis.total} accessible</span>
          </div>
        </div>

        <div className="space-y-1.5">
          <h1 className="text-2xl sm:text-3xl lg:text-4xl font-black tracking-tight text-white leading-tight">
            <span aria-hidden className="mr-1.5">{greetingEmoji}</span>
            {greet}
            <span className="text-slate-500">.</span>
          </h1>
          {dept && (
            <p className="text-sm sm:text-base text-slate-400 leading-relaxed">
              Signed in to <span className="text-slate-200 font-bold">{dept}</span>
              {actor?.employee_code && (
                <>
                  <span className="text-slate-600 mx-1.5">·</span>
                  <span className="font-mono text-xs text-slate-500">{actor.employee_code}</span>
                </>
              )}
            </p>
          )}
        </div>

        <div className="grid grid-cols-2 sm:grid-cols-4 gap-2.5 sm:gap-3">
          <Kpi
            label="Accessible"
            value={kpis.open}
            accent="indigo"
            caption={`of ${kpis.total} tiles`}
          />
          <Kpi
            label="Locked"
            value={kpis.locked}
            accent="rose"
            caption="request access"
          />
          <Kpi
            label="Groups"
            value={kpis.groups}
            accent="cyan"
            caption="active in catalog"
          />
          <Kpi
            label="Spotlight"
            value={featured ? GROUP_LABEL[featured.group].label : '—'}
            accent="emerald"
            caption={featured ? 'first hub tile' : 'no open tile'}
            valueClassName="text-base"
          />
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-5 gap-3 sm:gap-4">
          <div className="lg:col-span-3">
            <Spotlight
              tile={featured}
              isLocked={isLocked}
              onOpen={onOpenTile}
            />
          </div>
          <div className="lg:col-span-2 grid grid-cols-2 lg:grid-cols-1 gap-2.5 sm:gap-3">
            {QUICK_ACTIONS.map((a) => {
              const accentText =
                a.key === 'search' ? 'text-indigo-300' :
                a.key === 'dashboard' ? 'text-cyan-300' :
                a.key === 'persona' ? 'text-purple-300' :
                'text-amber-300';
              const inner = (
                <div className={`relative h-full rounded-2xl border bg-gradient-to-br p-3.5 sm:p-4 transition-all hover:scale-[1.02] hover:-translate-y-0.5 hover:shadow-lg hover:shadow-black/40 ${a.tone}`}>
                  <div className="flex items-start justify-between gap-2">
                    <span className="text-2xl drop-shadow" aria-hidden>{a.icon}</span>
                    <span className={`text-[9px] font-mono font-bold uppercase tracking-widest ${accentText}`}>
                      {a.hint}
                    </span>
                  </div>
                  <div className="mt-3 sm:mt-4">
                    <div className="text-[13px] font-black text-white leading-tight">{a.label}</div>
                  </div>
                  {a.key === 'notifications' && typeof unreadCount === 'number' && unreadCount > 0 && (
                    <span className="absolute top-2 right-2 min-w-[18px] h-[18px] inline-flex items-center justify-center rounded-full bg-rose-500 text-white text-[9px] font-black font-mono px-1 shadow-md">
                      {unreadCount > 99 ? '99+' : unreadCount}
                    </span>
                  )}
                </div>
              );
              if (a.isButton) {
                const handler =
                  a.key === 'search' ? onOpenCommand :
                  a.key === 'persona'
                    ? (onOpenPersona ?? (() => window.dispatchEvent(new Event('world-erp:open-persona'))))
                    : (onOpenNotifications ?? (() => window.dispatchEvent(new Event('world-erp:open-notifications'))));
                return (
                  <button
                    key={a.key}
                    type="button"
                    onClick={handler}
                    aria-label={a.label}
                    className="text-left h-full"
                  >
                    {inner}
                  </button>
                );
              }
              return (
                <Link key={a.key} href={a.href!} aria-label={a.label} className="h-full">
                  {inner}
                </Link>
              );
            })}
          </div>
        </div>
      </div>
    </section>
    </TileTooltipProvider>
  );
};

interface SpotlightProps {
  tile: TileWithMeta | null;
  isLocked: (t: TileWithMeta) => boolean;
  onOpen: (t: TileWithMeta) => void;
}

const Spotlight: React.FC<SpotlightProps> = ({ tile, isLocked, onOpen }) => {
  if (!tile) {
    return (
      <div className="relative h-full min-h-[210px] rounded-2xl border border-dashed border-slate-700 bg-slate-950/30 p-5 flex flex-col items-center justify-center text-center">
        <div className="text-3xl mb-2 opacity-50" aria-hidden>🗂</div>
        <div className="text-sm font-bold text-slate-300">No spotlight tile</div>
        <div className="text-[11px] text-slate-500 font-mono mt-1 max-w-[28ch]">
          No open tile available for your role right now.
        </div>
      </div>
    );
  }
  const locked = isLocked(tile);
  const groupMeta = GROUP_LABEL[tile.group] ?? { label: 'Hub', icon: '🗂️' };
  const meta = metaLine(tile.access_meta ?? null);
  return (
    <button
      type="button"
      onClick={() => onOpen(tile)}
      aria-label={`Open ${tile.display_name}`}
      className="group relative w-full h-full text-left rounded-2xl overflow-hidden border border-slate-800/80 bg-slate-950/50 transition-all hover:border-slate-700 hover:shadow-2xl hover:shadow-black/60"
    >
      <Tile
        tile={tile}
        active
        href={locked ? undefined : tile.href}
        state={locked ? 'locked' : 'open'}
        onClick={() => onOpen(tile)}
      />
      <div className="absolute top-2 left-2 z-20 inline-flex items-center gap-1.5 rounded-full bg-slate-950/80 border border-indigo-500/40 px-2 py-0.5 text-[9px] font-mono font-bold uppercase tracking-widest text-indigo-200 shadow">
        <span aria-hidden>⭐</span>
        Spotlight · {groupMeta.icon} {groupMeta.label}
      </div>
      {meta && (
        <div className="absolute bottom-2 left-2 right-2 z-20 px-2 py-1 rounded-lg bg-slate-950/70 border border-slate-800/80 text-[10px] font-mono text-slate-300 truncate">
          {meta}
        </div>
      )}
    </button>
  );
};

export default HubHero;

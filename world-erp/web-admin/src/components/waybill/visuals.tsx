import type { PipState } from '@erp-lib/waybill/derive';

export type { PipState } from '@erp-lib/waybill/derive';

export const PIP_BADGE_EN: Record<PipState, string> = {
  passed: 'Done',
  active: 'Active',
  pending: 'Pending',
  rejected: 'Rejected',
  skipped: 'Optional',
};

export const PIP_BADGE_TH: Record<PipState, string> = {
  passed: 'ผ่าน',
  active: 'กำลังดำเนินการ',
  pending: 'รอ',
  rejected: 'ปฏิเสธ',
  skipped: 'ไม่บังคับ',
};

export const PIP_BADGE_DE: Record<PipState, string> = {
  passed: 'Erledigt',
  active: 'Aktiv',
  pending: 'Ausstehend',
  rejected: 'Abgelehnt',
  skipped: 'Optional',
};

export const BULLET_GLYPH: Record<PipState, string> = {
  passed: '✓',
  active: '◉',
  pending: '○',
  rejected: '✗',
  skipped: '—',
};

export interface PipTone {
  card: string;
  bullet: string;
  badge: string;
  title: string;
  sectionHead: string;
}

export function toneForState(state: PipState): PipTone {
  switch (state) {
    case 'passed':
      return {
        card: 'border-emerald-500/50 bg-emerald-950/30 text-emerald-100',
        bullet: 'bg-emerald-400 shadow-[0_0_12px_rgba(52,211,153,0.7)] text-emerald-200',
        badge: 'bg-emerald-500/20 text-emerald-200 border border-emerald-400/40',
        title: 'text-emerald-200',
        sectionHead: 'text-emerald-300/80',
      };
    case 'active':
      return {
        card: 'border-cyan-400/80 bg-cyan-950/40 text-white ring-2 ring-cyan-400/70',
        bullet: 'bg-cyan-300 shadow-[0_0_14px_rgba(34,211,238,0.9)] animate-pulse text-cyan-100',
        badge: 'bg-cyan-400 text-slate-950 border border-cyan-300',
        title: 'text-cyan-200',
        sectionHead: 'text-cyan-300/80',
      };
    case 'skipped':
      return {
        card: 'glass-panel text-slate-700 opacity-60',
        bullet: 'bg-slate-800 text-slate-600',
        badge: 'bg-slate-800 text-slate-600 border border-slate-700',
        title: 'text-slate-700',
        sectionHead: 'text-slate-700',
      };
    case 'rejected':
      return {
        card: 'border-rose-500/70 bg-rose-950/40 text-rose-100 ring-2 ring-rose-500/50',
        bullet: 'bg-rose-400 text-rose-100 shadow-[0_0_10px_rgba(244,63,94,0.7)]',
        badge: 'bg-rose-500/25 text-rose-200 border border-rose-400/50',
        title: 'text-rose-200',
        sectionHead: 'text-rose-300/80',
      };
    case 'pending':
    default:
      return {
        card: 'glass-panel text-slate-400',
        bullet: 'bg-slate-700 text-slate-500',
        badge: 'bg-slate-800 text-slate-500 border border-slate-700',
        title: 'text-slate-400',
        sectionHead: 'text-slate-500',
      };
  }
}
export type ChromeTone =
  | 'accent'
  | 'caution'
  | 'info'
  | 'positive'
  | 'critical'
  | 'indigo'
  | 'purple'
  | 'neutral';

export const TONE_VAR: Record<ChromeTone, string> = {
  accent: '--accent',
  caution: '--caution',
  info: '--info',
  positive: '--positive',
  critical: '--critical',
  indigo: '--color-indigo-400',
  purple: '--color-purple-400',
  neutral: '--neutral',
};

export const TONE_SOFT: Record<ChromeTone, string> = {
  accent: '--accent-soft',
  caution: '--caution-soft',
  info: '--info-soft',
  positive: '--positive-soft',
  critical: '--critical-soft',
  indigo: '--color-indigo-950',
  purple: '--color-purple-950',
  neutral: '--neutral-soft',
};

export const TONE_TINT: Record<ChromeTone, string> = {
  accent: 'glass-tint-accent',
  caution: 'glass-tint-caution',
  info: 'glass-tint-info',
  positive: 'glass-tint-positive',
  critical: 'glass-tint-critical',
  indigo: 'glass-tint-indigo',
  purple: 'glass-tint-purple',
  neutral: 'glass-tint-neutral',
};

export const TONE_TEXT: Record<ChromeTone, string> = {
  accent: 'text-accent',
  caution: 'text-caution',
  info: 'text-info',
  positive: 'text-positive',
  critical: 'text-critical',
  indigo: 'text-indigo-300',
  purple: 'text-purple-300',
  neutral: 'text-neutral',
};

export const TONE_BORDER: Record<ChromeTone, string> = {
  accent: 'border-accent',
  caution: 'border-caution',
  info: 'border-info',
  positive: 'border-positive',
  critical: 'border-critical',
  indigo: 'border-indigo-400/40',
  purple: 'border-purple-400/40',
  neutral: 'border-rule',
};

export const TONE_SECTION: Record<ChromeTone, { dot: string; text: string; glow: string }> = {
  accent:    { dot: 'bg-accent',          glow: 'shadow-[0_0_8px_var(--accent)]',          text: 'text-accent' },
  caution:   { dot: 'bg-caution',         glow: 'shadow-[0_0_8px_var(--caution)]',         text: 'text-caution' },
  info:      { dot: 'bg-info',            glow: 'shadow-[0_0_8px_var(--info)]',            text: 'text-info' },
  positive:  { dot: 'bg-positive',        glow: 'shadow-[0_0_8px_var(--positive)]',        text: 'text-positive' },
  critical:  { dot: 'bg-critical',        glow: 'shadow-[0_0_8px_var(--critical)]',        text: 'text-critical' },
  indigo:    { dot: 'bg-indigo-400',      glow: 'shadow-[0_0_8px_var(--color-indigo-400)]',text: 'text-indigo-300' },
  purple:    { dot: 'bg-purple-400',      glow: 'shadow-[0_0_8px_var(--color-purple-400)]',text: 'text-purple-300' },
  neutral:   { dot: 'bg-mute',            glow: '',                                          text: 'text-mute' },
};

export function toneForPathname(pathname: string | null | undefined): ChromeTone {
  const p = pathname || '/';
  if (p === '/' || p.startsWith('/hub')) return 'accent';
  if (p.startsWith('/inbox') || p.startsWith('/subordinate-prs') || p.startsWith('/approve')) return 'caution';
  if (
    p.startsWith('/expense') ||
    p === '/pr' || p.startsWith('/pr/') ||
    p === '/po' || p.startsWith('/po/') ||
    p.startsWith('/cockpit') ||
    p.startsWith('/waybill') ||
    p.startsWith('/my-waybills')
  ) return 'info';
  if (p.startsWith('/policy') || p.startsWith('/roles') || p.startsWith('/tiles') || p.startsWith('/audit')) return 'indigo';
  if (p.startsWith('/customers') || p.startsWith('/sales')) return 'purple';
  return 'accent';
}
import type { TileWithMeta, TileGroup, TileAccessMeta } from '@/components/tile-config';

export type GreetingKey = 'morning' | 'afternoon' | 'evening';

export function timeGreeting(now: Date = new Date()): GreetingKey {
  const hour = Number(
    new Intl.DateTimeFormat('en-GB', {
      hour: '2-digit',
      hour12: false,
      timeZone: 'Asia/Bangkok',
    }).format(now),
  );
  if (hour >= 5 && hour < 12) return 'morning';
  if (hour >= 12 && hour < 18) return 'afternoon';
  return 'evening';
}

export function greetingLine(name: string, key: GreetingKey = timeGreeting()): string {
  const safe = (name || '').trim() || 'there';
  return key === 'morning'
    ? `Good morning, ${safe}`
    : key === 'afternoon'
      ? `Good afternoon, ${safe}`
      : `Good evening, ${safe}`;
}

export function pickFeaturedTile(
  tiles: TileWithMeta[],
  isLocked: (t: TileWithMeta) => boolean,
): TileWithMeta | null {
  if (!tiles || tiles.length === 0) return null;
  const hubOpen = tiles.find((t) => t.group === 'hub' && !isLocked(t));
  if (hubOpen) return hubOpen;
  const anyOpen = tiles.find((t) => !isLocked(t));
  return anyOpen ?? null;
}

export interface HeroKpis {
  open: number;
  locked: number;
  groups: number;
  total: number;
  groupLabels: string[];
}

export function kpiSummary(
  tiles: TileWithMeta[],
  isLocked: (t: TileWithMeta) => boolean,
): HeroKpis {
  const total = tiles.length;
  let locked = 0;
  const groupSet = new Set<TileGroup>();
  for (const t of tiles) {
    if (isLocked(t)) locked += 1;
    if (t.group) groupSet.add(t.group);
  }
  return {
    total,
    locked,
    open: Math.max(0, total - locked),
    groups: groupSet.size,
    groupLabels: Array.from(groupSet),
  };
}

export function metaLine(meta: TileAccessMeta | null | undefined): string {
  if (!meta) return '';
  const parts: string[] = [];
  if (meta.dept_name) parts.push(meta.dept_name);
  if (meta.group_name) parts.push(meta.group_name);
  return parts.join(' · ');
}

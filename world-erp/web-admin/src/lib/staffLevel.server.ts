import { query } from '@/lib/db';
import { type StaffLevel, isStaffLevel } from '@/lib/permissions';

let cache: Map<string, StaffLevel> | null = null;
let cacheTs = 0;
const TTL_MS = 60_000;

export async function getDefaultStaffLevelFromDB(role: string | undefined): Promise<StaffLevel> {
  if (!role) return 5;
  const now = Date.now();
  if (!cache || now - cacheTs > TTL_MS) {
    try {
      const r = await query(
        `SELECT name, default_staff_level FROM roles WHERE default_staff_level IS NOT NULL`
      );
      const out = new Map<string, StaffLevel>();
      for (const row of r.rows) {
        if (isStaffLevel(row.default_staff_level)) {
          out.set(row.name, row.default_staff_level);
        }
      }
      cache = out;
      cacheTs = now;
    } catch {
      cache = new Map();
      cacheTs = now;
    }
  }
  const fromDb = cache.get(role);
  if (fromDb) return fromDb;
  const { getDefaultStaffLevel } = await import('@/lib/permissions');
  return getDefaultStaffLevel(role as any);
}

export async function getRoleDefaultStaffLevelMap(): Promise<Map<string, StaffLevel>> {
  if (!cache) await getDefaultStaffLevelFromDB('__warm__');
  return cache || new Map();
}
// lib/staffLevel.server.ts — TTL-cached role-name → level lookup.
//
// Reads the level from the role-id suffix directly (no SQL views).

import { query } from '@/lib/db';
import { parseRoleId } from '@erp-lib/perm/server';

let cache: Map<string, number> | null = null;
let cacheTs = 0;
const TTL_MS = 60_000;

export async function getDefaultStaffLevelFromDB(role: string | undefined): Promise<number> {
  if (!role) return 5;
  const now = Date.now();
  if (!cache || now - cacheTs > TTL_MS) {
    try {
      const r = await query<{ id: string }>(
        `SELECT id FROM perm.roles`,
      );
      const out = new Map<string, number>();
      for (const row of r.rows) {
        const parsed = parseRoleId(row.id);
        if (parsed) out.set(parsed.name, parsed.level);
      }
      cache = out;
      cacheTs = now;
    } catch {
      cache = new Map();
      cacheTs = now;
    }
  }
  return cache.get(role) ?? 5;
}

export async function getRoleDefaultStaffLevelMap(): Promise<Map<string, number>> {
  if (!cache) await getDefaultStaffLevelFromDB('__warm__');
  return cache || new Map();
}

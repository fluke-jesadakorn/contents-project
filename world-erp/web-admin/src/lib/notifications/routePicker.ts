import 'server-only';

type TargetKind = 'expense' | 'pr' | 'po';

interface Candidate {
  moduleId: string;
  href: string;
  targetKind: TargetKind | null;
}

const CANDIDATES: Record<string, Candidate[]> = {
  'expense.submitted': [
    { moduleId: 'tile-expense',    href: '/my-waybills?scope=mine', targetKind: 'expense' },
    { moduleId: 'tile-my-waybills', href: '/my-waybills?scope=all',  targetKind: 'expense' },
  ],
  'expense.advanced': [
    { moduleId: 'tile-my-waybills', href: '/my-waybills?scope=all',  targetKind: 'expense' },
    { moduleId: 'tile-expense',     href: '/my-waybills?scope=queue', targetKind: 'expense' },
  ],
  'expense.rejected': [
    { moduleId: 'tile-expense',     href: '/my-waybills?scope=mine', targetKind: 'expense' },
    { moduleId: 'tile-my-waybills', href: '/my-waybills?scope=all',  targetKind: 'expense' },
  ],
  'expense.paid': [
    { moduleId: 'tile-my-waybills', href: '/my-waybills?scope=all', targetKind: 'expense' },
    { moduleId: 'tile-cockpit',     href: '/cockpit',              targetKind: null },
  ],
  'pr.submitted': [
    { moduleId: 'tile-pr',          href: '/my-waybills?scope=mine', targetKind: 'pr' },
    { moduleId: 'tile-my-waybills', href: '/my-waybills?scope=all',  targetKind: 'pr' },
  ],
  'pr.advanced': [
    { moduleId: 'tile-pr',          href: '/my-waybills?scope=queue', targetKind: 'pr' },
    { moduleId: 'tile-my-waybills', href: '/my-waybills?scope=all',   targetKind: 'pr' },
  ],
  'pr.rejected': [
    { moduleId: 'tile-pr',          href: '/my-waybills?scope=mine', targetKind: 'pr' },
    { moduleId: 'tile-my-waybills', href: '/my-waybills?scope=all',  targetKind: 'pr' },
  ],
  'po.created': [
    { moduleId: 'tile-po',          href: '/my-waybills?scope=all', targetKind: 'po' },
    { moduleId: 'tile-my-waybills', href: '/my-waybills?scope=all', targetKind: 'po' },
  ],
  'po.advanced': [
    { moduleId: 'tile-po',          href: '/my-waybills?scope=all', targetKind: 'po' },
    { moduleId: 'tile-my-waybills', href: '/my-waybills?scope=all', targetKind: 'po' },
  ],
  'po.settled': [
    { moduleId: 'tile-po',          href: '/my-waybills?scope=all', targetKind: 'po' },
    { moduleId: 'tile-my-waybills', href: '/my-waybills?scope=all', targetKind: 'po' },
  ],
  'policy.updated': [
    { moduleId: 'tile-policy', href: '/policy', targetKind: null },
  ],
};

const CEO_CANDIDATE: Candidate = {
  moduleId: 'tile-override-queue',
  href: '/override-queue',
  targetKind: null,
};

const FALLBACK: Candidate = {
  moduleId: 'tile-my-waybills',
  href: '/my-waybills?scope=all',
  targetKind: null,
};

const DASHBOARD_FALLBACK = { href: '/', focus: null as string | null };

export interface NotificationInput {
  type: string;
  refType: string | null;
  refId: number | null;
}

export interface ResolvedNav {
  href: string;
  focus: string | null;
}

export interface ActorLite {
  id: number;
  permissions: string[];
}

export async function resolveNotificationHrefs(
  items: NotificationInput[],
  actor: ActorLite | null,
): Promise<(ResolvedNav | null)[]> {
  if (!actor || actor.permissions.length === 0) {
    return items.map(() => null);
  }

  const candidates = items.map(listFor);
  const moduleIds = new Set<string>();
  for (const list of candidates) {
    for (const c of list) moduleIds.add(c.moduleId);
  }
  moduleIds.add(FALLBACK.moduleId);

  const permSet = new Set(actor.permissions);
  const allowedSet = new Set<string>();
  for (const m of moduleIds) {
    const perm = `tile:${m.replace(/^tile-/, '').replace(/-/g, '_')}:view`;
    if (permSet.has(perm)) allowedSet.add(m);
  }

  return items.map((it, idx) => pick(it, candidates[idx]!, allowedSet));
}

function listFor(it: NotificationInput): Candidate[] {
  if (it.type === 'ceo.override') {
    return [{
      moduleId: CEO_CANDIDATE.moduleId,
      href: CEO_CANDIDATE.href,
      targetKind:
        it.refType === 'pr' ? 'pr' :
        it.refType === 'expense' ? 'expense' : null,
    }];
  }
  return CANDIDATES[it.type] ?? [];
}

function pick(
  it: NotificationInput,
  list: Candidate[],
  allow: Set<string>,
): ResolvedNav | null {
  for (const c of list) {
    if (!allow.has(c.moduleId)) continue;
    const focus =
      c.targetKind && it.refType && it.refId != null && kindMatch(c.targetKind, it.refType)
        ? `${c.targetKind}:${it.refId}`
        : null;
    return { href: c.href, focus };
  }
  if (allow.has(FALLBACK.moduleId)) {
    return { href: FALLBACK.href, focus: null };
  }
  return DASHBOARD_FALLBACK;
}

function kindMatch(candidate: TargetKind, refType: string): boolean {
  if (candidate === 'expense') return refType === 'expense';
  if (candidate === 'pr') return refType === 'pr';
  if (candidate === 'po') return refType === 'po';
  return false;
}
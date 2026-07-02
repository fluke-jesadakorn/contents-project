import { query } from '@/lib/db';

export interface RecipientContext {
  type: string;
  refType: string | null;
  refId: number | null;
  actorId: number | null;
  payload?: Record<string, any>;
}

const NO_FANOUT_TYPES = new Set(['policy.updated']);

const DOMAIN_BY_REF: Record<string, string> = {
  expense: 'expenses',
  pr: 'pr',
  po: 'po',
  slip: 'slips',
  user: 'users',
  department: 'departments',
  audit: 'audit',
  ai: 'ai_settings',
  notification: 'notifications',
};

function mapEventToDomain(type: string, refType: string | null): string | null {
  if (refType && DOMAIN_BY_REF[refType]) return DOMAIN_BY_REF[refType];
  if (type.startsWith('expense.')) return 'expenses';
  if (type.startsWith('pr.')) return 'pr';
  if (type.startsWith('po.')) return 'po';
  if (type.startsWith('slip.')) return 'slips';
  if (type.startsWith('user.')) return 'users';
  if (type.startsWith('audit.')) return 'audit';
  if (type.startsWith('ai.')) return 'ai_settings';
  if (type.startsWith('notification.') || type.startsWith('notif.')) return 'notifications';
  return null;
}

export async function computeRecipients(ctx: RecipientContext): Promise<number[]> {
  if (NO_FANOUT_TYPES.has(ctx.type)) return [];
  const ids = new Set<number>();
  const ownerId = await lookupRefOwner(ctx.refType, ctx.refId);
  const submitterId = ownerId ?? ctx.actorId ?? null;
  const causeId = ctx.actorId ?? null;

  if (ctx.type.startsWith('ceo.override')) {
    if (ownerId) ids.add(ownerId);
  } else if (ctx.type.startsWith('expense.')) {
    if (submitterId) ids.add(submitterId);
    if (causeId && causeId !== submitterId) ids.add(causeId);
  } else if (ctx.type.startsWith('pr.') || ctx.type.startsWith('po.')) {
    if (submitterId) ids.add(submitterId);
    if (causeId && causeId !== submitterId) ids.add(causeId);
  } else {
    if (causeId) ids.add(causeId);
  }

  if (submitterId) {
    const sup = await lookupSupervisor(submitterId);
    if (sup && sup !== submitterId) ids.add(sup);
  }

  const domainId = mapEventToDomain(ctx.type, ctx.refType);
  if (domainId) {
    const broadcast = await expandByDomainScope(domainId, ctx.refType, ctx.refId);
    for (const uid of broadcast) ids.add(uid);
  }

  return [...ids];
}

async function expandByDomainScope(
  domainId: string,
  refType: string | null,
  refId: number | null,
): Promise<number[]> {
  const roles = await query<{ rbac_role_id: string; scope_kind: string; team_ids: string[] | null }>(
    `SELECT u.rbac_role_id,
            COALESCE(ds.scope_kind, r.scope_kind) AS scope_kind,
            (SELECT array_agg(rg.group_id)
               FROM rbac.role_groups rg
               JOIN rbac.groups g ON g.id = rg.group_id
              WHERE rg.role_id = u.rbac_role_id AND g.kind = 'team'
            ) AS team_ids
       FROM users u
       JOIN rbac.roles r ON r.id = u.rbac_role_id
       LEFT JOIN rbac.domain_scope ds
         ON ds.role_id = u.rbac_role_id AND ds.domain_id = $1
      WHERE u.rbac_role_id IS NOT NULL
        AND u.is_active IS NOT FALSE
        AND COALESCE(ds.scope_kind, r.scope_kind) <> 'deny'`,
    [domainId],
  );

  if (roles.rows.length === 0) return [];

  let anchorDept: string | null = null;
  let anchorSubmitter: number | null = null;
  if (refType === 'expense' && refId) {
    const r = await query<{ submitter_id: number | null }>(
      `SELECT submitter_id FROM expenses WHERE id = $1`,
      [refId],
    );
    anchorSubmitter = r.rows[0]?.submitter_id ?? null;
    if (anchorSubmitter) {
      const u = await query<{ dept_group_id: string | null; department: string | null }>(
        `SELECT dept_group_id, department FROM users WHERE id = $1`,
        [anchorSubmitter],
      );
      anchorDept = u.rows[0]?.dept_group_id ?? u.rows[0]?.department ?? null;
    }
  }

  const out = new Set<number>();
  for (const row of roles.rows) {
    const scope = row.scope_kind;
    if (scope === 'deny' || scope === 'self') continue;
    if (scope === 'all') {
      const r = await query<{ id: number }>(
        `SELECT id FROM users WHERE rbac_role_id = $1 AND is_active IS NOT FALSE`,
        [row.rbac_role_id],
      );
      for (const u of r.rows) out.add(u.id);
      continue;
    }
    if (scope === 'department' && anchorDept) {
      const r = await query<{ id: number }>(
        `SELECT id FROM users
          WHERE rbac_role_id = $1
            AND (dept_group_id = $2 OR department = $3)
            AND is_active IS NOT FALSE`,
        [row.rbac_role_id, anchorDept, anchorDept],
      );
      for (const u of r.rows) out.add(u.id);
      continue;
    }
    if (scope === 'team' && row.team_ids && row.team_ids.length > 0) {
      const r = await query<{ id: number }>(
        `SELECT u.id FROM users u
          JOIN rbac.role_groups rg ON rg.role_id = u.rbac_role_id
         WHERE u.rbac_role_id = $1
           AND rg.group_id = ANY($2::text[])
           AND u.is_active IS NOT FALSE`,
        [row.rbac_role_id, row.team_ids],
      );
      for (const u of r.rows) out.add(u.id);
      continue;
    }
    if (scope === 'subtree' && anchorSubmitter) {
      const r = await query<{ id: number }>(
        `WITH RECURSIVE down AS (
           SELECT id FROM users WHERE id = $2
           UNION
           SELECT u.id FROM users u JOIN down d ON u.reports_to_user_id = d.id
         )
         SELECT id FROM down WHERE id <> $2 AND id IN (
           SELECT id FROM users WHERE rbac_role_id = $1 AND is_active IS NOT FALSE
         )`,
        [row.rbac_role_id, anchorSubmitter],
      );
      for (const u of r.rows) out.add(u.id);
    }
  }
  return [...out];
}

async function lookupRefOwner(refType: string | null, refId: number | null): Promise<number | null> {
  if (!refType || !refId) return null;
  if (refType === 'expense') {
    const r = await query<{ submitter_id: number | null }>(
      `SELECT submitter_id FROM expenses WHERE id = $1`,
      [refId]
    );
    return r.rows[0]?.submitter_id ?? null;
  }
  if (refType === 'pr') {
    const r = await query<{ requester_id: number | null }>(
      `SELECT requester_id FROM purchase_requisitions WHERE id = $1`,
      [refId]
    );
    return r.rows[0]?.requester_id ?? null;
  }
  if (refType === 'po') {
    const r = await query<{ requester_id: number | null }>(
      `SELECT pr.requester_id FROM purchase_orders po JOIN purchase_requisitions pr ON pr.id = po.pr_id WHERE po.id = $1`,
      [refId]
    );
    return r.rows[0]?.requester_id ?? null;
  }
  return null;
}

async function lookupSupervisor(userId: number): Promise<number | null> {
  const r = await query<{ reports_to_user_id: number | null }>(
    `SELECT reports_to_user_id FROM users WHERE id = $1`,
    [userId]
  );
  return r.rows[0]?.reports_to_user_id ?? null;
}

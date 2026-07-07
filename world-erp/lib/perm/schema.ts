// perm row shapes — match perm.* tables exactly.

export interface Role {
  id: string;
  display_name: string;
  description: string | null;
  is_system: boolean;
  sort_order: number;
}

export interface Permission {
  id: string;
  domain: string;
  subject: string;
  verb: string;
  description: string | null;
}

export type Effect = 'allow' | 'deny';

export interface RolePermission {
  role_id: string;
  permission_id: string;
  effect: Effect;
}

export interface UserRole {
  user_id: number;
  role_id: string;
}

export interface AclRule {
  id: number;
  permission_id: string;
  subject_type: string;
  owner_field: string;
  can_assign_to_self: boolean;
  can_assign_to_group: boolean;
}

export interface AuditEntry {
  id: number;
  kind: string;
  actor: string;
  target: unknown;
  occurred_at: string;
}

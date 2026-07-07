// Public session shape — matches the user's sketch exactly:
//   { user: { id, name, role, deptGroupId?, staffLevel? }, permissions: [...] }

export interface PermSession {
  user: {
    id: number;
    name: string;
    role: string;
    deptGroupId?: string | null;
    staffLevel?: number | null;
  };
  permissions: string[];
}

export type { PermSession as PermSessionEnvelope };

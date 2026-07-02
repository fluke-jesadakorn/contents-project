import 'server-only';
import { getDashboardData, getDashboardForRole } from '@/lib/server/queries';
import { DashboardShell } from '../dashboard/DashboardShell';

interface Props {
  actor: {
    id: number;
    role_name: string;
    fullname: string;
    dept_group_name?: string | null;
    department?: string | null;
    [k: string]: unknown;
  };
}

function kindLabel(kind: string | null | undefined): string {
  switch (kind) {
    case 'it':       return 'IT Console';
    case 'exec':     return 'Executive Summary';
    case 'hod':      return 'Department Pipeline';
    case 'am':       return 'Accounting Manager';
    case 'reviewer': return 'Reviewer Queue';
    case 'hr':       return 'HR Workspace';
    case 'finance':  return 'Finance Disbursement';
    case 'staff':    return 'My Submissions';
    default:         return 'Organization Dashboard';
  }
}

function taglineFor(kind: string | null | undefined, user: any): string {
  if (!user) return 'Your role-tailored overview';
  const role = (user.role_name || 'user').replace(/_/g, ' ');
  const deptName = user.dept_group_name ?? user.department;
  const dept = deptName ? ` · ${deptName}` : '';
  return `Hello ${user.fullname} (${role}${dept}) — this dashboard only shows data you have permission to access`;
}

export async function DashboardContent({ actor }: Props) {
  const data = await getDashboardData();
  const summary = actor ? await getDashboardForRole(actor.id).catch(() => null) : null;

  const users = (data.users || []) as any[];
  const summaryPayload = summary && (summary as any).success ? (summary as any) : null;
  const kind: string | null = summaryPayload?.kind || null;

  return (
    <DashboardShell
      users={users}
      currentUser={actor as any}
      summary={summaryPayload as any}
      kindLabel={kindLabel(kind)}
      tagline={taglineFor(kind, actor)}
      breadcrumbCurrentRole={actor?.role_name?.replace(/_/g, ' ')}
      breadcrumbFullname={actor?.fullname}
    />
  );
}

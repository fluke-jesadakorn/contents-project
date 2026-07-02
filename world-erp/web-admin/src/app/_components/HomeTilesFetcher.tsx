import 'server-only';
import {
  getDashboardData,
  getExecutiveReport,
  listApprovalPolicies,
  listPurchaseRequisitions,
} from '@/lib/server/queries';
import { HomeClient } from '@/app/HomeClient';

interface Props {
  actor: {
    id: number;
    role_name: string;
    rbac_role_id?: string | null;
    fullname?: string;
    [k: string]: unknown;
  };
  canViewHub: boolean;
  canViewPolicy: boolean;
  canViewExec: boolean;
}

export async function HomeTilesFetcher({ actor, canViewHub, canViewPolicy, canViewExec }: Props) {
  const [{ users = [], expenses = [] }, policiesRes, prsRes, execRes] = await Promise.all([
    getDashboardData(),
    canViewPolicy ? listApprovalPolicies(actor.id) : Promise.resolve({ success: false as const, policies: [] }),
    listPurchaseRequisitions(actor.id),
    canViewExec ? getExecutiveReport(actor.id) : Promise.resolve({ success: false as const, report: null }),
  ]);

  return (
    <HomeClient
      users={users as any[]}
      currentUser={actor as any}
      expenses={expenses as any[]}
      policies={(policiesRes.success ? policiesRes.policies : []) as any[]}
      prs={(prsRes.success ? prsRes.prs : []) as any[]}
      execReport={execRes.success ? execRes.report : null}
      canViewHub={canViewHub}
    />
  );
}

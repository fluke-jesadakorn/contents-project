import 'server-only';
import {
  getDashboardData,
  getExecutiveReport,
  listPurchaseRequisitions,
} from '@/lib/server/queries';
import { HomeClient } from '@/app/HomeClient';
import {
  loadActorAsSession,
  loadTileAccessBundle,
} from '@/components/tileAccess.server';
import { timeGreeting } from '@/lib/hero';

interface Props {
  actor: {
    id: number;
    role_name: string;
    rbac_role_id?: string | null;
    fullname?: string;
    [k: string]: unknown;
  };
  canViewExec: boolean;
}

export async function HomeTilesFetcher({ actor, canViewExec }: Props) {
  const [{ users = [], expenses = [] }, prsRes, execRes] = await Promise.all([
    getDashboardData(),
    listPurchaseRequisitions(actor.id),
    canViewExec ? getExecutiveReport(actor.id) : Promise.resolve({ success: false as const, report: null }),
  ]);

  const permSession = await loadActorAsSession();
  const [bundle, greetingKey] = await Promise.all([
    loadTileAccessBundle(permSession),
    Promise.resolve(timeGreeting()),
  ]);

  return (
    <HomeClient
      users={users as any[]}
      currentUser={actor as any}
      expenses={expenses as any[]}
      prs={(prsRes.success ? prsRes.prs : []) as any[]}
      execReport={execRes.success ? execRes.report : null}
      tiles={bundle.tiles}
      accessByTile={bundle.accessByTile}
      greetingKey={greetingKey}
    />
  );
}

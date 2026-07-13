import { redirect } from 'next/navigation';
import { cookies } from 'next/headers';
import { verifySession } from '@erp-lib/server/sessionToken';
import { buildPolicyContext } from '@erp-lib/policy/context';
import { evalPolicy, POL } from '@erp-lib/policy';
import { loadActor } from '@/lib/server/guard';
import { ActorProvider, type ActorSnapshot } from '@/components/ActorProvider';
import { OnboardingOverlay } from '@/components/onboarding/OnboardingOverlay';

export const dynamic = 'force-dynamic';

export default async function ProtectedLayout({ children }: { children: React.ReactNode }) {
  const tok = (await cookies()).get('erp_session')?.value ?? null;
  const payload = await verifySession(tok);
  const ctx = await buildPolicyContext(payload);
  if (!ctx) {
    redirect('/login');
  }

  const canSeeGlLines = (await evalPolicy(POL.canSeeGlLines, ctx)).allow;
  const canPostAccrual = (await evalPolicy(POL.canPostGlAccrual, ctx)).allow;
  const canPostSettlement = (await evalPolicy(POL.canPostGlSettlement, ctx)).allow;
  const canConfirmGl = (await evalPolicy(POL.canConfirmGl, ctx)).allow;
  const canSettleExpense = (await evalPolicy(POL.canSettleExpense, ctx)).allow;
  const canFinalApprove = (await evalPolicy(POL.canFinalApproveExpense, ctx)).allow;
  const canAttach = (await evalPolicy(POL.canAttachAtStage, ctx)).allow;
  const canRemoveAttachment = (await evalPolicy(POL.canRemoveAttachment, ctx)).allow;
  const canRecall = (await evalPolicy(POL.recallWaybill, ctx)).allow;

  const profile = await loadActor();
  const snapshot: ActorSnapshot = {
    id: ctx.actor.id,
    fullname: profile?.fullname ?? '',
    employee_code: profile?.employee_code ?? '',
    role_name: profile?.role_name ?? ctx.actor.roleName ?? '',
    policies: {
      canSeeGlLines,
      canPostAccrual,
      canPostSettlement,
      canConfirmGl,
      canSettleExpense,
      canFinalApprove,
      canAttach,
      canRemoveAttachment,
      canRecall,
      canAct: false,
    },
  };

  return (
    <ActorProvider value={snapshot}>
      <OnboardingOverlay />
      {children}
    </ActorProvider>
  );
}

export const MIN_REJECT_REASON = 5;

export function ensureRejectReason(actionComment: string): string | null {
  const t = (actionComment || '').trim();
  if (t.length < MIN_REJECT_REASON) {
    return `Please provide a rejection reason of at least ${MIN_REJECT_REASON} characters`;
  }
  return null;
}

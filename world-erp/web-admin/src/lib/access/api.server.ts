// Direct calls into @erp-lib (no HTTP). Replaces the previous HTTP proxy
// to rbac-svc.

import 'server-only';
export * from '@erp-lib/access/api.server';
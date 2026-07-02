// Direct call into @erp-lib/ai/router. Replaces the previous HTTP proxy to ai-svc.

import 'server-only';

export type {
  InvokeInput,
  InvokeResult,
} from '@erp-lib/ai/router';

export { invoke, aiInvoke } from '@erp-lib/ai/router';
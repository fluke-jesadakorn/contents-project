// Re-export from the consolidated @erp-lib/server/sessionToken so existing
// web-admin imports of `@/lib/server/sessionToken` keep working.

export {
  SESSION_COOKIE,
  SESSION_TTL_SECONDS,
  ENC,
  DEC,
  signSession,
  verifySession,
  safeEqual,
  sessionFromHeaders,
  mintSessionId,
  type SessionPayload,
} from '@erp-lib/server/sessionToken';
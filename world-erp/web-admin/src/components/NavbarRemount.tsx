'use client';

import React from 'react';
import { usePathname } from 'next/navigation';

/**
 * Tiny client wrapper that forces its children to remount whenever the
 * pathname changes. Lets the surrounding AppShell stay a Server Component
 * (so NotificationBell/Navbar/etc. can fetch data on the server) while
 * still getting the route-change remount that fixes stale event handlers
 * after client-side navigation.
 *
 * Why this exists: putting 'use client' on AppShell pulls the entire Navbar
 * subtree into the client bundle, which transitively pulls in `pg` (via
 * server-only guards in queries.ts) and breaks the build.
 */
export const NavbarRemount: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const pathname = usePathname();
  return <React.Fragment key={pathname}>{children}</React.Fragment>;
};
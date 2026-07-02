import React, { Suspense } from 'react';
import { Navbar } from './Navbar';
import { NavbarSkeleton } from './NavbarSkeleton';
import { NavbarRemount } from './NavbarRemount';
import { ScrollReset } from './ScrollReset';
import { getActor } from '@/lib/server/actor';
import { getDashboardData } from '@/lib/server/queries';

interface AppShellProps {
  children: React.ReactNode;
}

async function NavbarData() {
  const [actor, data] = await Promise.all([
    getActor(),
    getDashboardData(),
  ]);
  const users = (data.users || []) as any[];
  return <Navbar users={users} currentUser={actor as any} />;
}

export const AppShell: React.FC<AppShellProps> = ({ children }) => (
  <>
    <ScrollReset />
    <NavbarRemount>
      <Suspense fallback={<NavbarSkeleton />}>
        <NavbarData />
      </Suspense>
    </NavbarRemount>
    {children}
  </>
);

export default AppShell;
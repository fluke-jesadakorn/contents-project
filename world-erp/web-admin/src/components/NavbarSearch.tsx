'use client';

import React, { useState } from 'react';
import { useRouter } from 'next/navigation';
import { CommandPalette } from './CommandPalette';
import type { RoleName } from '@/lib/permissions';

interface NavbarSearchProps {
  role: RoleName | undefined;
  users: any[];
  currentUser: any;
}

export const NavbarSearch: React.FC<NavbarSearchProps> = ({ role, users, currentUser }) => {
  const router = useRouter();
  const [open, setOpen] = useState(false);

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        aria-label="Search"
        className="w-9 h-9 inline-flex items-center justify-center rounded-xl bg-slate-900/60 border border-slate-800 text-slate-300 hover:text-white"
      >
        <span className="text-base">🔍</span>
      </button>

      <CommandPalette
        role={role}
        onNavigate={(href) => router.push(href)}
        users={users}
        currentUser={currentUser}
        openCommand={open}
        setOpenCommand={setOpen}
      />
    </>
  );
};

export default NavbarSearch;
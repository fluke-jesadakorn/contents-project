import React from 'react';
import Link from 'next/link';
import type { RoleName } from '@/lib/permissions';
import { roleAccent } from './UserAvatar';
import { PersonaMenu } from './PersonaMenu';
import { NavbarSearch } from './NavbarSearch';
import { NotificationBell } from './NotificationBell';

interface NavbarProps {
  users: any[];
  currentUser: any;
  onOpenMobileNav?: () => void;
}

function envLabel(): string {
  const env = (typeof process !== 'undefined' && (process as any).env?.NEXT_PUBLIC_ENV) || 'dev';
  return env.toUpperCase();
}

export const Navbar: React.FC<NavbarProps> = ({
  users,
  currentUser,
  onOpenMobileNav,
}) => {
  const role = (currentUser?.role_name || undefined) as RoleName | undefined;

  return (
    <header
      role="banner"
      className={[
        'sticky top-0 z-50 flex items-center gap-2 px-3 sm:px-4 lg:px-6 py-2.5 mb-6',
        'glass-panel-heavy border-b border-slate-800/80',
        'shadow-xl shadow-black/40',
      ].join(' ')}
    >
      {onOpenMobileNav && (
        <button
          type="button"
          aria-label="Open menu"
          className="md:hidden w-9 h-9 inline-flex items-center justify-center rounded-xl bg-slate-900/60 border border-slate-800 text-slate-300 hover:text-white"
          onClick={onOpenMobileNav}
        >
          ☰
        </button>
      )}

      <Link
        href="/"
        aria-label="Go to home"
        className="flex items-center gap-2.5 min-w-0 rounded-xl px-1 py-1 -ml-1 hover:bg-slate-800/40 transition-colors"
      >
        <div
          className={[
            'w-9 h-9 rounded-2xl text-white shadow-lg inline-flex items-center justify-center text-base',
            roleAccent(role as string),
          ].join(' ')}
          aria-hidden
        >
          📊
        </div>
        <div className="min-w-0">
          <div className="flex items-center gap-1.5">
            <h1 className="text-base sm:text-lg font-black tracking-tight bg-gradient-to-r from-white via-slate-100 to-indigo-300 bg-clip-text text-transparent truncate">
              World ERP
            </h1>
            <span className="text-[9px] px-1.5 py-0.5 rounded-full bg-slate-900 border border-slate-800 text-slate-400 font-mono font-bold uppercase tracking-wider">
              {envLabel()}
            </span>
          </div>
          <p className="text-[10px] text-slate-500 font-sans truncate hidden sm:block">
            AI Finance · OCR · Policy Engine · Cockpit
          </p>
        </div>
      </Link>

      <div className="flex-1" />

      <NavbarSearch
        role={role}
        users={users}
        currentUser={currentUser}
      />

      <NotificationBell />

      <PersonaMenu users={users} currentUser={currentUser} />
    </header>
  );
};

export default Navbar;
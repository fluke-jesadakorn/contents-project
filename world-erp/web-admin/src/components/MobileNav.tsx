'use client';

import React, { useEffect } from 'react';
import type { RoleName } from '@/lib/roles/display';
import { UserAvatar, roleGlyph, roleAccent } from './UserAvatar';

interface MobileNavProps {
  open: boolean;
  onClose: () => void;
  role: RoleName | undefined;
  currentUser: any;
}

export const MobileNav: React.FC<MobileNavProps> = ({
  open,
  onClose,
  role,
  currentUser,
}) => {
  useEffect(() => {
    if (open) {
      document.body.style.overflow = 'hidden';
    } else {
      document.body.style.overflow = '';
    }
    return () => { document.body.style.overflow = ''; };
  }, [open]);

  return (
    <>
      <div
        className={[
          'fixed inset-0 bg-slate-950/70 backdrop-blur-sm z-[60] transition-opacity md:hidden',
          open ? 'opacity-100 pointer-events-auto' : 'opacity-0 pointer-events-none',
        ].join(' ')}
        onClick={onClose}
        aria-hidden
      />
      <aside
        className={[
          'fixed left-0 top-0 bottom-0 z-[70] w-80 max-w-[85vw] glass-panel-heavy border-r border-slate-800/80 md:hidden transition-transform duration-300',
          open ? 'translate-x-0' : '-translate-x-full',
        ].join(' ')}
        aria-hidden={!open}
      >
        <div className="px-4 pt-5 pb-4 border-b border-slate-800/80 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className={['w-9 h-9 rounded-xl bg-gradient-to-tr text-white inline-flex items-center justify-center text-base', roleAccent(role as string)].join(' ')}>
              📊
            </div>
            <div>
              <div className="text-sm font-black text-white">World ERP</div>
              <div className="text-[10px] text-slate-500 font-mono uppercase tracking-widest">
                {role ? (role as string).replace(/_/g, ' ') : 'No role'}
              </div>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="w-9 h-9 rounded-xl bg-slate-900 border border-slate-800 inline-flex items-center justify-center text-slate-400 hover:text-white"
            aria-label="Close menu"
          >
            ✕
          </button>
        </div>

        <div className="px-4 py-4 space-y-1 overflow-y-auto h-[calc(100%-1px)]">
          {currentUser && (
            <div className="flex items-center gap-3 px-3 py-3 mb-3 rounded-2xl bg-slate-950/60 border border-slate-800">
              <UserAvatar fullname={currentUser.fullname} role={currentUser.role_name} size="md" />
              <div className="min-w-0">
                <div className="text-sm font-bold truncate text-white">{currentUser.fullname}</div>
                <div className="text-[10px] text-slate-500 font-mono truncate">{currentUser.employee_code}</div>
              </div>
              <span className="ml-auto text-base" aria-hidden>{roleGlyph(currentUser.role_name)}</span>
            </div>
          )}

          <div className="pt-3 mt-3 border-t border-slate-800/80 flex items-center gap-2 text-[10px] font-mono text-slate-400">
            <span className="w-2 h-2 rounded-full bg-emerald-400" />
            <span>READY</span>
          </div>
        </div>
      </aside>
    </>
  );
};
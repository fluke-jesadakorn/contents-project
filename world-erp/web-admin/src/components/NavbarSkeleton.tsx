import React from 'react';

export const NavbarSkeleton: React.FC = () => {
  return (
    <header
      role="banner"
      aria-busy="true"
      aria-live="polite"
      className={[
        'sticky top-0 z-50 flex items-center gap-2 px-3 sm:px-4 lg:px-6 py-2.5 mb-6',
        'glass-panel-heavy border-b border-slate-800/80',
        'shadow-xl shadow-black/40',
      ].join(' ')}
    >
      <div className="w-9 h-9 rounded-xl bg-slate-800/70 border border-slate-800 animate-pulse md:hidden" />

      <div className="flex items-center gap-2.5 min-w-0 rounded-xl px-1 py-1">
        <div className="w-9 h-9 rounded-2xl bg-slate-800/70 animate-pulse" />
        <div className="min-w-0 space-y-1.5">
          <div className="flex items-center gap-1.5">
            <div className="h-4 w-28 rounded-md bg-slate-800/70 animate-pulse" />
            <div className="h-3 w-8 rounded-full bg-slate-800/60 animate-pulse" />
          </div>
          <div className="h-2.5 w-44 rounded bg-slate-800/50 animate-pulse hidden sm:block" />
        </div>
      </div>

      <div className="flex-1" />

      <div className="w-9 h-9 rounded-xl bg-slate-800/60 border border-slate-800 animate-pulse" />
      <div className="w-9 h-9 rounded-xl bg-slate-800/60 border border-slate-800 animate-pulse" />
      <div className="flex items-center gap-2 pl-1.5 pr-3 py-1.5 rounded-2xl border border-slate-800 bg-slate-900/60">
        <div className="w-7 h-7 rounded-full bg-slate-800/70 animate-pulse" />
        <div className="hidden md:flex flex-col gap-1">
          <div className="h-3 w-16 rounded bg-slate-800/70 animate-pulse" />
          <div className="h-2.5 w-12 rounded bg-slate-800/50 animate-pulse" />
        </div>
        <div className="hidden md:block w-2 h-2 rounded bg-slate-800/60 animate-pulse" />
      </div>
    </header>
  );
};

export default NavbarSkeleton;
import React from 'react';
import Link from 'next/link';

export interface Crumb {
  label: React.ReactNode;
  href?: string;
  icon?: string;
}

interface BreadcrumbProps {
  crumbs: Crumb[];
  className?: string;
}

export const Breadcrumb: React.FC<BreadcrumbProps> = ({ crumbs, className }) => {
  const safeCrumbs = Array.isArray(crumbs) ? crumbs.filter((c) => c && c.label) : [];
  if (safeCrumbs.length === 0) return null;

  return (
    <nav
      aria-label="Breadcrumb"
      className={[
        'flex items-center flex-wrap gap-x-1.5 gap-y-1 px-3 py-2 mb-4',
        'rounded-xl border border-slate-800/70 bg-slate-900/40',
        'text-[11px] font-sans',
        className || '',
      ].join(' ')}
    >
      {safeCrumbs.map((c, i) => {
        const isLast = i === safeCrumbs.length - 1;
        return (
          <React.Fragment key={`${c.label}-${i}`}>
            {i > 0 && (
              <span aria-hidden className="text-slate-700 select-none px-0.5">
                ›
              </span>
            )}
            {c.href && !isLast ? (
              <Link
                href={c.href}
                className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-slate-400 hover:text-white hover:bg-slate-800/60 transition-colors font-mono"
              >
                {c.icon && <span aria-hidden>{c.icon}</span>}
                <span>{c.label}</span>
              </Link>
            ) : (
              <span
                aria-current={isLast ? 'page' : undefined}
                className={[
                  'inline-flex items-center gap-1 px-2 py-0.5 rounded-md font-mono',
                  isLast
                    ? 'bg-indigo-500/15 text-indigo-200 border border-indigo-500/30'
                    : 'text-slate-500',
                ].join(' ')}
              >
                {c.icon && <span aria-hidden>{c.icon}</span>}
                <span className={isLast ? 'font-bold' : undefined}>{c.label}</span>
              </span>
            )}
          </React.Fragment>
        );
      })}
    </nav>
  );
};

export default Breadcrumb;

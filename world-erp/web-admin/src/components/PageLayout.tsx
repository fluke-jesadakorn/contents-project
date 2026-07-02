import React from 'react';
import { Breadcrumb, type Crumb } from './Breadcrumb';

interface PageLayoutProps {
  breadcrumbs: Crumb[];
  title: string;
  subtitle?: string;
  children: React.ReactNode;
  className?: string;
}

export const PageLayout: React.FC<PageLayoutProps> = ({
  breadcrumbs,
  title,
  subtitle,
  children,
  className,
}) => {
  return (
    <main
      className={[
        'max-w-6xl mx-auto px-6 py-10 text-slate-100 selection:bg-indigo-500 selection:text-white',
        className || '',
      ].join(' ')}
    >
      {breadcrumbs.length > 0 && (
        <Breadcrumb
          crumbs={breadcrumbs}
          className="!mb-0 !bg-transparent !border-0 !px-0 !py-0 !text-slate-500 text-[12px] font-mono"
        />
      )}

      <h1 className="mt-3 text-[28px] font-bold tracking-tight text-white leading-tight">
        {title}
      </h1>

      {subtitle && (
        <p className="mt-1 text-[13px] text-slate-400 leading-relaxed">
          {subtitle}
        </p>
      )}

      <div className="mt-8">{children}</div>
    </main>
  );
};

export default PageLayout;

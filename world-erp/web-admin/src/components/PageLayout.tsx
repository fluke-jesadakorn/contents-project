import React from 'react';

interface PageLayoutProps {
  title: string;
  subtitle?: string;
  children: React.ReactNode;
  className?: string;
}

export const PageLayout: React.FC<PageLayoutProps> = ({
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
      <h1 className="text-[28px] font-bold tracking-tight text-white leading-tight">
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
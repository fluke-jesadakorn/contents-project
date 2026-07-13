'use client';

import React, { useEffect, useState } from 'react';

const STORAGE_KEY = 'worderp.lang';
type Lang = 'de' | 'th';

export function useLang(): Lang {
  const [lang, setLangState] = useState<Lang>('th');
  useEffect(() => {
    const stored = (typeof window !== 'undefined' ? localStorage.getItem(STORAGE_KEY) : null) as Lang | null;
    if (stored === 'de' || stored === 'th') setLangState(stored);
    else setLangState('th');
  }, []);
  return lang;
}

export function setLang(lang: Lang): void {
  if (typeof window !== 'undefined') {
    localStorage.setItem(STORAGE_KEY, lang);
    document.documentElement.lang = lang;
    window.dispatchEvent(new CustomEvent('worderp:lang', { detail: lang }));
  }
}

interface Props {
  open: boolean;
  onPick: (lang: Lang) => void;
}

export function LangPicker({ open, onPick }: Props) {
  if (!open) return null;
  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label="Pick language"
      className="fixed inset-0 z-[100] flex items-center justify-center bg-slate-950/70 backdrop-blur-sm"
    >
      <div className="rounded-2xl border border-slate-800 bg-slate-900 p-6 shadow-2xl">
        <h2 className="mb-4 text-base font-bold text-white">เลือกภาษา · Sprache wählen</h2>
        <div className="flex gap-3">
          <button
            type="button"
            onClick={() => onPick('th')}
            className="flex w-32 flex-col items-center gap-1 rounded-xl border border-slate-700 bg-slate-950 p-4 text-white hover:border-cyan-500"
          >
            <span className="text-2xl" aria-hidden>🇹🇭</span>
            <span className="text-sm font-bold">ไทย</span>
            <span className="text-[10px] font-mono text-slate-500">TH</span>
          </button>
          <button
            type="button"
            onClick={() => onPick('de')}
            className="flex w-32 flex-col items-center gap-1 rounded-xl border border-slate-700 bg-slate-950 p-4 text-white hover:border-cyan-500"
          >
            <span className="text-2xl" aria-hidden>🇩🇪</span>
            <span className="text-sm font-bold">Deutsch</span>
            <span className="text-[10px] font-mono text-slate-500">DE</span>
          </button>
        </div>
      </div>
    </div>
  );
}

interface TriggerProps {
  className?: string;
}

export function LangPickerTrigger({ className }: TriggerProps) {
  const [lang, setLangState] = useState<Lang | null>(null);
  useEffect(() => {
    const stored = (typeof window !== 'undefined' ? localStorage.getItem(STORAGE_KEY) : null) as Lang | null;
    setLangState(stored);
    const handler = (e: Event) => {
      setLangState((e as CustomEvent<Lang>).detail);
    };
    window.addEventListener('worderp:lang', handler);
    return () => window.removeEventListener('worderp:lang', handler);
  }, []);

  if (!lang) return null;
  const swap = () => {
    const next: Lang = lang === 'th' ? 'de' : 'th';
    setLang(next);
    setLangState(next);
  };

  return (
    <button
      type="button"
      onClick={swap}
      title={`${lang === 'th' ? 'Waybill · ใบส่งของ' : 'Waybill · Lieferschein'}`}
      aria-label="Toggle language"
      className={
        'rounded-lg border border-slate-700 px-2 py-1 text-[10px] font-mono uppercase text-slate-300 hover:border-cyan-500 ' +
        (className ?? '')
      }
    >
      {lang === 'th' ? '🇹🇭 TH' : '🇩🇪 DE'}
    </button>
  );
}

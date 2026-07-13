'use client';

import React, { useEffect, useRef, useState } from 'react';
import { useT } from '@/components/i18n/useT';
import { T } from '@/components/i18n/T';
import type { BilingualText } from '@erp-lib/i18n/types';
import { useSecondaryLocale } from '@/components/i18n/SecondaryLocaleProvider';
import aiDict from '@erp-lib/i18n/ai';

export interface TileExplainerButtonProps {
  tileId: string;
  tileDisplayName: string;
  roleName?: string;
  fullname?: string;
  lang?: 'en' | 'th' | 'de';
}

interface ExplainerResponse {
  ok: boolean;
  text?: string;
  error?: string;
  modelName?: string;
  latencyMs?: number;
}

function stripThinking(s: string): string {
  if (!s) return s;
  return s.replace(/<think>[\s\S]*?<\/think>/g, '').trim();
}

export const TileExplainerButton: React.FC<TileExplainerButtonProps> = ({
  tileId,
  tileDisplayName,
  roleName,
  fullname,
}) => {
  const t = useT(aiDict);
  const locale = useSecondaryLocale();
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [text, setText] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [meta, setMeta] = useState<{ modelName?: string; latencyMs?: number } | null>(null);
  const [copied, setCopied] = useState(false);
  const wrapRef = useRef<HTMLDivElement | null>(null);

  const pick = (k: string): BilingualText => t(k);
  const plain = (k: string) => {
    const b = pick(k);
    return b[locale] ?? b.en;
  };
  const line = (b: BilingualText) => {
    const s = b[locale];
    return s && s !== b.en ? `${b.en} · ${s}` : b.en;
  };

  useEffect(() => {
    if (!open) return;
    function onDocClick(e: MouseEvent) {
      if (!wrapRef.current) return;
      if (!wrapRef.current.contains(e.target as Node)) setOpen(false);
    }
    function onEsc(e: KeyboardEvent) {
      if (e.key === 'Escape') setOpen(false);
    }
    document.addEventListener('mousedown', onDocClick);
    document.addEventListener('keydown', onEsc);
    return () => {
      document.removeEventListener('mousedown', onDocClick);
      document.removeEventListener('keydown', onEsc);
    };
  }, [open]);

  async function run() {
    setOpen(true);
    if (text || error) return;
    setBusy(true);
    setError(null);
    try {
      const res = await fetch('/api/tile/explainer', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ tileId, tileDisplayName, roleName, fullname, lang: locale }),
      });
      const data: ExplainerResponse = await res.json();
      if (!data.ok) {
        setError(data.error || line(pick('ai.explainer.failed')));
      } else {
        setText(stripThinking(data.text || ''));
        setMeta({ modelName: data.modelName, latencyMs: data.latencyMs });
      }
    } catch (e: any) {
      setError(e?.message || line(pick('ai.explainer.networkError')));
    } finally {
      setBusy(false);
    }
  }

  async function copy() {
    if (!text) return;
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {}
  }

  function close() {
    setOpen(false);
    setCopied(false);
  }

  return (
    <div ref={wrapRef} className="relative inline-block">
      <button
        type="button"
        onClick={run}
        disabled={busy}
        className="text-[10px] px-2.5 py-1.5 rounded-lg bg-indigo-500/15 text-indigo-200 border border-indigo-500/30 hover:bg-indigo-500/25 font-bold inline-flex items-center gap-1.5 disabled:opacity-60"
      >
        <span>{busy ? '…' : '🔍'}</span>
        <span><T value={busy ? pick('ai.explainer.thinking') : pick('ai.explainer.walkMeThrough')} /></span>
      </button>

      {open && (
        <div className="absolute left-0 top-full mt-2 w-80 z-50 glass-panel-heavy rounded-2xl border border-indigo-500/30 shadow-2xl shadow-indigo-900/40 p-3 text-left">
          <div className="flex items-center justify-between gap-2 mb-2">
            <div className="text-[10px] font-mono font-bold uppercase tracking-wider text-indigo-200 min-w-0">
              <span className="truncate block">🪟 {tileDisplayName}</span>
              {meta?.modelName && (
                <span className="mt-1 inline-block px-1.5 py-0.5 rounded bg-black/30 text-[9px] font-mono normal-case text-slate-300">
                  {meta.modelName}
                  {meta.latencyMs != null ? ` · ${meta.latencyMs}ms` : ''}
                </span>
              )}
            </div>
            <div className="flex items-center gap-1 shrink-0">
              <button
                type="button"
                onClick={copy}
                disabled={!text}
                className="text-[10px] px-2 py-0.5 rounded bg-black/30 hover:bg-black/50 disabled:opacity-30 font-mono text-slate-200"
              >
                <T value={copied ? pick('ai.explainer.copied') : pick('ai.explainer.copy')} />
              </button>
              <button
                type="button"
                onClick={close}
                aria-label={plain('ai.explainer.close')}
                title={plain('ai.explainer.close')}
                className="text-[10px] w-5 h-5 inline-flex items-center justify-center rounded bg-black/30 hover:bg-rose-900/60 text-slate-200 font-mono"
              >
                ✕
              </button>
            </div>
          </div>

          {busy && (
            <div className="flex items-center gap-1.5 py-2">
              <span className="h-1.5 w-1.5 rounded-full bg-indigo-300 animate-pulse" />
              <span className="h-1.5 w-1.5 rounded-full bg-indigo-300 animate-pulse [animation-delay:120ms]" />
              <span className="h-1.5 w-1.5 rounded-full bg-indigo-300 animate-pulse [animation-delay:240ms]" />
              <span className="ml-1 text-[10px] font-mono text-slate-400"><T value={pick('ai.explainer.askingCoach')} /></span>
            </div>
          )}

          {!busy && error && (
            <p className="text-[11px] text-rose-300 font-mono">✗ {error}</p>
          )}

          {!busy && !error && text && (
            <p className="text-[12px] whitespace-pre-wrap leading-relaxed text-slate-100 font-sans">
              {text}
            </p>
          )}

          {!busy && !error && !text && (
            <p className="text-[11px] text-slate-500 font-mono"><T value={pick('ai.explainer.noResponse')} /></p>
          )}
        </div>
      )}
    </div>
  );
};

export default TileExplainerButton;
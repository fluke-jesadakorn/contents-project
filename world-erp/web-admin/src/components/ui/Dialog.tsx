'use client';

import React, { createContext, useCallback, useContext, useState } from 'react';
import { Modal, type ModalTone } from './Modal';

type ConfirmVariant = 'default' | 'danger';

interface ConfirmOptions {
  title: string;
  message: React.ReactNode;
  confirmLabel?: string;
  cancelLabel?: string;
  tone?: ModalTone;
  variant?: ConfirmVariant;
}

interface PromptOptions extends ConfirmOptions {
  placeholder?: string;
  defaultValue?: string;
  inputType?: 'text' | 'number' | 'password';
  minLength?: number;
  validate?: (value: string) => string | null;
}

interface DialogContextValue {
  confirm: (opts: ConfirmOptions) => Promise<boolean>;
  prompt: (opts: PromptOptions) => Promise<string | null>;
}

const DialogCtx = createContext<DialogContextValue | null>(null);

type DialogState =
  | { kind: 'confirm'; opts: ConfirmOptions; resolve: (v: boolean) => void }
  | { kind: 'prompt'; opts: PromptOptions; resolve: (v: string | null) => void }
  | null;

export const DialogProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [state, setState] = useState<DialogState>(null);
  const [value, setValue] = useState('');
  const [err, setErr] = useState<string | null>(null);

  const close = useCallback(() => {
    setState(null);
    setValue('');
    setErr(null);
  }, []);

  const confirm = useCallback<DialogContextValue['confirm']>((opts) => {
    return new Promise<boolean>((resolve) => {
      setState({ kind: 'confirm', opts, resolve });
      setValue('');
      setErr(null);
    });
  }, []);

  const prompt = useCallback<DialogContextValue['prompt']>((opts) => {
    return new Promise<string | null>((resolve) => {
      setState({ kind: 'prompt', opts, resolve });
      setValue(opts.defaultValue || '');
      setErr(null);
    });
  }, []);

  const onConfirm = () => {
    if (!state) return;
    if (state.kind === 'confirm') {
      state.resolve(true);
    } else {
      const v = value.trim();
      if (state.opts.minLength != null && v.length < state.opts.minLength) {
        setErr(`Must be at least ${state.opts.minLength} characters.`);
        return;
      }
      const vErr = state.opts.validate?.(v);
      if (vErr) { setErr(vErr); return; }
      state.resolve(v);
    }
    close();
  };

  const onCancel = () => {
    if (!state) return;
    if (state.kind === 'confirm') state.resolve(false);
    else state.resolve(null);
    close();
  };

  return (
    <DialogCtx.Provider value={{ confirm, prompt }}>
      {children}
      <Modal
        open={!!state}
        onClose={onCancel}
        title={state?.opts.title}
        tone={state?.opts.tone || (state?.kind === 'confirm' && state.opts.variant === 'danger' ? 'rose' : 'indigo')}
        width="md"
        footer={
          state && (
            <>
              <button
                type="button"
                onClick={onCancel}
                className="px-4 py-2 rounded-lg bg-slate-800 text-slate-200 text-xs font-bold hover:text-white"
              >
                {state.opts.cancelLabel || 'Cancel'}
              </button>
              <button
                type="button"
                onClick={onConfirm}
                className={`px-4 py-2 rounded-lg text-xs font-bold ${
                  state.kind === 'confirm' && state.opts.variant === 'danger'
                    ? 'bg-rose-600 text-white hover:bg-rose-500'
                    : 'bg-indigo-600 text-white hover:bg-indigo-500'
                }`}
              >
                {state.opts.confirmLabel || (state.kind === 'confirm' ? 'Confirm' : 'OK')}
              </button>
            </>
          )
        }
      >
        {state && (
          <div className="space-y-3">
            <div className="text-[13px] text-slate-200 font-sans leading-relaxed">
              {state.opts.message}
            </div>
            {state.kind === 'prompt' && (
              <div>
                <input
                  autoFocus
                  type={state.opts.inputType || 'text'}
                  value={value}
                  onChange={(e) => { setValue(e.target.value); setErr(null); }}
                  onKeyDown={(e) => { if (e.key === 'Enter') onConfirm(); }}
                  placeholder={state.opts.placeholder}
                  className="w-full bg-slate-900 border border-slate-800 rounded-lg px-3 py-2 text-xs text-white focus:outline-none focus:border-indigo-500"
                />
                {state.opts.minLength != null && (
                  <p className="text-xs text-slate-500 mt-1 font-mono">
                    Min {state.opts.minLength} characters
                  </p>
                )}
                {err && (
                  <p className="text-xs text-rose-300 mt-1 font-mono">{err}</p>
                )}
              </div>
            )}
          </div>
        )}
      </Modal>
    </DialogCtx.Provider>
  );
};

export function useDialog() {
  const ctx = useContext(DialogCtx);
  if (!ctx) {
    return {
      confirm: () => Promise.resolve(window.confirm('Confirm?')), // graceful fallback
      prompt: () => Promise.resolve(window.prompt('Input:')),
    };
  }
  return ctx;
}

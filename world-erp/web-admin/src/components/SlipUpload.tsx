'use client';

import React, { useRef, useState } from 'react';

interface SlipUploadProps {
  onUploaded?: (result: any) => void;
  onUseMockToggle?: (next: boolean) => void;
  useMock?: boolean;
}

export const SlipUpload: React.FC<SlipUploadProps> = ({ onUploaded, onUseMockToggle, useMock }) => {
  const inputRef = useRef<HTMLInputElement | null>(null);
  const [dragOver, setDragOver] = useState(false);
  const [progress, setProgress] = useState(0);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [preview, setPreview] = useState<string | null>(null);

  async function uploadFile(file: File) {
    setBusy(true);
    setError(null);
    setProgress(0);
    if (file.type.startsWith('image/')) {
      setPreview(URL.createObjectURL(file));
    } else {
      setPreview(null);
    }
    try {
      const fd = new FormData();
      fd.append('file', file, file.name);
      const xhr = new XMLHttpRequest();
      const result = await new Promise((resolve, reject) => {
        xhr.open('POST', '/api/upload');
        xhr.upload.onprogress = (e: ProgressEvent) => {
          if (e.lengthComputable) setProgress(Math.round((e.loaded / e.total) * 100));
        };
        xhr.onload = () => {
          if (xhr.status >= 200 && xhr.status < 300) {
            try { resolve(JSON.parse(xhr.responseText)); }
            catch { reject(new Error('Invalid JSON response')); }
          } else {
            try {
              const j = JSON.parse(xhr.responseText);
              reject(new Error(j.detail?.error || j.error || `HTTP ${xhr.status}`));
            } catch {
              reject(new Error(`HTTP ${xhr.status}`));
            }
          }
        };
        xhr.onerror = () => reject(new Error('Network error'));
        xhr.send(fd);
      });
      onUploaded?.(result);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
      setProgress(0);
    }
  }

  function onPick(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0];
    if (f) uploadFile(f);
    e.target.value = '';
  }

  function onDrop(e: React.DragEvent<HTMLDivElement>) {
    e.preventDefault();
    setDragOver(false);
    const f = e.dataTransfer.files?.[0];
    if (f) uploadFile(f);
  }

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <h3 className="text-xs font-bold text-slate-200 uppercase tracking-wider flex items-center gap-2 font-mono">
          <span>📤</span> Real Slip Upload (Real Slip Upload → Ollama Vision OCR)
        </h3>
        <label className="flex items-center gap-2 text-[10px] font-mono text-slate-400 cursor-pointer">
          <input
            type="checkbox"
            checked={!!useMock}
            onChange={(e) => onUseMockToggle?.(e.target.checked)}
            className="accent-emerald-500"
          />
          Mock mode (mock presets)
        </label>
      </div>

      <div
        onDragOver={(e) => { e.preventDefault(); setDragOver(true); }}
        onDragLeave={() => setDragOver(false)}
        onDrop={onDrop}
        onClick={() => !busy && inputRef.current?.click()}
        className={`relative border-2 border-dashed rounded-2xl p-6 cursor-pointer transition-all ${
          dragOver
            ? 'border-emerald-400 bg-emerald-500/5'
            : 'border-slate-800 bg-slate-950/40 hover:border-emerald-500/50'
        }`}
      >
        <input
          ref={inputRef}
          type="file"
          accept="image/*,application/pdf"
          onChange={onPick}
          className="hidden"
        />
        <div className="flex items-center gap-5">
          {preview ? (
            <img src={preview} alt="preview" className="w-20 h-20 object-cover rounded-xl border border-slate-800" />
          ) : (
            <div className="w-20 h-20 rounded-xl bg-slate-900/80 flex items-center justify-center text-3xl border border-slate-800">
              📄
            </div>
          )}
          <div className="flex-1 min-w-0">
            <p className="text-sm font-bold text-white">
              {busy ? 'Processing OCR…' : 'Drag file here or click to select'}
            </p>
            <p className="text-[10px] text-slate-400 font-mono mt-1">
              Supports JPG / PNG / WEBP / PDF · Max 20 MB · Processed by Ollama qwen3-vl:4b
            </p>
            {busy && (
              <div className="mt-2 w-full bg-slate-800 h-1.5 rounded-full overflow-hidden">
                <div className="bg-emerald-500 h-full transition-all" style={{ width: `${progress}%` }} />
              </div>
            )}
            {error && (
              <p className="mt-2 text-xs text-rose-400 font-mono">⚠ {error}</p>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

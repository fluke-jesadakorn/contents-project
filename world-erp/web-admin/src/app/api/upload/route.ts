// POST /api/upload  — multipart file → OCR pipeline → persist slip row.
// Canonical upload endpoint. /api/slips is a thin alias that returns the
// same parsed data without persisting a slip row (legacy callers).

import { NextResponse } from 'next/server';
import { query } from '@/lib/db';
import { canPerformAction } from '@/lib/permissions';
import { getCurrentActor } from '@/lib/session';
import { put, publicUrlFor, makeKey } from '@erp-lib/slips/storage';
import { runOcrPipeline } from '@/lib/slips/ocrPipeline';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function POST(req: Request) {
  const actor = await getCurrentActor(req);
  if (!actor) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  if (!canPerformAction(actor.role_name, 'submit_expense') && !canPerformAction(actor.role_name, 'submit_pr')) {
    return NextResponse.json({ error: 'forbidden' }, { status: 403 });
  }

  const form = await req.formData();
  const file = form.get('file');
  if (!file || typeof file === 'string') {
    return NextResponse.json({ error: 'file is required' }, { status: 400 });
  }

  const arrayBuffer = await file.arrayBuffer();
  const buffer = Buffer.from(arrayBuffer);
  const mime = file.type || 'application/octet-stream';
  const originalName = file.name || 'slip';
  const key = makeKey(originalName);

  const stored = await put(key, buffer, mime);

  let parsed: Record<string, unknown>;
  let mode: string;
  try {
    ({ parsed, mode } = await runOcrPipeline(buffer, mime));
  } catch (err: any) {
    return NextResponse.json(
      { error: 'ocr_failed', detail: err.message },
      { status: 502 },
    );
  }

  const confidence = confidenceScoreLocal(parsed);

  const insert = await query(
    `INSERT INTO slips (file_path, mime_type, file_size, ocr_raw_json, ocr_confidence, uploaded_by)
     VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`,
    [
      stored.key,
      mime,
      stored.size,
      JSON.stringify(parsed || {}),
      confidence ?? null,
      actor.id,
    ],
  );

  const targetType = String(form.get('target_type') || '').toLowerCase();
  const targetId = Number(form.get('target_id') || 0);
  if (targetId > 0 && ['expense', 'pr', 'po'].includes(targetType)) {
    const col = targetType === 'expense' ? 'expense_id'
              : targetType === 'pr' ? 'pr_id'
              : 'po_id';
    await query(
      `UPDATE slips SET ${col} = $1 WHERE id = $2`,
      [targetId, insert.rows[0].id],
    );
  }

  return NextResponse.json({
    slipId: insert.rows[0].id,
    fileUrl: publicUrlFor(stored.key),
    fileKey: stored.key,
    mime,
    size: stored.size,
    parsed,
    confidence,
    mode,
  });
}

function confidenceScoreLocal(parsed: Record<string, unknown>): number {
  let score = 0;
  if (parsed.vendorName) score += 0.15;
  if (parsed.transactionDate) score += 0.15;
  if (Array.isArray(parsed.items) && (parsed.items as unknown[]).length > 0) score += 0.30;
  if (typeof parsed.totalAmount === 'number') score += 0.20;
  if (typeof parsed.subtotal === 'number' && typeof parsed.vatAmount === 'number') {
    const sum = +((parsed.subtotal as number) + (parsed.vatAmount as number)).toFixed(2);
    if (Math.abs(sum - +(parsed.totalAmount as number)) < 0.01) score += 0.20;
  }
  return Math.min(1, score);
}
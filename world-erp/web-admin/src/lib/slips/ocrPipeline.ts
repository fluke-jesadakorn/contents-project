// Shared OCR pipeline used by both /api/slips and /api/upload.
// Keeps the SYSTEM_PROMPT, safeParse, and confidenceScore helpers in one
// place so the two endpoints don't drift.

import { invoke } from '@erp-lib/ai/router';

export const OCR_SYSTEM_PROMPT = `You are a professional financial AI parsing agent.
Analyze the receipt image and extract values into a single JSON object.
Do not add markdown, code fences, or commentary. Return only JSON.

Schema:
{
  "vendorName": "string (store name in original language)",
  "transactionDate": "YYYY-MM-DD",
  "subtotal": number,
  "vatAmount": number,
  "totalAmount": number,
  "paymentMethod": "cash" | "credit_card" | "transfer",
  "currency": "THB" | "USD" | "...",
  "isCorrupted": boolean,
  "correctionNotes": "string (empty when not corrupted)",
  "items": [
    { "description": "string (Thai or English)", "amount": number }
  ]
}

If subtotal + vat does not equal totalAmount, set isCorrupted=true and put a short reason in correctionNotes.
Do not silently correct the math; report what the receipt shows.`;

export function safeParse(s: string): Record<string, unknown> {
  try { return JSON.parse(s); }
  catch {
    const m = s.match(/\{[\s\S]*\}/);
    if (!m) throw new Error('Vision output was not JSON');
    return JSON.parse(m[0]);
  }
}

export function confidenceScore(parsed: Record<string, unknown>): number {
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

export async function runOcrPipeline(buffer: Buffer, mime: string): Promise<{ parsed: Record<string, unknown>; mode: string }> {
  let parsed: Record<string, unknown>;
  let mode: string;
  if (mime.startsWith('image/')) {
    mode = 'vision';
    const text = await invoke('staff:ocr', 'vision', {
      systemPrompt: OCR_SYSTEM_PROMPT,
      text: `Analyze the attached receipt (${mime}).`,
      images: [`data:${mime};base64,${buffer.toString('base64')}`],
      temperature: 0.1,
    });
    if (!text.ok || !text.text) throw new Error(text.error || 'Empty response from vision');
    parsed = safeParse(text.text);
  } else {
    mode = 'text-fallback';
    const text = await invoke('staff:ocr', 'vision', {
      systemPrompt: OCR_SYSTEM_PROMPT,
      text: `Parse this receipt text:\n${buffer.toString('utf8')}`,
      temperature: 0.1,
    });
    if (!text.ok || !text.text) throw new Error(text.error || 'Empty response from text-vision');
    parsed = safeParse(text.text);
  }
  return { parsed, mode };
}
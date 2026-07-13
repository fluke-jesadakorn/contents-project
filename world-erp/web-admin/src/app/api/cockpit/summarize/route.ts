import { NextResponse } from 'next/server';
import { invoke } from '@erp-lib/ai/router';
import { loadActor } from '@/lib/server/guard';
import { parseChartBlocks } from '@/components/chat/chartContract';
import { parseExtractBlocks } from '@/components/chat/extractContract';
import { cockpitSummarizePrompt, renderLocaleAwarePrompt } from '@/lib/ai/systemPrompts';
import { getSecondaryLocaleFromHeaders } from '@erp-lib/server/locale';

export const dynamic = 'force-dynamic';

export async function POST(req: Request) {
  const actor = await loadActor();
  if (!actor) return NextResponse.json({ ok: false, error: 'unauthorized' }, { status: 401 });

  let body: any = {};
  try { body = await req.json(); } catch {}
  const { messages } = body;
  if (!Array.isArray(messages) || messages.length === 0) {
    return NextResponse.json({ ok: false, error: 'messages required' }, { status: 400 });
  }

  const lang = getSecondaryLocaleFromHeaders(req.headers);
  const systemPrompt = renderLocaleAwarePrompt(cockpitSummarizePrompt, lang);

  const result = await invoke(
    'cockpit:summarize',
    'chat',
    {
      messages,
      systemPrompt,
      temperature: 0.3,
    },
    { actorId: actor.id },
  );

  if (!result.ok) {
    return NextResponse.json({ ok: false, error: result.error || 'AI call failed' }, { status: 200 });
  }

  const fullText = (result.text || '').replace(/<think>[\s\S]*?<\/think>/g, '').trim();
  const { plain, charts } = parseChartBlocks(fullText);
  const { extracts } = parseExtractBlocks(plain);

  return NextResponse.json({
    ok: true,
    text: fullText,
    plain,
    charts,
    extracts,
    modelName: result.modelName,
    latencyMs: result.latencyMs,
  });
}
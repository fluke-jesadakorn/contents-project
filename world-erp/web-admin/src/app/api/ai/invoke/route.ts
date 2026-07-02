import { NextResponse } from 'next/server';
import { invoke } from '@erp-lib/ai/router';
import { loadActor } from '@/lib/server/guard';

export async function POST(req: Request) {
  const actor = await loadActor();
  if (!actor) return NextResponse.json({ ok: false, error: 'unauthorized' }, { status: 401 });

  const body = (await req.json().catch(() => ({}))) as { sectionKey?: string; task?: string; [k: string]: unknown };
  if (!body.sectionKey || !body.task) {
    return NextResponse.json({ ok: false, error: 'sectionKey and task are required' }, { status: 400 });
  }
  const { sectionKey, task, ...rest } = body;
  const result = await invoke(
    sectionKey,
    task as 'embed' | 'chat' | 'vision',
    rest as Parameters<typeof invoke>[2],
    { actorId: actor.id },
  );
  return NextResponse.json(result);
}
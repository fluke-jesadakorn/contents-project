import { NextResponse } from 'next/server';
import { minioClient } from '@erp-lib/slips/storage';
import { config } from '@erp-lib/config';
import { apiSlipGuard } from '@/lib/server/apiGuard';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(req: Request) {
  const url = new URL(req.url);
  const key = url.searchParams.get('key');
  if (!key || typeof key !== 'string') return NextResponse.json({ error: 'key required' }, { status: 400 });
  if (key.includes('..')) return NextResponse.json({ error: 'invalid key' }, { status: 400 });

  const guard = await apiSlipGuard(req, key);
  if (guard.response) return guard.response;

  try {
    const signed = await (minioClient as unknown as {
      presignedGetObject: (b: string, k: string, e: number) => Promise<string>;
    }).presignedGetObject(config.storage.minio.bucket, key, 600);
    return NextResponse.redirect(signed, 302);
  } catch {
    return NextResponse.json({ error: 'not found' }, { status: 404 });
  }
}
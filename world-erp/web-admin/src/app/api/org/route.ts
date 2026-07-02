import { NextResponse } from 'next/server';
import { getOrg } from '@/lib/rbac/server';

export async function GET() {
  return NextResponse.json(await getOrg());
}
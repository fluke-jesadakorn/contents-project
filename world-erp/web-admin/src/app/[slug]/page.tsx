import { redirect } from 'next/navigation';
import { getActor } from '@/lib/server/actor';
import { SlugTile } from '../(protected)/_components/SlugTile';

export const dynamic = 'force-dynamic';

interface PageProps {
  params: Promise<{ slug: string }>;
}

export default async function TilePageRoute({ params }: PageProps) {
  const { slug } = await params;
  const actor = await getActor();
  if (!actor) redirect('/?login=1');

  return <SlugTile slug={slug} actor={actor as any} />;
}
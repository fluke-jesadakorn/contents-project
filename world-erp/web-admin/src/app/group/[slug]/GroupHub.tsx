'use client';

import React, { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { CommandPalette } from '@/components/CommandPalette';
import { TileHub } from '@/components/TileHub';
import { HubHero } from '@/components/HubHero';
import { AccessDenied } from '@/components/AccessDenied';
import { PageLayout } from '@/components/PageLayout';
import { GROUP_LABEL, tileFromRow, type TileDef, type TileGroup, tileHref } from '@/components/tile-config';
import { evaluateTileOptimistic } from '@/components/tileAccess';

interface Props {
  actor: any;
  group: TileGroup;
  users: any[];
  prs: any[];
}

export function GroupHub({ actor, group, users, prs }: Props) {
  const router = useRouter();
  const [tiles, setTiles] = useState<TileDef[]>([]);
  const [tilesLoaded, setTilesLoaded] = useState(false);
  const [openCommand, setOpenCommand] = useState(false);

  useEffect(() => {
    let cancelled = false;
    fetch('/api/tiles')
      .then((r) => r.json())
      .then((data: { tiles: any[] }) => {
        if (cancelled) return;
        setTiles((data.tiles ?? []).map((t) => tileFromRow(t)).filter((t) => t.group === group));
      })
      .catch(() => {
        if (!cancelled) setTiles([]);
      })
      .finally(() => { if (!cancelled) setTilesLoaded(true); });
    return () => { cancelled = true; };
  }, [group]);

  const title = GROUP_LABEL[group].label.toUpperCase();
  const subtitle = `${tiles.length} tile${tiles.length === 1 ? '' : 's'} in ${GROUP_LABEL[group].label}`;

  const handleSelectTile = (t: any) => {
    const access = evaluateTileOptimistic(t, actor);
    if (access.state === 'open' || access.state === 'checking') router.push(tileHref(t.id));
  };

  if (actor && actor.role_name && !actor.rbac_role_id) {
    return (
      <PageLayout title={title} subtitle="Restricted">
        <AccessDenied roleName={actor.role_name} requiredAccess={`${GROUP_LABEL[group].label} group`} />
      </PageLayout>
    );
  }

  return (
    <>
      <CommandPalette
        role={actor?.role_name as any}
        onNavigate={(href) => router.push(href)}
        users={users}
        currentUser={actor}
        openCommand={openCommand}
        setOpenCommand={setOpenCommand}
        tiles={tiles}
      />

      <PageLayout title={title} subtitle={subtitle}>
        {actor && tilesLoaded && tiles.length > 0 && (
          <div className="mb-8">
            <HubHero
              actor={actor}
              tiles={tiles as any}
              pendingPrs={prs}
              isLocked={(t) => evaluateTileOptimistic(t, actor).state === 'locked'}
              onOpenCommand={() => setOpenCommand(true)}
            />
          </div>
        )}

        {actor && tilesLoaded && tiles.length > 0 && (
          <TileHub
            currentUser={actor}
            tiles={tiles}
            activeTileId=""
            onSelectTile={handleSelectTile}
          />
        )}

        {actor && tilesLoaded && tiles.length === 0 && (
          <div className="flex justify-center items-center py-10 glass-panel rounded-2xl border-slate-800">
            <span className="text-sm text-slate-400 font-sans">
              No tiles in {GROUP_LABEL[group].label}.
            </span>
          </div>
        )}
      </PageLayout>
    </>
  );
}

export default GroupHub;
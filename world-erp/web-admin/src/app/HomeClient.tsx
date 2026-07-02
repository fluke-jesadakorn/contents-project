'use client';

import React, { useEffect, useMemo, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { CommandPalette } from '@/components/CommandPalette';
import { TileHub } from '@/components/TileHub';
import { AccessDenied } from '@/components/AccessDenied';
import { PageLayout } from '@/components/PageLayout';
import { GROUP_LABEL, type TileDef, type TileGroup, tileHref, tileFromRow } from '@/components/tile-config';
import { evaluateTileOptimistic } from '@/components/tileAccess';
import { ROOT_CRUMB, groupCrumb } from '@/components/breadcrumbs';

interface HomeClientProps {
  users: any[];
  currentUser: any | null;
  expenses: any[];
  policies: any[];
  prs: any[];
  execReport: any | null;
  canViewHub: boolean;
}

export function HomeClient({ users, currentUser, expenses: _expenses, policies: _policies, prs: _prs, execReport: _execReport, canViewHub }: HomeClientProps) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const groupParam = searchParams.get('group');
  const activeGroup: TileGroup | null = (groupParam && (groupParam in GROUP_LABEL))
    ? (groupParam as TileGroup)
    : null;

  const [openCommand, setOpenCommand] = useState(false);
  const [tiles, setTiles] = useState<TileDef[]>([]);
  const [tilesLoaded, setTilesLoaded] = useState(false);

  useEffect(() => {
    let cancelled = false;
    fetch('/api/tiles')
      .then((r) => r.json())
      .then((data: { tiles: any[] }) => {
        if (cancelled) return;
        setTiles((data.tiles ?? []).map((t) => tileFromRow(t)));
      })
      .catch(() => {
        if (!cancelled) setTiles([]);
      })
      .finally(() => { if (!cancelled) setTilesLoaded(true); });
    return () => { cancelled = true; };
  }, []);

  const visibleTiles = useMemo(
    () => (activeGroup ? tiles.filter((t) => t.group === activeGroup) : tiles),
    [tiles, activeGroup],
  );

  const homeTitle = activeGroup ? GROUP_LABEL[activeGroup].label.toUpperCase() : 'Hub';
  const homeSubtitle = activeGroup
    ? `${visibleTiles.length} tile${visibleTiles.length === 1 ? '' : 's'} in ${GROUP_LABEL[activeGroup].label}`
    : (currentUser ? `${tiles.length} tiles in catalog — visibility filtered by RBAC` : 'Sign in to view your tiles');
  const homeCrumbs = activeGroup ? [ROOT_CRUMB, groupCrumb(activeGroup)] : [ROOT_CRUMB];

  const handleSelectTile = (t: any) => {
    const access = evaluateTileOptimistic(t, currentUser);
    if (access.state === 'open' || access.state === 'checking') router.push(tileHref(t.id));
  };

  if (currentUser && !canViewHub) {
    return (
      <PageLayout
        breadcrumbs={[ROOT_CRUMB]}
        title="Hub"
        subtitle="Restricted"
      >
        <AccessDenied roleName={currentUser.role_name} requiredAccess="Hub" />
      </PageLayout>
    );
  }

  return (
    <>
      <CommandPalette
        role={currentUser?.role_name as any}
        onNavigate={(href) => router.push(href)}
        users={users}
        currentUser={currentUser}
        openCommand={openCommand}
        setOpenCommand={setOpenCommand}
        tiles={tiles}
      />

      <PageLayout
        breadcrumbs={homeCrumbs}
        title={homeTitle}
        subtitle={homeSubtitle}
      >
        {!currentUser && (
          <div className="flex justify-center items-center py-10 glass-panel rounded-2xl border-indigo-500/20">
            <span className="ml-3 text-xs font-mono text-slate-300">
              No user session. POST /api/actor with a user id to sign in.
            </span>
          </div>
        )}

        {currentUser && tilesLoaded && visibleTiles.length > 0 && (
          <TileHub
            currentUser={currentUser}
            tiles={visibleTiles}
            activeTileId=""
            onSelectTile={handleSelectTile}
          />
        )}

        {currentUser && tilesLoaded && visibleTiles.length === 0 && (
          <div className="flex justify-center items-center py-10 glass-panel rounded-2xl border-slate-800">
            <span className="text-sm text-slate-400 font-sans">
              {activeGroup ? `No tiles in ${GROUP_LABEL[activeGroup].label}.` : 'No tiles in catalog.'}
            </span>
          </div>
        )}
      </PageLayout>
    </>
  );
}
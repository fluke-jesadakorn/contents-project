'use client';

import React, { useState } from 'react';
import { useRouter } from 'next/navigation';
import { CommandPalette } from '@/components/CommandPalette';
import { TileHub } from '@/components/TileHub';
import { HubHero } from '@/components/HubHero';
import { AccessDenied } from '@/components/AccessDenied';
import { PageLayout } from '@/components/PageLayout';
import { BreadcrumbSetter } from '@/components/breadcrumbs/BreadcrumbSetter';
import { type TileDef, tileHref, type TileWithMeta } from '@/components/tile-config';
import { type TileAccess } from '@/components/tileAccess';
import { ROOT_CRUMB } from '@/components/breadcrumbs';

interface Props {
  users: any[];
  currentUser: any | null;
  expenses: any[];
  prs: any[];
  execReport: any | null;
  canViewHub: boolean;
  tiles: TileDef[];
  accessByTile?: Record<string, TileAccess>;
  greetingKey?: 'morning' | 'afternoon' | 'evening';
}

export function HomeHubClient({
  users, currentUser, expenses: _expenses, prs, execReport: _execReport,
  canViewHub, tiles, accessByTile, greetingKey: _greetingKey,
}: Props) {
  const router = useRouter();
  const [openCommand, setOpenCommand] = useState(false);

  const isLocked = (t: TileWithMeta) => {
    const a = accessByTile?.[t.id];
    return !!a && a.state === 'locked';
  };

  const handleSelectTile = (t: any) => {
    const access = accessByTile?.[t.id];
    if (!access || access.state === 'open') router.push(tileHref(t.id));
  };

  if (currentUser && !canViewHub) {
    return (
      <>
        <BreadcrumbSetter crumbs={[ROOT_CRUMB]} />
        <PageLayout title="Hub" subtitle="Restricted">
          <AccessDenied roleName={currentUser.role_name} requiredAccess="Hub" />
        </PageLayout>
      </>
    );
  }

  return (
    <>
      <BreadcrumbSetter crumbs={[ROOT_CRUMB]} />
      <CommandPalette
        role={currentUser?.role_name as any}
        onNavigate={(href) => router.push(href)}
        users={users}
        currentUser={currentUser}
        openCommand={openCommand}
        setOpenCommand={setOpenCommand}
        tiles={tiles}
      />
      <PageLayout title="Hub" subtitle="Your tiles, by role">
        {currentUser && tiles.length > 0 && (
          <div className="mb-8">
            <HubHero
              actor={currentUser}
              tiles={tiles as TileWithMeta[]}
              pendingPrs={prs}
              isLocked={isLocked}
              onOpenCommand={() => setOpenCommand(true)}
            />
          </div>
        )}
        {currentUser && tiles.length > 0 && (
          <TileHub
            currentUser={currentUser}
            tiles={tiles}
            activeTileId=""
            onSelectTile={handleSelectTile}
            accessByTile={accessByTile}
          />
        )}
        {currentUser && tiles.length === 0 && (
          <div className="border border-rule p-8 text-center text-mute font-mono text-xs">
            No tiles in catalog.
          </div>
        )}
      </PageLayout>
    </>
  );
}

export default HomeHubClient;
'use client';

import React, { useEffect, useState } from 'react';
import { SortableTileGrid } from './SortableTileGrid';
import { type TileGroup, targetLabel, type TileWithMeta } from '../tile-config';
import { type TileAccess } from '../tileAccess';
import { applyOrder, loadOrder, saveGroupOrder, type TileOrderMap } from '@/lib/tileOrder';

interface Props {
  group: TileGroup;
  items: Array<{ tile: TileWithMeta; access: TileAccess }>;
  activeTileId: string;
  onSelectTile: (t: any) => void;
  actorId: number;
  targetLabel: (t: any) => string;
  currentUser: any;
}

export function TileSortableGroup({
  group, items, activeTileId, onSelectTile, actorId, targetLabel, currentUser,
}: Props) {
  const [order, setOrder] = useState<string[]>([]);

  useEffect(() => {
    const stored = loadOrder(actorId);
    setOrder(stored[group] ?? []);
  }, [actorId, group]);

  const orderMap: TileOrderMap = { [group]: order };
  const sortedItems = applyOrder(items, group, orderMap);

  return (
    <SortableTileGrid
      group={group}
      items={sortedItems}
      activeTileId={activeTileId}
      onSelectTile={onSelectTile}
      actorId={actorId}
      targetLabel={targetLabel}
      currentUser={currentUser}
      onOrderChange={(g, nextIds) => {
        if (g !== group) return;
        setOrder(nextIds);
        saveGroupOrder(actorId, g, nextIds);
      }}
    />
  );
}

export default TileSortableGroup;
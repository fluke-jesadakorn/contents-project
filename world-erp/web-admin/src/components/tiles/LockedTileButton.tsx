'use client';

import React, { useState } from 'react';
import { Icon } from '@/components/icons';
import { TileTooltip } from '../TileTooltip';
import { RequestAccessModal } from '../RequestAccessModal';
import { tileAccentToTone, tileIconFromEmoji, type TileWithMeta } from '../tile-config';

interface Props {
  tile: TileWithMeta;
  active?: boolean;
  reason?: string;
  requiredRoles?: string[];
  onRequestAccess?: () => void;
  actorId?: number;
  targetLabel?: string;
}

export function LockedTileButton({
  tile, active, reason, requiredRoles, onRequestAccess, actorId, targetLabel,
}: Props) {
  const tone = tileAccentToTone(tile.accent);
  const [requestOpen, setRequestOpen] = useState(false);
  const viewPermId = tile.access_meta?.viewPermId ?? tile.view_perm_id ?? null;

  const content = (
    <>
      <div className={`absolute top-0 left-0 right-0 h-1 ${tone.bar} opacity-25`} />

      <div className="glass-panel absolute top-2 right-2 inline-flex items-center gap-1 px-1.5 py-0.5 text-sm font-mono uppercase tracking-wider text-ink-2 z-10">
        <Icon name="lock" size={10} /> Locked
      </div>

      <div className="relative h-full flex flex-col p-4">
        <div className="flex items-start justify-between gap-2">
          <span className="text-mute group-hover:text-ink-2">
            <Icon name={(tileIconFromEmoji(tile.icon) as any) || 'square'} size={22} />
          </span>
          {tile.count !== undefined && (
            <span className="font-display text-2xl font-medium num-tabular leading-none text-mute">
              {typeof tile.count === 'number'
                ? (tile.count as number).toLocaleString()
                : tile.count}
            </span>
          )}
        </div>

        <div className="mt-auto pt-3">
          <h3 className="font-display text-sm font-medium leading-tight text-mute">
            {tile.display_name}
          </h3>
          {tile.subtitle && (
            <p className="mt-1 text-xs leading-snug line-clamp-2 text-mute">{tile.subtitle}</p>
          )}
          {viewPermId && (
            <div className="mt-2 text-sm font-mono uppercase tracking-wider text-mute truncate">
              🔒 restricted
            </div>
          )}
        </div>
      </div>
    </>
  );

  const className = [
    'group relative h-[176px] w-full overflow-hidden',
    'glass-panel border-l-4 rounded-2xl',
    tone.leftRule,
    'opacity-55 cursor-not-allowed transition-all duration-150',
  ].join(' ');

  const tooltipBody = (
    <div className="space-y-1.5">
      <div className="text-sm text-ink">{reason || tile.display_name}</div>
      {viewPermId && (
        <div className="text-sm font-mono text-mute"><span className="text-mute">perm:</span> {viewPermId}</div>
      )}
      {requiredRoles && requiredRoles.length > 0 && (
        <div className="text-sm font-mono text-mute">
          <span className="text-mute">roles:</span> {requiredRoles.join(', ')}
        </div>
      )}
      <button
        type="button"
        onClick={(e) => { e.preventDefault(); e.stopPropagation(); setRequestOpen(true); onRequestAccess?.(); }}
        className="glass-tint-info mt-1 inline-flex items-center gap-1.5 px-2 py-1 text-sm font-mono uppercase tracking-wider text-info hover:"
      >
        Request access
      </button>
    </div>
  );

  return (
    <>
      <TileTooltip content={tooltipBody}>
        <button type="button" aria-disabled className={className}>
          {content}
        </button>
      </TileTooltip>
      {actorId && (
        <RequestAccessModal
          open={requestOpen}
          onClose={() => setRequestOpen(false)}
          tile={tile as any}
          actorId={actorId}
          targetLabel={targetLabel || 'HR Manager'}
        />
      )}
    </>
  );
}

export default LockedTileButton;
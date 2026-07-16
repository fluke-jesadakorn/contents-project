'use client';

import React, { useState } from 'react';
import { CommandPalette } from './CommandPalette';
import { Icon } from '@/components/icons';
import { useT } from '@/components/i18n/useT';
import { T } from '@/components/i18n/T';
import chromeDict from '@erp-lib/i18n/chrome';

interface Props { users: any[]; currentUser: any; role?: any; }

export function CmdPaletteOpener({ users, currentUser, role }: Props) {
  const [open, setOpen] = useState(false);
  const t = useT(chromeDict);

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        aria-label={t('chrome.cmd.opener.aria').en}
        className="inline-flex items-center gap-2 w-full h-9 px-3 border border-rule bg-paper-2 text-mute hover:text-ink hover:border-rule-strong transition-colors"
      >
        <Icon name="search" size={14} />
        <span className="text-sm font-sans"><T value={t('chrome.cmd.opener.placeholder')} /></span>
        <kbd className="ml-auto text-[10px] font-mono uppercase tracking-wider text-mute px-1.5 py-0.5 border border-rule">⌘K</kbd>
      </button>

      <CommandPalette
        role={role}
        onNavigate={() => {}}
        users={users}
        currentUser={currentUser}
        openCommand={open}
        setOpenCommand={setOpen}
      />
    </>
  );
}

export default CmdPaletteOpener;

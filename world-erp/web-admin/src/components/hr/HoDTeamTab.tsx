'use client';

import React, { useEffect, useState } from 'react';
import { TeamManageView } from '@/components/workspaces/TeamManageView';
import type { RoleOption, UserRow } from '@/components/workspaces/UserEditModal';

interface HoDTeamTabProps {
  currentUser: any;
}

export const HoDTeamTab: React.FC<HoDTeamTabProps> = ({ currentUser }) => {
  const [users, setUsers] = useState<UserRow[]>([]);
  const [roleOptions, setRoleOptions] = useState<RoleOption[]>([]);
  const [loading, setLoading] = useState(true);

  const refresh = async () => {
    setLoading(true);
    const [dirRes, roleRes] = await Promise.all([
      fetch('/api/users?include_inactive=true').then((r) => r.json()),
      fetch('/api/roles/options').then((r) => r.json()),
    ]);
    setUsers(dirRes.users || []);
    setRoleOptions(roleRes.roles || []);
    setLoading(false);
  };

  useEffect(() => {
    refresh();
  }, [currentUser?.id]);

  if (loading) {
    return (
      <div className="glass-panel p-8 rounded-3xl border-slate-800 text-center text-slate-500 font-mono text-xs">
        <span className="animate-pulse">⏳ Loading your team…</span>
      </div>
    );
  }

  const directReports = users.filter((u) => u.reports_to_user_id === currentUser.id);
  const directIds = new Set(directReports.map((u) => u.id));
  const seen = new Set<number>();
  const stack = [...directIds];
  let indirectCount = 0;
  while (stack.length) {
    const cur = stack.pop()!;
    if (seen.has(cur)) continue;
    seen.add(cur);
    const children = users.filter((u) => u.reports_to_user_id === cur);
    indirectCount += children.length;
    stack.push(...children.map((c) => c.id));
  }

  return (
    <TeamManageView
      actorId={currentUser.id}
      directReports={directReports}
      indirectCount={indirectCount}
      roleOptions={roleOptions}
      onRefresh={refresh}
    />
  );
};
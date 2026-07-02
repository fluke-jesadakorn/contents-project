import React, { useMemo, useState } from 'react';
import { UserAvatar, roleGlyph } from '../UserAvatar';
import { UserEditModal, type RoleOption, type UserRow } from './UserEditModal';
import { useToast } from '@/components/ui';

interface TeamManageViewProps {
  actorId: number;
  directReports: UserRow[];
  indirectCount: number;
  roleOptions: RoleOption[];
  onRefresh: () => Promise<void> | void;
}

export const TeamManageView: React.FC<TeamManageViewProps> = ({
  actorId,
  directReports,
  indirectCount,
  roleOptions,
  onRefresh,
}) => {
  const toast = useToast();
  const [editing, setEditing] = useState<UserRow | null>(null);

  const _roleMap = useMemo(
    () => Object.fromEntries(roleOptions.map((r) => [r.name, r])),
    [roleOptions]
  );

  async function quickChangeRole(u: UserRow, newRole: string) {
    if (newRole === u.role_name) return;
    const r = await fetch(`/api/users/${u.id}`, {
      method: 'PATCH',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ role_name: newRole }),
    }).then((res) => res.json());
    if (r.error) toast.error(r.error, "Error");
    else onRefresh();
  }

  async function toggleActive(u: UserRow) {
    const r = await fetch(`/api/users/${u.id}`, {
      method: 'PATCH',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ is_active: !u.is_active }),
    }).then((res) => res.json());
    if (r.error) toast.error(r.error, "Error");
    else onRefresh();
  }

  if (directReports.length === 0) {
    return (
      <div className="glass-panel p-10 rounded-3xl border-slate-800 text-center text-slate-500 font-mono text-sm">
        👥 You have no direct reports yet (check <code>reports_to_user_id</code> of your team)
      </div>
    );
  }

  return (
    <div className="space-y-4 animate-fade-in">
      <div className="glass-panel p-5 rounded-3xl border-amber-500/30 bg-gradient-to-br from-amber-950/20 to-slate-950">
        <div className="flex items-center justify-between">
          <div>
            <span className="text-[10px] font-mono font-black uppercase tracking-widest text-amber-300">
              👥 Team Management
            </span>
            <h2 className="text-sm font-bold text-white mt-1">
              Manage Direct Reports&apos; Permissions ({directReports.length} direct · {indirectCount} in chain)
            </h2>
            <p className="text-[11px] text-slate-400 mt-1">
              You can only change the role and status of direct reports in your chain of command
            </p>
          </div>
        </div>
      </div>

      <div className="glass-panel rounded-3xl border-slate-800 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead className="bg-slate-950/60 text-[10px] font-mono uppercase tracking-widest text-slate-500">
              <tr>
                <th className="text-left px-3 py-2.5">Person</th>
                <th className="text-left px-3 py-2.5">Level</th>
                <th className="text-left px-3 py-2.5">Current Position</th>
                <th className="text-left px-3 py-2.5">Change To</th>
                <th className="text-right px-3 py-2.5">Status</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-900">
              {directReports.map((u) => (
                <tr key={u.id} className={!u.is_active ? 'opacity-50' : ''}>
                  <td className="px-3 py-2">
                    <div className="flex items-center gap-2">
                      <UserAvatar fullname={u.fullname} role={u.role_name} level={u.level} size="xs" />
                      <div>
                        <div className="text-white font-bold">{u.fullname}</div>
                        <div className="text-[10px] font-mono text-slate-500">
                          {u.employee_code}
                        </div>
                      </div>
                    </div>
                  </td>
                  <td className="px-3 py-2 font-mono">
                    <span className="text-[10px] px-1.5 py-0.5 rounded bg-indigo-500/15 text-indigo-200 border border-indigo-500/30">
                      {typeof u.level === 'number' ? `L${u.level}` : '—'}
                    </span>
                  </td>
                  <td className="px-3 py-2 font-mono text-amber-300">
                    {roleGlyph(u.role_name)} {u.role_name}
                  </td>
                  <td className="px-3 py-2">
                    <div className="flex items-center gap-1.5">
                      <select
                        value={u.role_name}
                        onChange={(e) => quickChangeRole(u, e.target.value)}
                        className="bg-slate-950/60 border border-slate-800 rounded-lg px-2 py-1 text-[11px] text-white"
                      >
                        {roleOptions.map((r) => (
                          <option key={r.id} value={r.name}>
                            {r.name}
                          </option>
                        ))}
                      </select>
                      <button
                        type="button"
                        onClick={() => setEditing(u)}
                        className="text-[10px] font-mono px-2 py-1 rounded-lg bg-indigo-500/20 border border-indigo-500/30 text-indigo-200"
                      >
                        Edit
                      </button>
                    </div>
                  </td>
                  <td className="px-3 py-2 text-right">
                    <button
                      type="button"
                      onClick={() => toggleActive(u)}
                      className={[
                        'text-[10px] font-mono px-2 py-1 rounded-lg border',
                        u.is_active
                          ? 'bg-amber-500/15 text-amber-200 border-amber-500/30'
                          : 'bg-emerald-500/15 text-emerald-200 border-emerald-500/30',
                      ].join(' ')}
                    >
                      {u.is_active ? 'Deactivate' : 'Activate'}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {editing && (
        <UserEditModal
          open
          mode="edit"
          actorId={actorId}
          initial={editing}
          roleOptions={roleOptions}
          departments={[]}
          managerCandidates={[]}
          deptHeads={[]}
          onClose={() => setEditing(null)}
          onSaved={onRefresh}
        />
      )}
    </div>
  );
};

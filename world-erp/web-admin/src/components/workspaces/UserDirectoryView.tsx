import React, { useMemo, useState } from 'react';
import { UserAvatar, roleGlyph, roleLabel, roleBadge } from '../UserAvatar';
import { staffLevelLabel, staffLevelBadge } from '@/lib/permissions';
import { Modal } from '@/components/ui';
import { ROLE_RANK, type DisplayRoleName } from '@/lib/roles/display';

function tierRank(role: string): number {
  return ROLE_RANK[role as DisplayRoleName] ?? 99;
}

function sortByHierarchy(users: UserRow[]): UserRow[] {
  return users.slice().sort((a, b) => {
    const al = typeof a.staff_level === 'number' ? a.staff_level : 99;
    const bl = typeof b.staff_level === 'number' ? b.staff_level : 99;
    if (al !== bl) return al - bl;
    const tr = tierRank(a.role_name) - tierRank(b.role_name);
    if (tr !== 0) return tr;
    const ad = a.level ?? 99;
    const bd = b.level ?? 99;
    if (ad !== bd) return ad - bd;
    return (a.fullname || '').localeCompare(b.fullname || '');
  });
}
import {
  DepartmentHeadEditor,
  UserEditModal,
  type DeptRow,
  type RoleOption,
  type UserRow,
} from './UserEditModal';

interface UserDirectoryViewProps {
  actorId: number;
  initialUsers: UserRow[];
  roleOptions: RoleOption[];
  departments: DeptRow[];
  onRefresh: () => Promise<void> | void;
}

export const UserDirectoryView: React.FC<UserDirectoryViewProps> = ({
  actorId,
  initialUsers,
  roleOptions,
  departments,
  onRefresh,
}) => {
  const [roleFilter, setRoleFilter] = useState<string>('');
  const [deptFilter, setDeptFilter] = useState<number | ''>('');
  const [showInactive, setShowInactive] = useState(true);
  const [search, setSearch] = useState('');
  const [editing, setEditing] = useState<UserRow | null>(null);
  const [creating, setCreating] = useState(false);
  const [removing, setRemoving] = useState<UserRow | null>(null);
  const [removeConfirm, setRemoveConfirm] = useState('');
  const [removingBusy, setRemovingBusy] = useState(false);
  const [removeErr, setRemoveErr] = useState<string | null>(null);

  const managerCandidates = useMemo(() => {
    return initialUsers
      .filter((u) => u.is_active)
      .map((u) => ({
        id: u.id,
        fullname: u.fullname,
        employee_code: u.employee_code,
        role_name: u.role_name,
      }));
  }, [initialUsers]);

  const filtered = useMemo(() => {
    const list = initialUsers.filter((u) => {
      if (roleFilter && u.role_name !== roleFilter) return false;
      if (deptFilter && u.department_id !== deptFilter) return false;
      if (!showInactive && !u.is_active) return false;
      if (search) {
        const q = search.toLowerCase();
        const hay = `${u.fullname} ${u.employee_code}`.toLowerCase();
        if (!hay.includes(q)) return false;
      }
      return true;
    });
    return sortByHierarchy(list);
  }, [initialUsers, roleFilter, deptFilter, showInactive, search]);

  return (
    <div className="space-y-4 animate-fade-in">
      <div className="glass-panel p-5 rounded-3xl border-slate-800">
        <div className="flex flex-wrap items-end gap-3">
          <div className="flex-1 min-w-[180px]">
            <span className="text-[10px] font-mono uppercase tracking-widest text-slate-400 block mb-1">
              Search
            </span>
            <input
              type="text"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Name / Code / Email"
              className="w-full bg-slate-950/60 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
            />
          </div>
          <FilterSelect
            label="Position"
            value={roleFilter}
            onChange={setRoleFilter}
            options={[{ id: '', name: 'All positions' }, ...roleOptions.map((r) => ({ id: r.name, name: r.name }))]}
          />
          <FilterSelect
            label="Department"
            value={deptFilter === '' ? '' : String(deptFilter)}
            onChange={(v) => setDeptFilter(v ? Number(v) : '')}
            options={[
              { id: '', name: 'All departments' },
              ...departments.map((d) => ({ id: String(d.id), name: `${d.code} · ${d.name}` })),
            ]}
          />
          <label className="flex items-center gap-1.5 text-[11px] text-slate-300 self-end pb-2">
            <input
              type="checkbox"
              checked={showInactive}
              onChange={(e) => setShowInactive(e.target.checked)}
              className="accent-cyan-500"
            />
            <span>Show inactive</span>
          </label>
          <button
            type="button"
            onClick={() => setCreating(true)}
            className="ml-auto px-3 py-2 rounded-xl bg-cyan-500/20 border border-cyan-500/40 text-xs font-mono text-cyan-200 hover:bg-cyan-500/30"
          >
            + Add Employee
          </button>
        </div>
        <div className="text-[10px] font-mono text-slate-500 mt-3">
          Showing {filtered.length} / {initialUsers.length} people
        </div>
      </div>

      <div className="glass-panel rounded-3xl border-slate-800 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead className="bg-slate-950/60 text-[10px] font-mono uppercase tracking-widest text-slate-500">
              <tr>
                <th className="text-left px-3 py-2.5">Code</th>
                <th className="text-left px-3 py-2.5">Name</th>
                <th className="text-left px-3 py-2.5">Position</th>
                <th className="text-left px-3 py-2.5">Grade</th>
                <th className="text-left px-3 py-2.5">Org Depth</th>
                <th className="text-left px-3 py-2.5">Department</th>
                <th className="text-left px-3 py-2.5">Manager</th>
                <th className="text-left px-3 py-2.5">Status</th>
                <th className="text-right px-3 py-2.5">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-900">
              {filtered.length === 0 && (
                <tr>
                  <td
                    colSpan={9}
                    className="text-center text-slate-500 font-mono text-[11px] py-10"
                  >
                    No users found matching criteria
                  </td>
                </tr>
              )}
              {filtered.map((u) => (
                <tr
                  key={u.id}
                  className={[
                    'hover:bg-slate-900/40 transition-colors',
                    !u.is_active ? 'opacity-50' : '',
                  ].join(' ')}
                >
                  <td className="px-3 py-2 font-mono text-slate-300">{u.employee_code}</td>
                  <td className="px-3 py-2">
                    <div className="flex items-center gap-2">
                      <UserAvatar fullname={u.fullname} role={u.role_name} level={u.level} size="xs" />
                      <span className="text-white font-bold">{u.fullname}</span>
                    </div>
                  </td>
                  <td className="px-3 py-2">
                    <span
                      className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-[10px] font-bold border ${roleBadge(u.role_name)}`}
                      title={u.role_name}
                    >
                      <span aria-hidden>{roleGlyph(u.role_name)}</span>
                      {roleLabel(u.role_name)}
                    </span>
                  </td>
                  <td className="px-3 py-2 font-mono">
                    {typeof u.staff_level === 'number' ? (
                      <span
                        className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-[10px] font-bold border ${staffLevelBadge(u.staff_level)}`}
                        title={`Grade ${u.staff_level}: ${staffLevelLabel(u.staff_level)}`}
                      >
                        G{u.staff_level} · {staffLevelLabel(u.staff_level)}
                      </span>
                    ) : (
                      <span className="text-[10px] text-slate-500 font-mono">—</span>
                    )}
                  </td>
                  <td className="px-3 py-2 font-mono">
                    <span className="text-[10px] px-1.5 py-0.5 rounded bg-indigo-500/15 text-indigo-200 border border-indigo-500/30">
                      {typeof u.level === 'number' ? `L${u.level}` : '—'}
                    </span>
                  </td>
                  <td className="px-3 py-2 text-slate-300">
                    {u.dept_code ? `${u.dept_code} · ${u.dept_name}` : '—'}
                  </td>
                  <td className="px-3 py-2 text-slate-300">
                    {u.manager_code ? `${u.manager_code} · ${u.manager_name}` : '—'}
                  </td>
                  <td className="px-3 py-2">
                    {u.is_active ? (
                      <span className="text-[10px] font-mono px-1.5 py-0.5 rounded bg-emerald-500/15 text-emerald-300 border border-emerald-500/30">
                        ACTIVE
                      </span>
                    ) : (
                      <span className="text-[10px] font-mono px-1.5 py-0.5 rounded bg-slate-700 text-slate-300 border border-slate-600">
                        INACTIVE
                      </span>
                    )}
                  </td>
                  <td className="px-3 py-2 text-right">
                    <div className="inline-flex gap-1">
                      <button
                        type="button"
                        onClick={() => setEditing(u)}
                        className="text-[10px] font-mono px-2 py-1 rounded-lg bg-indigo-500/20 border border-indigo-500/30 text-indigo-200 hover:bg-indigo-500/30"
                      >
                        Edit
                      </button>
                      <button
                        type="button"
                        onClick={() => {
                          setRemoving(u);
                          setRemoveConfirm('');
                          setRemoveErr(null);
                        }}
                        disabled={u.id === actorId}
                        title={u.id === actorId ? 'You cannot remove yourself' : 'Remove this employee'}
                        className="text-[10px] font-mono px-2 py-1 rounded-lg bg-rose-500/15 border border-rose-500/30 text-rose-200 hover:bg-rose-500/30 disabled:opacity-40 disabled:cursor-not-allowed"
                      >
                        Remove
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      <UserEditModal
        open={editing !== null || creating}
        mode={editing ? 'edit' : 'create'}
        actorId={actorId}
        initial={editing || undefined}
        roleOptions={roleOptions}
        departments={departments}
        managerCandidates={managerCandidates}
        deptHeads={managerCandidates}
        onClose={() => {
          setEditing(null);
          setCreating(false);
        }}
        onSaved={() => {
          onRefresh();
        }}
      />

      {removing && (
        <Modal
          open
          onClose={() => !removingBusy && setRemoving(null)}
          title={`Remove ${removing.fullname}?`}
          subtitle="This will permanently delete the user from the system. Department head and reporting lines are unlinked first; if the user has any expense or approval history, the action will be rejected."
          tone="rose"
          footer={
            <>
              <button
                type="button"
                onClick={() => setRemoving(null)}
                disabled={removingBusy}
                className="px-4 py-2 rounded-lg bg-slate-800 text-slate-300 text-xs font-bold hover:text-white disabled:opacity-50"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={async () => {
                  if (removeConfirm !== removing.employee_code) {
                    setRemoveErr(`Please type "${removing.employee_code}" exactly`);
                    return;
                  }
                  setRemovingBusy(true);
                  setRemoveErr(null);
                  try {
                    const r = await fetch(`/api/users/${removing.id}`, { method: 'DELETE' }).then((res) => res.json());
                    if (r.error) throw new Error(r.error);
                    setRemoving(null);
                    setRemoveConfirm('');
                    await onRefresh();
                  } catch (e: any) {
                    setRemoveErr(String(e?.message || e));
                  } finally {
                    setRemovingBusy(false);
                  }
                }}
                disabled={removingBusy || removeConfirm !== removing.employee_code}
                className="px-4 py-2 rounded-lg bg-rose-600 text-white text-xs font-bold hover:bg-rose-500 disabled:opacity-40"
              >
                {removingBusy ? 'Removing…' : 'Remove permanently'}
              </button>
            </>
          }
        >
          <div>
            <div className="text-[10px] font-mono uppercase tracking-widest text-rose-300 mb-1">
              ⚠ Permanent removal
            </div>
            <div className="mt-3">
              <span className="text-[10px] font-mono uppercase tracking-widest text-slate-400 block mb-1">
                Type <span className="text-rose-200">{removing.employee_code}</span> to confirm
              </span>
              <input
                type="text"
                value={removeConfirm}
                onChange={(e) => setRemoveConfirm(e.target.value.toUpperCase())}
                placeholder={removing.employee_code}
                className="w-full bg-slate-950/60 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white font-mono"
              />
            </div>
            {removeErr && (
              <div className="mt-3 px-3 py-2 rounded-xl bg-rose-950/40 border border-rose-500/30 text-[11px] text-rose-200">
                {removeErr}
              </div>
            )}
          </div>
        </Modal>
      )}
    </div>
  );
};

const FilterSelect: React.FC<{
  label: string;
  value: string;
  onChange: (v: string) => void;
  options: { id: string; name: string }[];
}> = ({ label, value, onChange, options }) => (
  <label className="block min-w-[140px]">
    <span className="text-[10px] font-mono uppercase tracking-widest text-slate-400 block mb-1">
      {label}
    </span>
    <select
      value={value}
      onChange={(e) => onChange(e.target.value)}
      className="w-full bg-slate-950/60 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
    >
      {options.map((o) => (
        <option key={o.id || 'all'} value={o.id}>
          {o.name}
        </option>
      ))}
    </select>
  </label>
);

interface DepartmentManagerViewProps {
  actorId: number;
  departments: DeptRow[];
  managerCandidates: { id: number; fullname: string; employee_code: string; role_name: string }[];
  onRefresh: () => Promise<void> | void;
}

export const DepartmentManagerView: React.FC<DepartmentManagerViewProps> = ({
  actorId,
  departments,
  managerCandidates,
  onRefresh,
}) => {
  return (
    <div className="glass-panel rounded-3xl border-slate-800 overflow-hidden animate-fade-in">
      <div className="p-5 border-b border-slate-800">
        <h3 className="text-sm font-bold text-white">🏢 Departments & Department Heads</h3>
        <p className="text-[11px] text-slate-400 mt-1">
          Only HR Manager can change the department head
        </p>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full text-xs">
          <thead className="bg-slate-950/60 text-[10px] font-mono uppercase tracking-widest text-slate-500">
            <tr>
              <th className="text-left px-3 py-2.5">Code</th>
              <th className="text-left px-3 py-2.5">Department Name</th>
              <th className="text-right px-3 py-2.5">Active</th>
              <th className="text-left px-3 py-2.5">Department Head</th>
              <th className="text-left px-3 py-2.5">Change Head</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-900">
            {departments.map((d) => (
              <tr key={d.id} className="hover:bg-slate-900/40">
                <td className="px-3 py-2 font-mono text-cyan-300">{d.code}</td>
                <td className="px-3 py-2 text-white">{d.name}</td>
                <td className="px-3 py-2 text-right font-mono">{d.active_members}</td>
                <td className="px-3 py-2 text-slate-300">
                  {d.head_fullname ? (
                    <>
                      <span className="font-mono text-amber-300 mr-1">{d.head_code}</span>
                      {d.head_fullname}
                    </>
                  ) : (
                    <span className="text-slate-500">—</span>
                  )}
                </td>
                <td className="px-3 py-2">
                  <DepartmentHeadEditor
                    actorId={actorId}
                    dept={d}
                    candidates={managerCandidates}
                    onSaved={onRefresh}
                  />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
};

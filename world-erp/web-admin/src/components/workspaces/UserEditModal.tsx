import React, { useEffect, useState } from 'react';
import { UserAvatar, roleGlyph, roleLabel } from '../UserAvatar';
import { staffLevelLabel } from '@/lib/permissions';
import { Modal } from '@/components/ui';

export interface UserRow {
  id: number;
  employee_code: string;
  fullname: string;
  role_name: string;
  department: string | null;
  department_id: number | null;
  dept_code: string | null;
  dept_name: string | null;
  reports_to_user_id: number | null;
  manager_name: string | null;
  manager_code: string | null;
  is_active: boolean;
  level?: number;
  staff_level?: number | null;
}

export interface DeptRow {
  id: number;
  code: string;
  name: string;
  head_user_id: number | null;
  head_fullname: string | null;
  head_code: string | null;
  active_members: number;
}

export interface RoleOption {
  id: number;
  name: string;
}

interface UserEditModalProps {
  open: boolean;
  mode: 'create' | 'edit';
  actorId: number;
  initial?: UserRow | null;
  roleOptions: RoleOption[];
  departments: DeptRow[];
  managerCandidates: { id: number; fullname: string; employee_code: string; role_name: string }[];
  deptHeads: { id: number; fullname: string; employee_code: string }[];
  onClose: () => void;
  onSaved: () => void;
}

export const UserEditModal: React.FC<UserEditModalProps> = ({
  open,
  mode,
  actorId: _actorId,
  initial,
  roleOptions,
  departments,
  managerCandidates,
  onClose,
  onSaved,
}) => {
  const [fullname, setFullname] = useState('');
  const [employeeCode, setEmployeeCode] = useState('');
  const [roleName, setRoleName] = useState('');
  const [departmentId, setDepartmentId] = useState<number | ''>('');
  const [reportsToId, setReportsToId] = useState<number | ''>('');
  const [staffLevel, setStaffLevel] = useState<number | ''>('');
  const [active, setActive] = useState(true);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setErr(null);
    setBusy(false);
    if (mode === 'edit' && initial) {
      setFullname(initial.fullname || '');
      setEmployeeCode(initial.employee_code || '');
      setRoleName(initial.role_name || '');
      setDepartmentId(initial.department_id ?? '');
      setReportsToId(initial.reports_to_user_id ?? '');
      setStaffLevel(
        initial.staff_level === null || initial.staff_level === undefined
          ? ''
          : initial.staff_level
      );
      setActive(!!initial.is_active);
    } else {
      setFullname('');
      setEmployeeCode('');
      setRoleName(roleOptions[0]?.name || 'staff');
      setDepartmentId('');
      setReportsToId('');
      setStaffLevel('');
      setActive(true);
    }
  }, [open, mode, initial, roleOptions]);

  if (!open) return null;

  async function save() {
    setBusy(true);
    setErr(null);
    try {
      if (mode === 'create') {
        const r = await fetch('/api/users', {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({
            employee_code: employeeCode.trim(),
            fullname: fullname.trim(),
            role_name: roleName,
            department_id: departmentId === '' ? null : Number(departmentId),
            reports_to_user_id: reportsToId === '' ? null : Number(reportsToId),
            is_active: active,
            staff_level: staffLevel === '' ? null : Number(staffLevel),
          }),
        }).then((res) => res.json());
        if (r.error) throw new Error(r.error);
      } else if (initial) {
        const patch: Record<string, any> = {};
        if (roleName !== initial.role_name) patch.role_name = roleName;
        if (Number(departmentId || 0) !== (initial.department_id || 0)) {
          patch.department_id = departmentId === '' ? null : Number(departmentId);
        }
        if (Number(reportsToId || 0) !== (initial.reports_to_user_id || 0)) {
          patch.reports_to_user_id = reportsToId === '' ? null : Number(reportsToId);
        }
        const initialLevel = initial.staff_level ?? null;
        const nextLevel = staffLevel === '' ? null : Number(staffLevel);
        if (nextLevel !== initialLevel) patch.staff_level = nextLevel;
        if (active !== initial.is_active) patch.is_active = active;
        if (Object.keys(patch).length > 0) {
          const r = await fetch(`/api/users/${initial.id}`, {
            method: 'PATCH',
            headers: { 'content-type': 'application/json' },
            body: JSON.stringify(patch),
          }).then((res) => res.json());
          if (r.error) throw new Error(r.error);
        }
      }
      onSaved();
      onClose();
    } catch (e: any) {
      setErr(String(e?.message || e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal
      open
      onClose={onClose}
      width="lg"
      tone="cyan"
      header={
        <div className="flex items-center gap-2">
          <UserAvatar
            fullname={fullname || (initial?.fullname ?? 'New')}
            role={roleName || initial?.role_name || 'staff'}
            level={initial?.level}
            size="sm"
          />
          <div>
            <div className="text-[10px] font-mono uppercase tracking-widest text-cyan-300">
              {mode === 'create' ? 'Create User' : 'Edit User'}
            </div>
            <div className="text-sm font-bold text-white">
              {mode === 'create' ? 'Add New Employee' : initial?.fullname}
            </div>
          </div>
        </div>
      }
    >
      <div className="space-y-3">
          <Field label="Employee Code">
            <input
              type="text"
              value={employeeCode}
              disabled={mode === 'edit'}
              onChange={(e) => setEmployeeCode(e.target.value.toUpperCase())}
              placeholder="EMP017"
              className="w-full bg-slate-950/60 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white font-mono disabled:opacity-50"
            />
          </Field>

          <Field label="Full Name">
            <input
              type="text"
              value={fullname}
              onChange={(e) => setFullname(e.target.value)}
              placeholder="John Staff"
              className="w-full bg-slate-950/60 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
            />
          </Field>

          <div className="grid grid-cols-2 gap-3">
            <Field label="Position (Role)">
              <select
                value={roleName}
                onChange={(e) => setRoleName(e.target.value)}
                className="w-full bg-slate-950/60 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
              >
                {roleOptions.map((r) => (
                  <option key={r.id} value={r.name}>
                    {roleLabel(r.name)} {roleGlyph(r.name)}
                  </option>
                ))}
              </select>
            </Field>

            <Field label="Department">
              <select
                value={departmentId === '' ? '' : String(departmentId)}
                onChange={(e) => setDepartmentId(e.target.value ? Number(e.target.value) : '')}
                className="w-full bg-slate-950/60 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
              >
                <option value="">— Not specified —</option>
                {departments.map((d) => (
                  <option key={d.id} value={d.id}>
                    {d.code} · {d.name}
                  </option>
                ))}
              </select>
            </Field>
          </div>

          <Field
            label={
              <span className="flex items-center justify-between w-full">
                <span>Grade Level (1 = highest)</span>
                <span className="text-slate-500 normal-case tracking-normal text-[9px]">
                  {staffLevel === '' ? 'Using role default' : `Override → ${staffLevelLabel(Number(staffLevel))}`}
                </span>
              </span>
            }
          >
            <select
              value={staffLevel === '' ? '' : String(staffLevel)}
              onChange={(e) =>
                setStaffLevel(e.target.value === '' ? '' : Number(e.target.value))
              }
              className="w-full bg-slate-950/60 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
            >
              <option value="">— Use role default —</option>
              <option value="1">1 · CEO</option>
              <option value="2">2 · C-Level</option>
              <option value="3">3 · Manager</option>
              <option value="4">4 · Supervisor</option>
              <option value="5">5 · Officer</option>
            </select>
          </Field>

          <Field label="Manager (Reports to)">
            <select
              value={reportsToId === '' ? '' : String(reportsToId)}
              onChange={(e) => setReportsToId(e.target.value ? Number(e.target.value) : '')}
              className="w-full bg-slate-950/60 border border-slate-800 rounded-xl px-3 py-2 text-xs text-white"
            >
              <option value="">— Not specified —</option>
              {managerCandidates
                .filter((m) => (mode === 'edit' ? m.id !== initial?.id : true))
                .map((m) => (
                  <option key={m.id} value={m.id}>
                    {m.employee_code} · {m.fullname} ({m.role_name})
                  </option>
                ))}
            </select>
          </Field>

          <label className="flex items-center gap-2 text-xs text-slate-300 px-1 mt-2">
            <input
              type="checkbox"
              checked={active}
              onChange={(e) => setActive(e.target.checked)}
              className="accent-cyan-500"
            />
            <span>Active Account</span>
          </label>

          {err && (
            <div className="px-3 py-2 rounded-xl bg-rose-950/40 border border-rose-500/30 text-[11px] text-rose-200">
              {err}
            </div>
          )}

          <div className="flex gap-2 pt-2">
            <button
              type="button"
              onClick={onClose}
              className="flex-1 px-3 py-2 rounded-xl bg-slate-900 border border-slate-800 text-xs text-slate-300"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={save}
              disabled={busy}
              className="flex-1 px-3 py-2 rounded-xl bg-cyan-600 text-white text-xs font-bold hover:bg-cyan-500 disabled:opacity-50"
            >
              {busy ? 'Saving…' : mode === 'create' ? 'Create User' : 'Save'}
            </button>
          </div>
      </div>
    </Modal>
  );
};

const Field: React.FC<{ label: React.ReactNode; children: React.ReactNode }> = ({
  label,
  children,
}) => (
  <label className="block">
    <span className="text-[10px] font-mono uppercase tracking-widest text-slate-400 block mb-1">
      {label}
    </span>
    {children}
  </label>
);

interface DepartmentHeadEditorProps {
  actorId: number;
  dept: DeptRow;
  candidates: { id: number; fullname: string; employee_code: string; role_name: string }[];
  onSaved: () => void;
}

export const DepartmentHeadEditor: React.FC<DepartmentHeadEditorProps> = ({
  actorId: _actorId,
  dept,
  candidates,
  onSaved,
}) => {
  const [val, setVal] = useState<number | ''>(dept.head_user_id ?? '');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => setVal(dept.head_user_id ?? ''), [dept.head_user_id]);

  async function save() {
    setBusy(true);
    setErr(null);
    try {
      const r = await fetch('/api/departments', {
        method: 'PATCH',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          department_id: dept.id,
          head_user_id: val === '' ? null : Number(val),
        }),
      }).then((res) => res.json());
      if (r.error) throw new Error(r.error);
      onSaved();
    } catch (e: any) {
      setErr(String(e?.message || e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex flex-col gap-1.5">
      <select
        value={val === '' ? '' : String(val)}
        onChange={(e) => setVal(e.target.value ? Number(e.target.value) : '')}
        className="bg-slate-950/60 border border-slate-800 rounded-xl px-2 py-1.5 text-[11px] text-white"
      >
        <option value="">— No head yet —</option>
        {candidates.map((c) => (
          <option key={c.id} value={c.id}>
            {c.employee_code} · {c.fullname} ({c.role_name})
          </option>
        ))}
      </select>
      <button
        type="button"
        onClick={save}
        disabled={busy || val === (dept.head_user_id ?? '')}
        className="text-[10px] font-mono px-2 py-1 rounded-lg bg-cyan-500/20 border border-cyan-500/30 text-cyan-200 disabled:opacity-40"
      >
        {busy ? '…' : 'Save Head'}
      </button>
      {err && <span className="text-[10px] text-rose-300">{err}</span>}
    </div>
  );
};

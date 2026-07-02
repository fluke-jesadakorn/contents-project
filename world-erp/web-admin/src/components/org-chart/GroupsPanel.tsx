'use client';

import React, { useCallback, useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { useToast } from '@/components/ui/Toast';
import { useDialog } from '@/components/ui/Dialog';
import { access } from '@/lib/access/api';
import { useCan } from '@/lib/rbac/client';

interface TreeNode {
  id: string;
  name: string;
  kind: 'module-group' | 'department' | 'team';
  parent_id: string | null;
  sort_order: number;
  is_system: boolean;
  children: TreeNode[];
  modules: { id: string; display_name: string }[];
  roles: { id: string; name: string }[];
}

interface ModuleRow {
  id: string;
  display_name: string;
  group_name: string;
}

const KIND_OPTIONS = ['module-group', 'department', 'team'] as const;

export const GroupsPanel: React.FC<{ rbacRoleId: string | null | undefined }> = ({ rbacRoleId }) => {
  const router = useRouter();
  const toast = useToast();
  const dialog = useDialog();
  const [tree, setTree] = useState<TreeNode[]>([]);
  const [modules, setModules] = useState<ModuleRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string | null>(null);
  const [editing, setEditing] = useState<TreeNode | null>(null);
  const [creating, setCreating] = useState(false);

  const canCreate = useCan(rbacRoleId, 'rbac-manage-groups', 'create');
  const canUpdate = useCan(rbacRoleId, 'rbac-manage-groups', 'update');
  const canDelete = useCan(rbacRoleId, 'rbac-manage-groups', 'delete');

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [t, mods] = await Promise.all([
        access.groupsTree() as Promise<TreeNode[]>,
        access.modules() as Promise<ModuleRow[]>,
      ]);
      setTree(t);
      setModules(mods);
    } catch (e: any) {
      toast.error(`Failed to load groups: ${e?.message ?? 'unknown'}`);
    } finally {
      setLoading(false);
    }
  }, [toast]);

  useEffect(() => {
    void load();
  }, [load]);

  const handleCreate = async (payload: {
    id: string;
    name: string;
    kind: string;
    parent_id: string | null;
    sort_order: number;
  }) => {
    setBusy('create');
    try {
      const res = await fetch('/api/groups', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(payload),
      });
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body.error ?? `HTTP ${res.status}`);
      }
      toast.success(`Created ${payload.id}`);
      setCreating(false);
      router.refresh();
      await load();
    } catch (e: any) {
      toast.error(`Create failed: ${e?.message ?? 'unknown'}`);
    } finally {
      setBusy(null);
    }
  };

  const handleDelete = async (id: string, isSystem: boolean) => {
    if (isSystem) {
      toast.error(`${id} is a system group and cannot be deleted.`);
      return;
    }
    const ok = await dialog.confirm({
      title: 'Delete group',
      message: `Delete "${id}"? This removes its module memberships and role memberships.`,
      confirmLabel: 'Delete',
      variant: 'danger',
    });
    if (!ok) return;
    setBusy(id);
    try {
      const res = await fetch(`/api/groups/${encodeURIComponent(id)}`, { method: 'DELETE' });
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body.error ?? `HTTP ${res.status}`);
      }
      toast.success(`Deleted ${id}`);
      router.refresh();
      await load();
    } catch (e: any) {
      toast.error(`Delete failed: ${e?.message ?? 'unknown'}`);
    } finally {
      setBusy(null);
    }
  };

  const handleUpdate = async (id: string, patch: Partial<{
    name: string;
    kind: string;
    parent_id: string | null;
    sort_order: number;
  }>) => {
    setBusy(id);
    try {
      const res = await fetch(`/api/groups/${encodeURIComponent(id)}`, {
        method: 'PATCH',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(patch),
      });
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body.error ?? `HTTP ${res.status}`);
      }
      toast.success(`Updated ${id}`);
      setEditing(null);
      router.refresh();
      await load();
    } catch (e: any) {
      toast.error(`Update failed: ${e?.message ?? 'unknown'}`);
    } finally {
      setBusy(null);
    }
  };

  const handleSetModules = async (moduleId: string, groupIds: string[]) => {
    setBusy(`mod:${moduleId}`);
    try {
      const res = await fetch(`/api/modules/${encodeURIComponent(moduleId)}/groups`, {
        method: 'PUT',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ group_ids: groupIds }),
      });
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body.error ?? `HTTP ${res.status}`);
      }
      router.refresh();
      await load();
    } catch (e: any) {
      toast.error(`Set modules failed: ${e?.message ?? 'unknown'}`);
    } finally {
      setBusy(null);
    }
  };

  const allGroupIds = collectIds(tree);

  if (loading) {
    return (
      <div className="glass-panel rounded-2xl border border-slate-800 p-8 text-center text-slate-500 font-mono text-xs">
        ⏳ Loading groups…
      </div>
    );
  }

  return (
    <div className="space-y-3">
      <div className="glass-panel rounded-2xl border border-slate-800 p-3 flex items-center justify-between flex-wrap gap-2">
        <div className="flex items-center gap-2">
          <span className="text-[10px] font-mono uppercase tracking-widest text-slate-400">
            Groups
          </span>
          <span className="text-[10px] font-mono text-slate-500">
            {allGroupIds.length} groups · {modules.length} modules
          </span>
        </div>
        {canCreate && (
          <button
            type="button"
            onClick={() => setCreating(true)}
            className="inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-md border border-indigo-500/40 bg-indigo-500/15 text-indigo-200 text-[11px] font-mono font-bold uppercase tracking-wider hover:bg-indigo-500/25"
          >
            + Create group
          </button>
        )}
      </div>

      <div className="space-y-2">
        {tree.map((g) => (
          <GroupRow
            key={g.id}
            group={g}
            modules={modules}
            busy={busy}
            canUpdate={!!canUpdate}
            canDelete={!!canDelete}
            onEdit={() => setEditing(g)}
            onDelete={() => handleDelete(g.id, g.is_system)}
            onToggleModule={(modId, attach) =>
              handleSetModules(
                modId,
                attach
                  ? Array.from(new Set([...g.modules.map((m) => m.id), modId]))
                  : g.modules.map((m) => m.id).filter((x) => x !== modId),
              )
            }
          />
        ))}
        {tree.length === 0 && (
          <div className="glass-panel rounded-2xl border border-slate-800 p-6 text-center text-slate-500 font-mono text-xs">
            No groups defined.
          </div>
        )}
      </div>

      {creating && (
        <GroupDialog
          title="Create group"
          initial={{ id: '', name: '', kind: 'module-group', parent_id: null, sort_order: 0 }}
          allGroups={tree}
          busy={busy === 'create'}
          onCancel={() => setCreating(false)}
          onSubmit={(p) => handleCreate(p)}
        />
      )}
      {editing && (
        <GroupDialog
          title={`Edit ${editing.id}`}
          initial={{
            id: editing.id,
            name: editing.name,
            kind: editing.kind,
            parent_id: editing.parent_id,
            sort_order: editing.sort_order,
          }}
          allGroups={tree}
          busy={busy === editing.id}
          lockedId
          onCancel={() => setEditing(null)}
          onSubmit={(p) => handleUpdate(editing.id, p)}
        />
      )}
    </div>
  );
};

interface GroupRowProps {
  group: TreeNode;
  modules: ModuleRow[];
  busy: string | null;
  canUpdate: boolean;
  canDelete: boolean;
  onEdit: () => void;
  onDelete: () => void;
  onToggleModule: (moduleId: string, attach: boolean) => void;
}

const GroupRow: React.FC<GroupRowProps> = ({
  group, modules, busy, canUpdate, canDelete, onEdit, onDelete, onToggleModule,
}) => {
  const [showModules, setShowModules] = useState(false);
  const moduleIds = new Set(group.modules.map((m) => m.id));
  const assigned = group.modules;
  const available = modules.filter((m) => !moduleIds.has(m.id));

  return (
    <div className="glass-panel rounded-2xl border border-slate-800 p-3">
      <div className="flex items-center gap-3 flex-wrap">
        <span className="text-[10px] font-mono uppercase tracking-widest px-1.5 py-0.5 rounded bg-slate-900/70 border border-slate-800 text-slate-300">
          {group.kind}
        </span>
        <span className="font-mono text-sm font-bold text-white">{group.id}</span>
        <span className="text-xs text-slate-300">{group.name}</span>
        {group.is_system && (
          <span className="text-[9px] font-mono uppercase tracking-wider text-amber-300/80">
            system
          </span>
        )}
        {group.parent_id && (
          <span className="text-[10px] font-mono text-slate-500">
            parent: <span className="text-slate-300">{group.parent_id}</span>
          </span>
        )}
        <span className="ml-auto text-[10px] font-mono text-slate-500">
          {assigned.length} module{assigned.length === 1 ? '' : 's'} · {group.roles.length} role{group.roles.length === 1 ? '' : 's'}
        </span>
        {canUpdate && (
          <button
            type="button"
            onClick={onEdit}
            className="px-2 py-1 rounded-md border border-slate-700 bg-slate-900/60 text-slate-300 text-[11px] font-mono uppercase hover:bg-slate-800"
          >
            Edit
          </button>
        )}
        {canDelete && (
          <button
            type="button"
            onClick={onDelete}
            disabled={group.is_system || busy === group.id}
            title={group.is_system ? 'system group' : 'delete'}
            className="px-2 py-1 rounded-md border border-rose-500/40 bg-rose-500/10 text-rose-200 text-[11px] font-mono uppercase hover:bg-rose-500/20 disabled:opacity-40 disabled:cursor-not-allowed"
          >
            Delete
          </button>
        )}
      </div>

      <div className="mt-2 flex flex-wrap gap-1.5">
        {assigned.map((m) => (
          <span
            key={m.id}
            className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md border border-indigo-500/40 bg-indigo-500/15 text-indigo-200 text-[11px] font-mono"
          >
            {m.display_name}
            {canUpdate && (
              <button
                type="button"
                aria-label={`remove ${m.id}`}
                onClick={() => onToggleModule(m.id, false)}
                className="text-indigo-200/70 hover:text-rose-200"
              >
                ×
              </button>
            )}
          </span>
        ))}
        {canUpdate && (
          <button
            type="button"
            onClick={() => setShowModules((v) => !v)}
            className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md border border-dashed border-slate-700 text-slate-400 text-[11px] font-mono hover:text-white hover:border-slate-500"
          >
            {showModules ? '− modules' : '+ modules'}
          </button>
        )}
      </div>

      {showModules && available.length > 0 && (
        <div className="mt-2 flex flex-wrap gap-1.5">
          {available.map((m) => (
            <button
              key={m.id}
              type="button"
              onClick={() => onToggleModule(m.id, true)}
              className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md border border-slate-700 text-slate-300 text-[11px] font-mono hover:border-indigo-400 hover:text-indigo-200"
            >
              + {m.display_name}
            </button>
          ))}
        </div>
      )}

      {group.roles.length > 0 && (
        <div className="mt-2 flex flex-wrap gap-1.5">
          <span className="text-[10px] font-mono uppercase tracking-wider text-slate-500 mr-1">
            Roles
          </span>
          {group.roles.map((r) => (
            <span
              key={r.id}
              className="inline-flex items-center px-2 py-0.5 rounded-md border border-amber-500/40 bg-amber-500/10 text-amber-200 text-[11px] font-mono"
            >
              {r.id}
            </span>
          ))}
        </div>
      )}
    </div>
  );
};

interface GroupDialogProps {
  title: string;
  initial: {
    id: string;
    name: string;
    kind: string;
    parent_id: string | null;
    sort_order: number;
  };
  allGroups: TreeNode[];
  busy: boolean;
  lockedId?: boolean;
  onCancel: () => void;
  onSubmit: (payload: {
    id: string;
    name: string;
    kind: string;
    parent_id: string | null;
    sort_order: number;
  }) => void;
}

const GroupDialog: React.FC<GroupDialogProps> = ({
  title, initial, allGroups, busy, lockedId, onCancel, onSubmit,
}) => {
  const [id, setId] = useState(initial.id);
  const [name, setName] = useState(initial.name);
  const [kind, setKind] = useState(initial.kind);
  const [parentId, setParentId] = useState<string | null>(initial.parent_id);
  const [sortOrder, setSortOrder] = useState<number>(initial.sort_order);

  const flat = flatten(allGroups);

  const submit = () => {
    if (!id.trim() || !name.trim()) return;
    onSubmit({
      id: id.trim(),
      name: name.trim(),
      kind,
      parent_id: parentId,
      sort_order: Number.isFinite(sortOrder) ? sortOrder : 0,
    });
  };

  return (
    <div className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm flex items-center justify-center p-4">
      <div className="glass-panel rounded-2xl border border-slate-800 bg-slate-950/95 max-w-md w-full p-4 space-y-3">
        <h3 className="font-mono text-sm font-bold text-white uppercase tracking-wider">{title}</h3>

        <label className="block">
          <span className="text-[10px] font-mono uppercase tracking-widest text-slate-400">ID</span>
          <input
            type="text"
            value={id}
            onChange={(e) => setId(e.target.value)}
            disabled={lockedId}
            className="mt-1 w-full px-2 py-1.5 rounded-md bg-slate-900/70 border border-slate-700 text-sm font-mono text-white disabled:opacity-60"
            placeholder="grp-foo"
          />
        </label>

        <label className="block">
          <span className="text-[10px] font-mono uppercase tracking-widest text-slate-400">Name</span>
          <input
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            className="mt-1 w-full px-2 py-1.5 rounded-md bg-slate-900/70 border border-slate-700 text-sm font-mono text-white"
          />
        </label>

        <label className="block">
          <span className="text-[10px] font-mono uppercase tracking-widest text-slate-400">Kind</span>
          <select
            value={kind}
            onChange={(e) => setKind(e.target.value)}
            className="mt-1 w-full px-2 py-1.5 rounded-md bg-slate-900/70 border border-slate-700 text-sm font-mono text-white"
          >
            {KIND_OPTIONS.map((k) => (
              <option key={k} value={k}>{k}</option>
            ))}
          </select>
        </label>

        <label className="block">
          <span className="text-[10px] font-mono uppercase tracking-widest text-slate-400">Parent</span>
          <select
            value={parentId ?? ''}
            onChange={(e) => setParentId(e.target.value || null)}
            className="mt-1 w-full px-2 py-1.5 rounded-md bg-slate-900/70 border border-slate-700 text-sm font-mono text-white"
          >
            <option value="">— none —</option>
            {flat.map((g) => (
              <option key={g.id} value={g.id}>{g.id}</option>
            ))}
          </select>
        </label>

        <label className="block">
          <span className="text-[10px] font-mono uppercase tracking-widest text-slate-400">Sort order</span>
          <input
            type="number"
            value={sortOrder}
            onChange={(e) => setSortOrder(Number(e.target.value))}
            className="mt-1 w-full px-2 py-1.5 rounded-md bg-slate-900/70 border border-slate-700 text-sm font-mono text-white"
          />
        </label>

        <div className="flex items-center justify-end gap-2 pt-2">
          <button
            type="button"
            onClick={onCancel}
            className="px-3 py-1.5 rounded-md border border-slate-700 bg-slate-900/60 text-slate-300 text-[11px] font-mono uppercase hover:bg-slate-800"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={submit}
            disabled={busy || !id.trim() || !name.trim()}
            className="px-3 py-1.5 rounded-md border border-emerald-500/40 bg-emerald-500/15 text-emerald-200 text-[11px] font-mono font-bold uppercase hover:bg-emerald-500/25 disabled:opacity-40"
          >
            {busy ? 'Saving…' : 'Save'}
          </button>
        </div>
      </div>
    </div>
  );
};

function collectIds(nodes: TreeNode[]): string[] {
  const out: string[] = [];
  const walk = (n: TreeNode) => {
    out.push(n.id);
    n.children.forEach(walk);
  };
  nodes.forEach(walk);
  return out;
}

function flatten(nodes: TreeNode[]): TreeNode[] {
  const out: TreeNode[] = [];
  const walk = (n: TreeNode) => {
    out.push(n);
    n.children.forEach(walk);
  };
  nodes.forEach(walk);
  return out;
}
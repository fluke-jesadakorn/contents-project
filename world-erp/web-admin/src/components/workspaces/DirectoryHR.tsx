'use client';

import React, { useEffect, useState } from 'react';
import { UserDirectoryView } from './UserDirectoryView';
import type { DeptRow, RoleOption, UserRow } from './UserEditModal';

interface DirectoryHRProps {
  currentUser: any;
}

export const DirectoryHR: React.FC<DirectoryHRProps> = ({ currentUser }) => {
  const [users, setUsers] = useState<UserRow[]>([]);
  const [departments, setDepartments] = useState<DeptRow[]>([]);
  const [roleOptions, setRoleOptions] = useState<RoleOption[]>([]);
  const [loading, setLoading] = useState(true);

  const refresh = async () => {
    setLoading(true);
    const [dirRes, deptRes, roleRes] = await Promise.all([
      fetch('/api/users?include_inactive=true').then((r) => r.json()),
      fetch('/api/departments').then((r) => r.json()),
      fetch('/api/roles/options').then((r) => r.json()),
    ]);
    setUsers(dirRes.users || []);
    setDepartments(deptRes.departments || []);
    setRoleOptions(roleRes.roles || []);
    setLoading(false);
  };

  useEffect(() => {
    refresh();
  }, [currentUser?.id]);

  if (loading) {
    return (
      <div className="glass-panel p-8 rounded-3xl border-slate-800 text-center text-slate-500 font-mono text-xs">
        <span className="animate-pulse">⏳ Loading user directory…</span>
      </div>
    );
  }

  return (
    <UserDirectoryView
      actorId={currentUser.id}
      initialUsers={users}
      roleOptions={roleOptions}
      departments={departments}
      onRefresh={refresh}
    />
  );
};
'use client';

import React, { useEffect, useState } from 'react';
import { DepartmentManagerView } from './UserDirectoryView';
import type { DeptRow } from './UserEditModal';

interface DepartmentsHRProps {
  currentUser: any;
}

export const DepartmentsHR: React.FC<DepartmentsHRProps> = ({ currentUser }) => {
  const [departments, setDepartments] = useState<DeptRow[]>([]);
  const [managerCandidates, setManagerCandidates] = useState<
    { id: number; fullname: string; employee_code: string; role_name: string }[]
  >([]);
  const [loading, setLoading] = useState(true);

  const refresh = async () => {
    setLoading(true);
    const [deptRes, dirRes] = await Promise.all([
      fetch('/api/departments').then((r) => r.json()),
      fetch('/api/users?include_inactive=true').then((r) => r.json()),
    ]);
    setDepartments(deptRes.departments || []);
    {
      const users = (dirRes.users || []) as any[];
      setManagerCandidates(
        users
          .filter((u) => u.is_active)
          .map((u) => ({
            id: u.id,
            fullname: u.fullname,
            employee_code: u.employee_code,
            role_name: u.role_name,
          }))
      );
    }
    setLoading(false);
  };

  useEffect(() => {
    refresh();
  }, [currentUser?.id]);

  if (loading) {
    return (
      <div className="glass-panel p-8 rounded-3xl border-slate-800 text-center text-slate-500 font-mono text-xs">
        <span className="animate-pulse">⏳ Loading departments…</span>
      </div>
    );
  }

  return (
    <DepartmentManagerView
      actorId={currentUser.id}
      departments={departments}
      managerCandidates={managerCandidates}
      onRefresh={refresh}
    />
  );
};
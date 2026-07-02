'use client';

import React from 'react';
import { PRWorkspace } from './PRWorkspace';
import { AccessDenied } from '@/components/AccessDenied';
import { useCan } from '@/lib/rbac/client';

export interface SubordinatePRsViewProps {
  currentUser: any;
  prs: any[];
  pos: any[];
  coa: any[];
  onSubmitPr: (payload: any) => Promise<any>;
  onAdvancePr: (prId: number, decision: 'approve' | 'reject', customComment?: string) => Promise<any>;
  onSelectPr: (pr: any) => void;
  selectedPr: any;
  loading: boolean;
}

export const SubordinatePRsView: React.FC<SubordinatePRsViewProps> = (props) => {
  const rbacRoleId = props.currentUser?.rbac_role_id ?? null;
  const canView = useCan(rbacRoleId, 'tile-subordinate-prs', 'read');
  const role = props.currentUser?.role_name as string | undefined;

  if (canView === false) {
    return (
      <AccessDenied
        roleName={role}
        requiredAccess="tile-subordinate-prs module access"
      />
    );
  }
  return (
    <PRWorkspace
      currentUser={props.currentUser}
      prs={props.prs}
      pos={props.pos}
      coa={props.coa}
      onSubmitPr={props.onSubmitPr}
      onAdvancePr={props.onAdvancePr}
      onSelectPr={props.onSelectPr}
      selectedPr={props.selectedPr}
      loading={props.loading}
    />
  );
};

export default SubordinatePRsView;

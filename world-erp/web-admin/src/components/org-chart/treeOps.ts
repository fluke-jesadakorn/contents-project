// Pure helpers for the role tree. No React, no DOM.

import type { RoleNode } from '@/lib/access/api';

export function findNode(roles: RoleNode[], id: string): RoleNode | null {
  for (const r of roles) {
    if (r.id === id) return r;
    const child = findNode(r.children, id);
    if (child) return child;
  }
  return null;
}

export function isDescendantOf(
  roles: RoleNode[],
  candidateId: string,
  ancestorId: string,
): boolean {
  const ancestor = findNode(roles, ancestorId);
  if (!ancestor) return false;
  return !!findNode(ancestor.children, candidateId);
}

export function pathToNode(roles: RoleNode[], id: string): RoleNode[] {
  const path: RoleNode[] = [];
  const walk = (nodes: RoleNode[], trail: RoleNode[]): boolean => {
    for (const n of nodes) {
      const next = [...trail, n];
      if (n.id === id) {
        path.push(...next);
        return true;
      }
      if (walk(n.children, next)) return true;
    }
    return false;
  };
  walk(roles, []);
  return path;
}

export function flattenOrg(roles: RoleNode[]): RoleNode[] {
  const out: RoleNode[] = [];
  const walk = (n: RoleNode) => {
    out.push(n);
    for (const c of n.children) walk(c);
  };
  for (const r of roles) walk(r);
  return out;
}

export function countDescendants(node: RoleNode): number {
  let n = 0;
  const stack = [...node.children];
  while (stack.length) {
    const cur = stack.pop()!;
    n += 1;
    stack.push(...cur.children);
  }
  return n;
}

export interface ReparentImpact {
  oldParentId: string | null;
  oldPath: string[];
  newParentId: string;
  newPath: string[];
  movedRoleName: string;
  descendantCount: number;
}

export function computeReparentImpact(
  roles: RoleNode[],
  movedId: string,
  newParentId: string,
): ReparentImpact | null {
  if (movedId === newParentId) return null;
  if (isDescendantOf(roles, newParentId, movedId)) return null;
  const moved = findNode(roles, movedId);
  const newParent = findNode(roles, newParentId);
  if (!moved || !newParent) return null;
  return {
    oldParentId: moved.parent_id,
    oldPath: pathToNode(roles, movedId).map((n) => n.id),
    newParentId,
    newPath: [...pathToNode(roles, newParentId).map((n) => n.id), movedId],
    movedRoleName: moved.name,
    descendantCount: countDescendants(moved),
  };
}
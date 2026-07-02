import { GROUP_LABEL, type TileGroup, type TileWithMeta } from './tile-config';
import type { Crumb } from './Breadcrumb';

export const ROOT_CRUMB: Crumb = { label: 'World ERP', href: '/', icon: '🌐' };

export const groupCrumb = (group: TileGroup): Crumb => ({
  label: GROUP_LABEL[group].label.toUpperCase(),
  href: `/group/${group}`,
  icon: GROUP_LABEL[group].icon,
});

export interface CrumbSpec {
  group: TileGroup;
  tile?: Pick<TileWithMeta, 'id' | 'display_name' | 'sub_view'>;
  subView?: string | null;
  record?: { label: string; href?: string };
}

export function buildCrumbs(spec: CrumbSpec): Crumb[] {
  const crumbs: Crumb[] = [ROOT_CRUMB, groupCrumb(spec.group)];
  if (spec.tile) {
    crumbs.push({ label: spec.tile.display_name, href: `/${spec.tile.id}` });
  }
  const subView = spec.subView ?? spec.tile?.sub_view;
  if (subView) {
    crumbs.push({ label: subView });
  }
  if (spec.record) {
    crumbs.push({ label: spec.record.label, href: spec.record.href });
  }
  return crumbs;
}
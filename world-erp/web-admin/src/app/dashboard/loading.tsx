import {
  HeaderSkeleton,
  KpiSkeleton,
  PanelSkeleton,
  SkeletonGrid,
} from '@/components/ui/Loading';

export default function Loading() {
  return (
    <div className="animate-fade-in space-y-6">
      <HeaderSkeleton />
      <SkeletonGrid cols={4} count={4} renderItem={() => <KpiSkeleton />} />
      <PanelSkeleton rows={4} />
    </div>
  );
}

import React from 'react';
import { loadExpenseFullPicture } from '@/lib/server/waybill';
import { getSecondaryLocale } from '@erp-lib/server/locale';
import { WaybillExpenseCollapsible } from './WaybillExpenseCollapsible';

interface Props {
  waybillId: string;
  originId: number;
}

export async function WaybillExpenseCollapsibleBlock({ waybillId, originId }: Props) {
  const [data, locale] = await Promise.all([
    loadExpenseFullPicture(originId),
    getSecondaryLocale(),
  ]);
  if (!data) return null;
  return <WaybillExpenseCollapsible data={data} waybillId={waybillId} locale={locale} />;
}

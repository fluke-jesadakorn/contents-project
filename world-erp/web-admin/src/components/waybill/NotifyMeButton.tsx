'use client';

import React, { useTransition } from 'react';
import {
  subscribeWaybillAction,
  unsubscribeWaybillAction,
} from '@/app/actions';
import { T } from '@/components/i18n/T';
import { useSecondaryLocale } from '@/components/i18n/SecondaryLocaleProvider';

interface Props {
  waybillId: string;
  stageKey: string;
  isSubscribed: boolean;
  canSubscribe: boolean;
}

export function NotifyMeButton({
  waybillId,
  stageKey,
  isSubscribed,
  canSubscribe,
}: Props) {
  const locale = useSecondaryLocale();
  const [pending, startTransition] = useTransition();
  const action = isSubscribed ? unsubscribeWaybillAction : subscribeWaybillAction;

  if (!canSubscribe && !isSubscribed) {
    return (
      <button
        type="button"
        disabled
        title={
          locale === 'th'
            ? 'เฉพาะผู้อนุมัติที่ระบุไว้ในขั้นนี้เท่านั้น'
            : locale === 'de'
              ? 'Nur aufgeführte Genehmiger können diese Stufe beobachten'
              : 'Only listed approvers can watch this stage'
        }
        className="inline-flex items-center gap-1.5 rounded-md border border-slate-700/60 bg-slate-900/40 px-2.5 py-1 text-sm font-mono text-slate-500 opacity-60"
      >
        <span aria-hidden>🔒</span>
        <span>
          <T value={{ en: 'Not eligible to watch', th: 'ไม่มีสิทธิ์ดู', de: 'Keine Beobachtungsberechtigung' }} />
        </span>
      </button>
    );
  }

  const label = isSubscribed
    ? <T value={{ en: 'Stop watching', th: 'หยุดติดตาม', de: 'Beobachtung beenden' }} />
    : <T value={{ en: 'Notify me when this activates', th: 'แจ้งเตือนเมื่อขั้นนี้ถึงที', de: 'Benachrichtigen, wenn diese Stufe aktiviert' }} />;

  const tone = isSubscribed
    ? 'border-slate-700/60 bg-slate-900/40 text-slate-300 hover:bg-slate-800'
    : 'border-cyan-500/40 bg-cyan-500/10 text-cyan-200 hover:bg-cyan-500/20';

  return (
    <form
      action={(fd: FormData) => {
        startTransition(() => {
          void action(fd);
        });
      }}
      className="inline-flex"
    >
      <input type="hidden" name="waybillId" value={waybillId} />
      <input type="hidden" name="stageKey" value={stageKey} />
      <button
        type="submit"
        disabled={pending}
        data-testid={`notify-${stageKey}`}
        className={
          'inline-flex items-center gap-1.5 rounded-md border px-2.5 py-1 text-sm font-mono transition disabled:opacity-50 ' +
          tone
        }
      >
        <span aria-hidden>{isSubscribed ? '🔕' : '🔔'}</span>
        <span>
          {pending
            ? <T value={{ en: 'Saving…', th: 'กำลังบันทึก…', de: 'Speichert…' }} />
            : label}
        </span>
      </button>
    </form>
  );
}

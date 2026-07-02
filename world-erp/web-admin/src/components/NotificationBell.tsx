import React from 'react';
import { listRecentNotifications, listUserNotifications, listUnreadCount } from '@/lib/server/queries';
import { NotificationBellClient } from '@/components/ai/NotificationBellClient';

interface NotificationBellProps {
  userNameById?: Record<number, string>;
  hideButton?: boolean;
}

export async function NotificationBell({
  userNameById: _userNameById,
  hideButton,
}: NotificationBellProps = {}) {
  const { getActor } = await import('@/lib/server/actor');
  const actor = await getActor();

  const items = actor
    ? await listUserNotifications(actor.id, 15)
    : await listRecentNotifications(15);
  const unread = actor ? await listUnreadCount(actor.id) : items.length;

  return (
    <NotificationBellClient
      initialItems={items.map((it: any) => ({
        id: it.id,
        type: it.type,
        message: it.message,
        createdAt: it.createdAt,
        severityClass: it.severityClass,
        readAt: it.readAt ?? null,
      }))}
      unread={unread}
      hideButton={!!hideButton}
      scoped={!!actor}
    />
  );
}
-- Cover the foreign keys introduced by the notification delivery foundation.

create index if not exists pachanga_notification_delivery_outbox_recipient_idx
  on private.pachanga_notification_delivery_outbox(recipient_user_id);

create index if not exists pachanga_notification_preference_receipts_actor_idx
  on private.pachanga_notification_preference_receipts(actor_user_id);

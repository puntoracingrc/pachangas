-- Cover the notification foreign key independently from the actor replay path.

set lock_timeout = '5s';
set statement_timeout = '120s';

create index if not exists pachanga_social_inbox_receipts_notification_idx
  on private.pachanga_social_inbox_command_receipts_v1(notification_id);

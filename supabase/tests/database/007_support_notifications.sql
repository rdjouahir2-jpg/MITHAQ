begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(18);
select extensions.has_table('public','support_ticket_messages','support ticket conversation table exists');
select extensions.has_table('public','user_notifications','durable notification inbox exists');
select extensions.ok((select relrowsecurity from pg_class where oid='public.support_tickets'::regclass),'support tickets use RLS');
select extensions.ok((select relrowsecurity from pg_class where oid='public.support_ticket_messages'::regclass),'support messages use RLS');
select extensions.ok((select relrowsecurity from pg_class where oid='public.user_notifications'::regclass),'notifications use RLS');
select extensions.ok(has_function_privilege('authenticated','public.create_support_ticket(text,text,uuid)','EXECUTE'),'authenticated users can create scoped support tickets');
select extensions.ok(has_function_privilege('authenticated','public.admin_list_support_tickets()','EXECUTE'),'admin queue RPC is callable with internal role check');
select extensions.ok(has_function_privilege('authenticated','public.admin_reply_support_ticket(uuid,text,text)','EXECUTE'),'admin reply RPC is callable with internal role check');
select extensions.ok(not has_function_privilege('anon','public.create_support_ticket(text,text,uuid)','EXECUTE'),'anonymous users cannot create support tickets');
select extensions.ok(not has_function_privilege('anon','public.admin_reply_support_ticket(uuid,text,text)','EXECUTE'),'anonymous users cannot reply to tickets');
select extensions.ok(not has_table_privilege('authenticated','public.user_notifications','INSERT'),'clients cannot forge notifications');
select extensions.ok(exists(select 1 from pg_trigger where tgname='rides_notify_status_change' and not tgisinternal),'ride status changes create durable notification events');
select extensions.ok(exists(select 1 from pg_trigger where tgname='safety_reports_notify_status_change' and not tgisinternal),'safety report status changes notify the reporting user');

select extensions.ok(not has_table_privilege('authenticated','public.support_ticket_messages','INSERT'),'clients cannot forge support conversation messages');

insert into auth.users (id,aud,role,email,created_at,updated_at)
values
 ('71000000-0000-4000-8000-000000000001','authenticated','authenticated','mithaq-support-user@example.invalid',now(),now()),
 ('71000000-0000-4000-8000-000000000002','authenticated','authenticated','mithaq-support-admin@example.invalid',now(),now())
on conflict (id) do nothing;
insert into public.user_roles(user_id,role)
values ('71000000-0000-4000-8000-000000000002','admin')
on conflict do nothing;

select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000001',true);
select public.create_support_ticket('شكوى اختبار','رسالة اختبار للتأكد من حفظ التذكرة والرد.',null);
select extensions.is(
 (select count(*)::integer from public.support_ticket_messages m
  join public.support_tickets t on t.id=m.ticket_id
  where t.user_id='71000000-0000-4000-8000-000000000001'),
 1,
 'creating a ticket persists its initial message'
);

select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000002',true);
select public.admin_reply_support_ticket(
 (select id from public.support_tickets where user_id='71000000-0000-4000-8000-000000000001' order by created_at desc limit 1),
 'تم استلام الشكوى وسيتم التحقق منها.','assigned'
);
select extensions.is(
 (select count(*)::integer from public.support_ticket_messages m
  join public.support_tickets t on t.id=m.ticket_id
  where t.user_id='71000000-0000-4000-8000-000000000001'),
 2,
 'administrative reply is appended to the support conversation'
);
select extensions.is(
 (select count(*)::integer from public.user_notifications
  where user_id='71000000-0000-4000-8000-000000000001' and notification_type='support_reply'),
 1,
 'administrative reply creates a durable notification for the requester'
);
select extensions.is(
 (select status from public.support_tickets where user_id='71000000-0000-4000-8000-000000000001'),
 'assigned',
 'support ticket status advances with the administrative reply'
);

select * from extensions.finish();
rollback;

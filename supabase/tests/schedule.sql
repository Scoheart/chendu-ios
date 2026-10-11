\set ON_ERROR_STOP on

do $$
declare
  n int;
  pending boolean;
  scheduled int;
begin
  perform public.enqueue_due('2026-10-12 07:59:00+08');
  select count(*) into n from public.jobs;
  if n <> 0 then
    raise exception 'a future delivery_time enqueued % jobs', n;
  end if;

  if public.enqueue_due('2026-10-12 08:00:00+08') <> 1 then
    raise exception '08:00 should enqueue user A only';
  end if;

  select push_pending into pending
  from public.jobs
  where user_id = '11111111-1111-4111-8111-111111111111';
  if pending is not true then
    raise exception 'push_enabled user should be marked push_pending';
  end if;

  if public.enqueue_due('2026-10-12 08:00:00+08') <> 0 then
    raise exception 'the same minute enqueued a duplicate';
  end if;

  if public.enqueue_due('2026-10-12 23:30:00+08') <> 1 then
    raise exception 'a missed window should still enqueue that day';
  end if;

  select count(*) into n
  from public.jobs
  where user_id = '22222222-2222-4222-8222-222222222222'
    and push_pending = false
    and status = 'queued';
  if n <> 1 then
    raise exception 'user B job missing or marked for push';
  end if;

  select count(*) into scheduled from cron.job where jobname = 'enqueue-due';
  if scheduled <> 1 then
    raise exception 'pg_cron job enqueue-due missing';
  end if;
end $$;

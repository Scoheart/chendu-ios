-- Enqueue the day's job when the user's local clock reaches delivery_time.
-- A missed window still enqueues once that same local day. pg_cron calls this
-- every minute. The edge function only calls this; it does not synthesize audio.

alter table public.jobs
  add column push_pending boolean not null default false;

create function public.enqueue_due(p_now timestamptz default now())
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  insert into public.jobs (user_id, kind, status, run_at, created_at, push_pending)
  select
    settings.user_id,
    'generate_issue',
    'queued',
    least(p_now, now()),
    p_now,
    settings.push_enabled
  from public.user_settings settings
  where (p_now at time zone settings.timezone)::time >= settings.delivery_time
    and not exists (
      select 1
      from public.jobs existing
      where existing.user_id = settings.user_id
        and existing.kind = 'generate_issue'
        and existing.status in ('queued', 'running', 'succeeded')
        and (existing.created_at at time zone settings.timezone)::date
          = (p_now at time zone settings.timezone)::date
    );

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.enqueue_due(timestamptz) from public, anon, authenticated;
grant execute on function public.enqueue_due(timestamptz) to service_role;

create extension if not exists pg_cron;

select cron.schedule('enqueue-due', '* * * * *', $$select public.enqueue_due();$$);

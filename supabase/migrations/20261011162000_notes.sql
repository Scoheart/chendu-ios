-- Notes and reading progress. Notes are never physically deleted.

create table public.user_notes (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  issue_id uuid not null references public.issues (id) on delete cascade,
  paragraph_index integer not null,
  start_utf16 integer not null,
  length_utf16 integer not null,
  quote text not null default '',
  body text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  origin_device text
);

create table public.reading_progress (
  user_id uuid not null references auth.users (id) on delete cascade,
  issue_id uuid not null references public.issues (id) on delete cascade,
  paragraph_index integer not null default 0,
  completed boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, issue_id)
);

create function public.reject_user_note_delete()
returns trigger
language plpgsql
as $$
begin
  raise exception 'user_notes cannot be deleted; set deleted_at'
    using errcode = '42501';
end;
$$;

create trigger user_notes_no_delete
  before delete on public.user_notes
  for each row
  execute function public.reject_user_note_delete();

alter table public.user_notes enable row level security;
alter table public.reading_progress enable row level security;

grant select, insert, update on public.user_notes to authenticated;
revoke delete on public.user_notes from authenticated, anon;
grant select, insert, update, delete on public.reading_progress to authenticated;

create policy user_notes_select on public.user_notes
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy user_notes_insert on public.user_notes
  for insert to authenticated
  with check (user_id = (select auth.uid()));

create policy user_notes_update on public.user_notes
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy reading_progress_all on public.reading_progress
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- Identity, settings, and the one active generation profile.
-- A signup trigger inserts all three. Authenticated users can read and
-- update only their own rows. They cannot insert or delete.

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default ''
);

create table public.user_settings (
  user_id uuid primary key references auth.users (id) on delete cascade,
  timezone text not null default 'Asia/Shanghai',
  delivery_time time not null default '08:00',
  push_enabled boolean not null default false,
  theme text not null default 'paper',
  font_scale numeric not null default 1 check (font_scale > 0 and font_scale <= 3),
  body_font text not null default 'serif' check (body_font in ('serif', 'system')),
  handwriting_headings boolean not null default true,
  sync_notes boolean not null default true
);

create table public.generation_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users (id) on delete cascade,
  name text not null default 'default',
  is_active boolean not null default true,
  rotation jsonb not null default '{"mode":"round_robin"}'::jsonb,
  excerpt_words integer not null default 400 check (excerpt_words between 50 and 500),
  learner_level text not null default 'B1' check (learner_level in ('A2', 'B1', 'B2', 'C1', 'C2')),
  explanation_lang text not null default 'zh-CN',
  annotation_depth text not null default 'standard' check (annotation_depth in ('light', 'standard', 'deep')),
  annotation_kinds text[] not null default '{vocab,grammar,idiom}',
  vocab_count integer not null default 12 check (vocab_count between 0 and 40),
  include_ipa boolean not null default true,
  pattern_count integer not null default 4 check (pattern_count between 0 and 12),
  tasks jsonb not null default '{}'::jsonb
);

alter table public.profiles enable row level security;
alter table public.user_settings enable row level security;
alter table public.generation_profiles enable row level security;

grant select, update on public.profiles to authenticated;
grant select, update on public.user_settings to authenticated;
grant select, update on public.generation_profiles to authenticated;

create policy profiles_select on public.profiles
  for select to authenticated
  using (id = (select auth.uid()));

create policy profiles_update on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

create policy user_settings_select on public.user_settings
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy user_settings_update on public.user_settings
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy generation_profiles_select on public.generation_profiles
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy generation_profiles_update on public.generation_profiles
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1), '')
  );

  insert into public.user_settings (user_id)
  values (new.id);

  insert into public.generation_profiles (user_id, tasks)
  values (new.id, '{}'::jsonb);

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

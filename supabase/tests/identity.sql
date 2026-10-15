-- Run as the local superuser after `supabase db reset`.
-- One transaction so `set local role` is valid.

\set ON_ERROR_STOP on

begin;

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  confirmation_token,
  email_change,
  email_change_token_new,
  recovery_token
) values
  (
    '00000000-0000-0000-0000-000000000000',
    '11111111-1111-4111-8111-111111111111',
    'authenticated',
    'authenticated',
    'a@example.com',
    extensions.crypt('password', extensions.gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"display_name":"A"}'::jsonb,
    now(),
    now(),
    '',
    '',
    '',
    ''
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '22222222-2222-4222-8222-222222222222',
    'authenticated',
    'authenticated',
    'b@example.com',
    extensions.crypt('password', extensions.gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"display_name":"B"}'::jsonb,
    now(),
    now(),
    '',
    '',
    '',
    ''
  );

do $$
declare
  n int;
  tasks jsonb;
  level text;
  tz text;
begin
  select count(*) into n from public.profiles;
  if n <> 2 then
    raise exception 'expected 2 profiles, got %', n;
  end if;

  select count(*) into n from public.user_settings;
  if n <> 2 then
    raise exception 'expected 2 settings rows, got %', n;
  end if;

  select count(*) into n from public.generation_profiles;
  if n <> 2 then
    raise exception 'expected 2 generation profiles, got %', n;
  end if;

  select g.tasks, g.learner_level into tasks, level
  from public.generation_profiles g
  where g.user_id = '11111111-1111-4111-8111-111111111111';
  if tasks <> '{}'::jsonb then
    raise exception 'tasks should start empty, got %', tasks;
  end if;
  if level <> 'B1' then
    raise exception 'learner_level default should be B1, got %', level;
  end if;

  select s.timezone into tz
  from public.user_settings s
  where s.user_id = '11111111-1111-4111-8111-111111111111';
  if tz <> 'Asia/Shanghai' then
    raise exception 'timezone default should be Asia/Shanghai, got %', tz;
  end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}',
  true
);

do $$
declare
  n int;
  changed int;
begin
  select count(*) into n from public.profiles;
  if n <> 1 then
    raise exception 'A should see 1 profile, saw %', n;
  end if;

  select count(*) into n from public.user_settings;
  if n <> 1 then
    raise exception 'A should see 1 settings row, saw %', n;
  end if;

  select count(*) into n from public.generation_profiles;
  if n <> 1 then
    raise exception 'A should see 1 generation profile, saw %', n;
  end if;

  update public.user_settings
  set timezone = 'UTC'
  where user_id = '22222222-2222-4222-8222-222222222222';
  get diagnostics changed = row_count;
  if changed <> 0 then
    raise exception 'A updated B settings, rows %', changed;
  end if;

  update public.profiles
  set display_name = 'A2'
  where id = '11111111-1111-4111-8111-111111111111';
  get diagnostics changed = row_count;
  if changed <> 1 then
    raise exception 'A should update own profile, rows %', changed;
  end if;

  begin
    update public.profiles
    set id = '33333333-3333-4333-8333-333333333333'
    where id = '11111111-1111-4111-8111-111111111111';
    raise exception 'A was allowed to change profiles.id';
  exception
    when insufficient_privilege then
      null;
    when others then
      if sqlerrm not like '%row-level security%' then
        raise;
      end if;
  end;
end $$;

rollback;

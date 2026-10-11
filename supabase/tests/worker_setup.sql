-- Fixture user, RSS source, and three queued jobs for the worker integration.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
) values (
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
);

update public.generation_profiles
set tasks = '{
  "select": {"provider": "openai", "model": "gpt-4.1-mini"},
  "tts": {"provider": "openai", "model": "tts-1", "voice": "alloy"}
}'::jsonb
where user_id = '11111111-1111-4111-8111-111111111111';

insert into public.sources (id, owner_id, kind, title, url, topic, license, config)
values (
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  '11111111-1111-4111-8111-111111111111',
  'rss',
  'Fixture Wire',
  'https://fixtures.local/sample.rss',
  'stocks',
  'all-rights-reserved',
  '{"excerpt_cap": 500}'::jsonb
);

insert into public.subscriptions (user_id, source_id)
values (
  '11111111-1111-4111-8111-111111111111',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
);

insert into public.jobs (id, user_id, status, run_at, created_at) values
  (
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa01',
    '11111111-1111-4111-8111-111111111111',
    'queued',
    now(),
    now()
  ),
  (
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa02',
    '11111111-1111-4111-8111-111111111111',
    'queued',
    now(),
    now() + interval '1 second'
  ),
  (
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa03',
    '11111111-1111-4111-8111-111111111111',
    'queued',
    now(),
    now() + interval '2 seconds'
  );

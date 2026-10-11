-- After db reset: two users, one curated source, one issue each.
-- User A must not see B, must not insert an issue, and must not edit
-- platform prompts or curated sources.

\set ON_ERROR_STOP on

begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
) values
  (
    '00000000-0000-0000-0000-000000000000',
    '11111111-1111-4111-8111-111111111111',
    'authenticated', 'authenticated', 'a@example.com',
    extensions.crypt('password', extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{"display_name":"A"}'::jsonb,
    now(), now(), '', '', '', ''
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '22222222-2222-4222-8222-222222222222',
    'authenticated', 'authenticated', 'b@example.com',
    extensions.crypt('password', extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{"display_name":"B"}'::jsonb,
    now(), now(), '', '', '', ''
  );

insert into public.sources (id, owner_id, kind, title, url, topic, license)
values (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  null, 'curated', 'Curated AI', 'https://example.com/curated', 'ai', 'cc-by'
);

insert into public.articles (id, user_id, source_id, external_url, title, excerpt, content_hash, license_snapshot)
values
  (
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    '11111111-1111-4111-8111-111111111111',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'https://example.com/a', 'A story', 'excerpt a', 'hash-a', 'cc-by'
  ),
  (
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    '22222222-2222-4222-8222-222222222222',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'https://example.com/b', 'B story', 'excerpt b', 'hash-b', 'cc-by'
  );

insert into public.issues (id, user_id, article_id, issue_date, topic, title)
values
  (
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    '11111111-1111-4111-8111-111111111111',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    '2026-10-11', 'ai', 'A issue'
  ),
  (
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
    '22222222-2222-4222-8222-222222222222',
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    '2026-10-11', 'ai', 'B issue'
  );

do $$
declare
  n int;
begin
  select count(*) into n from public.prompt_templates where owner_id is null and version = 1;
  if n <> 4 then
    raise exception 'expected 4 platform prompts, got %', n;
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
  select count(*) into n from public.issues;
  if n <> 1 then
    raise exception 'A should see 1 issue, saw %', n;
  end if;

  select count(*) into n from public.articles;
  if n <> 1 then
    raise exception 'A should see 1 article, saw %', n;
  end if;

  select count(*) into n from public.prompt_templates;
  if n <> 4 then
    raise exception 'A should read 4 platform prompts, saw %', n;
  end if;

  update public.prompt_templates set body = 'nope' where owner_id is null;
  get diagnostics changed = row_count;
  if changed <> 0 then
    raise exception 'A updated a platform prompt, rows %', changed;
  end if;

  update public.sources set title = 'hacked' where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  get diagnostics changed = row_count;
  if changed <> 0 then
    raise exception 'A updated a curated source, rows %', changed;
  end if;

  insert into public.sources (owner_id, kind, title, url)
  values ('11111111-1111-4111-8111-111111111111', 'rss', 'Mine', 'https://example.com/rss');

  select count(*) into n from public.sources where owner_id = '11111111-1111-4111-8111-111111111111';
  if n <> 1 then
    raise exception 'A should own 1 source, saw %', n;
  end if;

  begin
    insert into public.issues (user_id, issue_date, title)
    values ('11111111-1111-4111-8111-111111111111', '2026-10-12', 'smuggled');
    raise exception 'A was allowed to insert an issue';
  exception
    when insufficient_privilege then
      null;
  end;
end $$;

rollback;

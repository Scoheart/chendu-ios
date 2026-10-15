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
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    now(), now(), '', '', '', ''
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '22222222-2222-4222-8222-222222222222',
    'authenticated', 'authenticated', 'b@example.com',
    extensions.crypt('password', extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    now(), now(), '', '', '', ''
  );

insert into public.sources (id, owner_id, kind, title, url, license)
values (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  null, 'curated', 'Curated', 'https://example.com/c', 'cc-by'
);

insert into public.articles (id, user_id, external_url, content_hash, license_snapshot)
values (
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  '11111111-1111-4111-8111-111111111111',
  'https://example.com/a', 'hash-a', 'cc-by'
);

insert into public.issues (id, user_id, article_id, issue_date, title)
values (
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  '11111111-1111-4111-8111-111111111111',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  '2026-10-11', 'A issue'
);

insert into public.user_notes (
  id, user_id, issue_id, paragraph_index, start_utf16, length_utf16, quote, body, updated_at
) values (
  'f1111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  0, 0, 4, 'word', 'B note', '2026-10-11 00:00:00+00'
);

do $$
begin
  delete from public.user_notes where id = 'f1111111-1111-4111-8111-111111111111';
  raise exception 'physical delete was allowed';
exception
  when insufficient_privilege then
    null;
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
  insert into public.user_notes (
    id, user_id, issue_id, paragraph_index, start_utf16, length_utf16, quote, body, updated_at
  ) values (
    'f2222222-2222-4222-8222-222222222222',
    '11111111-1111-4111-8111-111111111111',
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    1, 2, 3, 'quote', 'hello', '2026-10-11 01:00:00+00'
  );

  update public.user_notes
  set body = 'hello 2', updated_at = '2026-10-11 02:00:00+00'
  where id = 'f2222222-2222-4222-8222-222222222222';
  get diagnostics changed = row_count;
  if changed <> 1 then
    raise exception 'A should update own note, rows %', changed;
  end if;

  update public.user_notes
  set deleted_at = '2026-10-11 03:00:00+00', updated_at = '2026-10-11 03:00:00+00'
  where id = 'f2222222-2222-4222-8222-222222222222';
  get diagnostics changed = row_count;
  if changed <> 1 then
    raise exception 'A should tombstone own note, rows %', changed;
  end if;

  update public.user_notes set body = 'nope' where id = 'f1111111-1111-4111-8111-111111111111';
  get diagnostics changed = row_count;
  if changed <> 0 then
    raise exception 'A updated B note, rows %', changed;
  end if;

  select count(*) into n from public.user_notes;
  if n <> 1 then
    raise exception 'A should see only own note, saw %', n;
  end if;

  begin
    delete from public.user_notes where id = 'f2222222-2222-4222-8222-222222222222';
    raise exception 'A was allowed to delete a note';
  exception
    when insufficient_privilege then
      null;
  end;

  insert into public.reading_progress (user_id, issue_id, paragraph_index, updated_at)
  values (
    '11111111-1111-4111-8111-111111111111',
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    3,
    '2026-10-11 04:00:00+00'
  );
end $$;

rollback;

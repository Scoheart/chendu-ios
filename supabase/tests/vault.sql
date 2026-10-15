\set ON_ERROR_STOP on

begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
) values (
  '00000000-0000-0000-0000-000000000000',
  '11111111-1111-4111-8111-111111111111',
  'authenticated', 'authenticated', 'a@example.com',
  extensions.crypt('password', extensions.gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
  now(), now(), '', '', '', ''
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}',
  true
);

create temp table saved_key on commit drop as
select * from public.save_provider_key('openai', 'main', 'sk-test-secret-ABCD');

do $$
declare
  hint text;
  dumped text;
begin
  select key_hint into hint from saved_key;
  if hint <> 'ABCD' then
    raise exception 'expected hint ABCD, got %', hint;
  end if;

  select string_agg(t::text, ' ') into dumped from saved_key t;
  if dumped like '%sk-test-secret-ABCD%' then
    raise exception 'rpc result contains the secret';
  end if;

  select string_agg(t::text, ' ') into dumped from public.provider_keys_public t;
  if dumped like '%sk-test-secret-ABCD%' then
    raise exception 'public view contains the secret';
  end if;
  if dumped not like '%ABCD%' then
    raise exception 'public view is missing the hint';
  end if;

  begin
    perform * from public.provider_keys;
    raise exception 'authenticated read the provider_keys table';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform * from vault.decrypted_secrets;
    raise exception 'authenticated read vault.decrypted_secrets';
  exception
    when insufficient_privilege then
      null;
  end;
end $$;

reset role;

do $$
declare
  secret text;
begin
  select public.active_provider_secret(
    '11111111-1111-4111-8111-111111111111',
    'openai'
  ) into secret;
  if secret <> 'sk-test-secret-ABCD' then
    raise exception 'service role did not read the secret';
  end if;
end $$;

set local role authenticated;
select public.revoke_provider_key((select id from saved_key));
reset role;

do $$
declare
  secret text;
begin
  select public.active_provider_secret(
    '11111111-1111-4111-8111-111111111111',
    'openai'
  ) into secret;
  if secret is not null then
    raise exception 'revoked key is still readable';
  end if;
end $$;

rollback;

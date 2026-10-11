-- Provider keys point at Vault. Authenticated users never see the secret.

create table public.provider_keys (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  provider text not null,
  label text not null default '',
  key_hint text not null,
  vault_secret_id uuid not null,
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);

alter table public.provider_keys enable row level security;
revoke all on public.provider_keys from anon, authenticated;

create view public.provider_keys_public as
select id, user_id, provider, label, key_hint, is_default, created_at, revoked_at
from public.provider_keys
where user_id = (select auth.uid());

grant select on public.provider_keys_public to authenticated;

create function public.save_provider_key(p_provider text, p_label text, p_secret text)
returns table (
  id uuid,
  provider text,
  label text,
  key_hint text,
  is_default boolean,
  created_at timestamptz,
  revoked_at timestamptz
)
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  uid uuid := auth.uid();
  hint text;
  secret_id uuid;
  row_id uuid;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if p_secret is null or length(p_secret) < 8 then
    raise exception 'secret too short' using errcode = '22023';
  end if;
  hint := right(p_secret, 4);
  secret_id := vault.create_secret(
    p_secret,
    uid::text || '/' || p_provider || '/' || gen_random_uuid()::text,
    p_provider
  );
  update public.provider_keys
  set is_default = false
  where provider_keys.user_id = uid
    and provider_keys.provider = p_provider
    and provider_keys.revoked_at is null;

  insert into public.provider_keys (user_id, provider, label, key_hint, vault_secret_id, is_default)
  values (uid, p_provider, coalesce(p_label, ''), hint, secret_id, true)
  returning provider_keys.id into row_id;

  return query
  select k.id, k.provider, k.label, k.key_hint, k.is_default, k.created_at, k.revoked_at
  from public.provider_keys k
  where k.id = row_id;
end;
$$;

create function public.revoke_provider_key(p_key_id uuid)
returns void
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  uid uuid := auth.uid();
  secret_id uuid;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  select vault_secret_id into secret_id
  from public.provider_keys
  where id = p_key_id and user_id = uid and revoked_at is null;
  if secret_id is null then
    raise exception 'provider key not found' using errcode = '42501';
  end if;
  update public.provider_keys
  set revoked_at = now(), is_default = false
  where id = p_key_id;
  delete from vault.secrets where id = secret_id;
end;
$$;

-- Used by the worker with the service role. Not granted to clients.
create function public.active_provider_secret(p_user_id uuid, p_provider text)
returns text
language sql
security definer
set search_path = public, vault
as $$
  select v.decrypted_secret
  from public.provider_keys k
  join vault.decrypted_secrets v on v.id = k.vault_secret_id
  where k.user_id = p_user_id
    and k.provider = p_provider
    and k.revoked_at is null
    and k.is_default
  limit 1;
$$;

revoke all on function public.save_provider_key(text, text, text) from public, anon;
revoke all on function public.revoke_provider_key(uuid) from public, anon;
revoke all on function public.active_provider_secret(uuid, text) from public, anon, authenticated;
grant execute on function public.save_provider_key(text, text, text) to authenticated;
grant execute on function public.revoke_provider_key(uuid) to authenticated;

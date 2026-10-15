-- After the import script: A can read the three imported issues, B cannot.
\set ON_ERROR_STOP on

do $$
declare
  n int;
begin
  select count(*) into n from storage.objects
  where bucket_id = 'audio'
    and name like '11111111-1111-4111-8111-111111111111/%';
  if n <> 6 then
    raise exception 'expected 6 audio objects, saw %', n;
  end if;
end $$;

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}',
  true
);
do $$
declare
  n int;
begin
  select count(*) into n from public.articles;
  if n <> 0 then
    raise exception 'B read % articles', n;
  end if;
  select count(*) into n from public.issues;
  if n <> 0 then
    raise exception 'B read % issues', n;
  end if;
end $$;
rollback;

begin;
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
  dates text;
begin
  select count(*) into n from public.articles where length(raw_text) > 0;
  if n <> 3 then
    raise exception 'A raw_text count %', n;
  end if;
  select string_agg(issue_date::text, ',' order by issue_date desc) into dates from public.issues;
  if dates <> '2026-10-11,2026-10-10,2026-10-09' then
    raise exception 'dates %', dates;
  end if;
  select count(*) into n from public.issues where config_snapshot ->> 'origin' = 'import';
  if n <> 3 then
    raise exception 'origin %', n;
  end if;
end $$;
rollback;

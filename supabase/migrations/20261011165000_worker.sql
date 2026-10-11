-- Claim, commit, and fail generation jobs. Service role only.
-- The snapshot copied onto an issue is the one already stored on the job.

create function public.claim_next_job(p_worker text)
returns setof public.jobs
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with next_job as (
    select jobs.id
    from public.jobs
    where jobs.status = 'queued'
      and jobs.run_at <= now()
    order by jobs.run_at, jobs.created_at
    for update skip locked
    limit 1
  )
  update public.jobs
  set status = 'running',
      attempts = jobs.attempts + 1,
      locked_at = now(),
      locked_by = p_worker
  from next_job
  where jobs.id = next_job.id
  returning jobs.*;
end;
$$;

create function public.fail_job(p_job_id uuid, p_error text, p_stop boolean)
returns setof public.jobs
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.jobs%rowtype;
  v_error text;
  v_wait integer;
begin
  select * into v_job from public.jobs where id = p_job_id for update;
  if not found then
    raise exception 'job not found';
  end if;

  v_error := left(regexp_replace(coalesce(p_error, 'failed'), 'sk-[A-Za-z0-9_-]{8,}', 'sk-***', 'g'), 1000);
  v_error := regexp_replace(v_error, 'xai-[A-Za-z0-9_-]{8,}', 'xai-***', 'g');

  if p_stop or v_job.attempts >= v_job.max_attempts then
    return query
    update public.jobs
    set status = 'failed',
        last_error = v_error,
        finished_at = now(),
        locked_at = null,
        locked_by = null
    where id = p_job_id
    returning *;
    return;
  end if;

  v_wait := (array[2, 10, 30])[least(greatest(v_job.attempts, 1), 3)];
  return query
  update public.jobs
  set status = 'queued',
      run_at = now() + make_interval(mins => v_wait),
      last_error = v_error,
      locked_at = null,
      locked_by = null
  where id = p_job_id
  returning *;
end;
$$;

create function public.commit_generated_issue(p_job_id uuid, p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.jobs%rowtype;
  v_article_id uuid;
  v_issue_id uuid;
  v_tz text;
begin
  select * into v_job from public.jobs where id = p_job_id for update;
  if not found then
    raise exception 'job not found';
  end if;
  if v_job.status <> 'running' then
    raise exception 'job is not running';
  end if;

  select user_settings.timezone into v_tz
  from public.user_settings
  where user_id = v_job.user_id;
  v_tz := coalesce(v_tz, 'UTC');

  if exists (
    select 1
    from public.jobs other
    where other.user_id = v_job.user_id
      and other.kind = 'generate_issue'
      and other.status = 'succeeded'
      and other.id <> v_job.id
      and (other.finished_at at time zone v_tz)::date = (now() at time zone v_tz)::date
  ) then
    raise exception 'already generated today';
  end if;

  insert into public.articles (
    user_id, source_id, external_url, title, author, published_at,
    raw_text, excerpt, word_count, content_hash, license_snapshot
  ) values (
    v_job.user_id,
    nullif(p_payload #>> '{article,source_id}', '')::uuid,
    p_payload #>> '{article,external_url}',
    nullif(p_payload #>> '{article,title}', ''),
    nullif(p_payload #>> '{article,author}', ''),
    nullif(p_payload #>> '{article,published_at}', '')::timestamptz,
    coalesce(p_payload #>> '{article,raw_text}', ''),
    coalesce(p_payload #>> '{article,excerpt}', ''),
    coalesce(nullif(p_payload #>> '{article,word_count}', '')::integer, 0),
    p_payload #>> '{article,content_hash}',
    coalesce(nullif(p_payload #>> '{article,license_snapshot}', ''), 'all-rights-reserved')
  )
  returning id into v_article_id;

  v_issue_id := coalesce(nullif(p_payload ->> 'issue_id', '')::uuid, gen_random_uuid());

  insert into public.issues (
    id, user_id, article_id, issue_date, topic, topic_label, title, zh_title,
    byline, lead, blocks, credit, podcast, status, config_snapshot
  ) values (
    v_issue_id,
    v_job.user_id,
    v_article_id,
    (p_payload #>> '{issue,issue_date}')::date,
    nullif(p_payload #>> '{issue,topic}', ''),
    nullif(p_payload #>> '{issue,topic_label}', ''),
    p_payload #>> '{issue,title}',
    coalesce(p_payload #>> '{issue,zh_title}', ''),
    coalesce(p_payload #>> '{issue,byline}', ''),
    coalesce(p_payload #>> '{issue,lead}', ''),
    coalesce(p_payload #> '{issue,blocks}', '[]'::jsonb),
    p_payload #> '{issue,credit}',
    case
      when jsonb_typeof(p_payload #> '{issue,podcast}') = 'null' then null
      else p_payload #> '{issue,podcast}'
    end,
    'ready',
    v_job.config_snapshot
  );

  insert into public.annotations (
    issue_id, n, kind, tag, head, body, paragraph_index, start_utf16, length_utf16
  )
  select
    v_issue_id,
    (item ->> 'n')::integer,
    item ->> 'kind',
    coalesce(item ->> 'tag', ''),
    item ->> 'head',
    item ->> 'body',
    nullif(item ->> 'paragraph_index', '')::integer,
    nullif(item ->> 'start_utf16', '')::integer,
    nullif(item ->> 'length_utf16', '')::integer
  from jsonb_array_elements(coalesce(p_payload -> 'annotations', '[]'::jsonb)) item;

  insert into public.vocab (issue_id, position, word, ipa, meaning, example)
  select
    v_issue_id,
    ordinality::integer,
    item ->> 'word',
    coalesce(item ->> 'ipa', ''),
    item ->> 'meaning',
    coalesce(item ->> 'example', '')
  from jsonb_array_elements(coalesce(p_payload -> 'vocab', '[]'::jsonb)) with ordinality as list(item, ordinality);

  insert into public.patterns (
    issue_id, position, pattern, pattern_zh, source_sentence, model_sentence, model_zh
  )
  select
    v_issue_id,
    ordinality::integer,
    item ->> 'pattern',
    coalesce(item ->> 'pattern_zh', ''),
    coalesce(item ->> 'source', ''),
    coalesce(item ->> 'model', ''),
    coalesce(item ->> 'model_zh', '')
  from jsonb_array_elements(coalesce(p_payload -> 'patterns', '[]'::jsonb)) with ordinality as list(item, ordinality);

  insert into public.audio_assets (issue_id, kind, storage_path, voice, byte_size)
  select
    v_issue_id,
    item ->> 'kind',
    item ->> 'storage_path',
    nullif(item ->> 'voice', ''),
    nullif(item ->> 'byte_size', '')::integer
  from jsonb_array_elements(coalesce(p_payload -> 'audio', '[]'::jsonb)) item;

  update public.jobs
  set status = 'succeeded',
      issue_id = v_issue_id,
      provider = coalesce(nullif(p_payload #>> '{usage,provider}', ''), jobs.provider),
      model = coalesce(nullif(p_payload #>> '{usage,model}', ''), jobs.model),
      input_tokens = coalesce(nullif(p_payload #>> '{usage,input_tokens}', '')::integer, 0),
      output_tokens = coalesce(nullif(p_payload #>> '{usage,output_tokens}', '')::integer, 0),
      audio_chars = coalesce(nullif(p_payload #>> '{usage,audio_chars}', '')::integer, 0),
      cost_usd = coalesce(nullif(p_payload #>> '{usage,cost_usd}', '')::numeric, 0),
      finished_at = now(),
      locked_at = null,
      locked_by = null,
      last_error = null
  where id = p_job_id;

  return v_issue_id;
end;
$$;

revoke all on function public.claim_next_job(text) from public, anon, authenticated;
revoke all on function public.fail_job(uuid, text, boolean) from public, anon, authenticated;
revoke all on function public.commit_generated_issue(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.claim_next_job(text) to service_role;
grant execute on function public.fail_job(uuid, text, boolean) to service_role;
grant execute on function public.commit_generated_issue(uuid, jsonb) to service_role;

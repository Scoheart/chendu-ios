-- Sources, issues, jobs, and prompt templates.
-- Generated rows are written by the service role. Authenticated users
-- can read their own, and can manage only their own sources and templates.

create table public.sources (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references auth.users (id) on delete cascade,
  kind text not null check (kind in ('rss', 'url', 'curated')),
  title text not null,
  url text not null,
  topic text check (topic in ('stocks', 'ai', 'general')),
  license text not null default 'all-rights-reserved',
  config jsonb not null default '{}'::jsonb,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  check (
    (kind = 'curated' and owner_id is null)
    or (kind in ('rss', 'url') and owner_id is not null)
  )
);

create table public.subscriptions (
  user_id uuid not null references auth.users (id) on delete cascade,
  source_id uuid not null references public.sources (id) on delete cascade,
  enabled boolean not null default true,
  priority integer not null default 0,
  created_at timestamptz not null default now(),
  primary key (user_id, source_id)
);

create table public.articles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  source_id uuid references public.sources (id),
  external_url text not null,
  title text,
  author text,
  published_at timestamptz,
  raw_text text not null default '',
  excerpt text not null default '',
  word_count integer not null default 0,
  content_hash text not null,
  license_snapshot text not null,
  fetched_at timestamptz not null default now(),
  unique (user_id, content_hash)
);

create table public.issues (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  article_id uuid references public.articles (id),
  issue_date date not null,
  topic text,
  topic_label text,
  title text not null,
  zh_title text not null default '',
  byline text not null default '',
  lead text not null default '',
  blocks jsonb not null default '[]'::jsonb,
  credit jsonb,
  podcast jsonb,
  status text not null default 'ready' check (status in ('ready', 'failed')),
  config_snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (user_id, issue_date)
);

create table public.annotations (
  id uuid primary key default gen_random_uuid(),
  issue_id uuid not null references public.issues (id) on delete cascade,
  n integer not null,
  kind text not null check (kind in ('vocab', 'grammar', 'idiom')),
  tag text not null default '',
  head text not null,
  body text not null,
  paragraph_index integer,
  start_utf16 integer,
  length_utf16 integer,
  unique (issue_id, n)
);

create table public.vocab (
  id uuid primary key default gen_random_uuid(),
  issue_id uuid not null references public.issues (id) on delete cascade,
  position integer not null,
  word text not null,
  ipa text not null default '',
  meaning text not null,
  example text not null default '',
  unique (issue_id, position)
);

create table public.patterns (
  id uuid primary key default gen_random_uuid(),
  issue_id uuid not null references public.issues (id) on delete cascade,
  position integer not null,
  pattern text not null,
  pattern_zh text not null default '',
  source_sentence text not null default '',
  model_sentence text not null default '',
  model_zh text not null default '',
  unique (issue_id, position)
);

create table public.audio_assets (
  id uuid primary key default gen_random_uuid(),
  issue_id uuid not null references public.issues (id) on delete cascade,
  kind text not null check (kind in ('normal', 'slow')),
  storage_path text not null,
  duration_sec numeric,
  voice text,
  byte_size integer,
  unique (issue_id, kind)
);

create table public.jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null default 'generate_issue',
  status text not null default 'queued' check (status in ('queued', 'running', 'succeeded', 'failed', 'cancelled')),
  run_at timestamptz not null default now(),
  attempts integer not null default 0,
  max_attempts integer not null default 3,
  locked_at timestamptz,
  locked_by text,
  last_error text,
  provider text,
  model text,
  config_snapshot jsonb not null default '{}'::jsonb,
  input_tokens integer,
  output_tokens integer,
  audio_chars integer,
  cost_usd numeric,
  issue_id uuid references public.issues (id),
  created_at timestamptz not null default now(),
  finished_at timestamptz
);

create table public.prompt_templates (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references auth.users (id) on delete cascade,
  task text not null check (task in ('select', 'annotate', 'vocab', 'patterns')),
  version integer not null check (version >= 1),
  body text not null,
  based_on_id uuid references public.prompt_templates (id),
  based_on_version integer,
  created_at timestamptz not null default now()
);

create unique index prompt_templates_platform_version
  on public.prompt_templates (task, version)
  where owner_id is null;

create unique index prompt_templates_one_per_user_task
  on public.prompt_templates (owner_id, task)
  where owner_id is not null;

alter table public.sources enable row level security;
alter table public.subscriptions enable row level security;
alter table public.articles enable row level security;
alter table public.issues enable row level security;
alter table public.annotations enable row level security;
alter table public.vocab enable row level security;
alter table public.patterns enable row level security;
alter table public.audio_assets enable row level security;
alter table public.jobs enable row level security;
alter table public.prompt_templates enable row level security;

grant select, insert, update, delete on public.sources to authenticated;
grant select, insert, update, delete on public.subscriptions to authenticated;
grant select on public.articles to authenticated;
grant select on public.issues to authenticated;
grant select on public.annotations to authenticated;
grant select on public.vocab to authenticated;
grant select on public.patterns to authenticated;
grant select on public.audio_assets to authenticated;
grant select on public.jobs to authenticated;
grant select, insert, update, delete on public.prompt_templates to authenticated;

create policy sources_select on public.sources
  for select to authenticated
  using (owner_id is null or owner_id = (select auth.uid()));

create policy sources_insert on public.sources
  for insert to authenticated
  with check (owner_id = (select auth.uid()) and kind in ('rss', 'url'));

create policy sources_update on public.sources
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create policy sources_delete on public.sources
  for delete to authenticated
  using (owner_id = (select auth.uid()));

create policy subscriptions_all on public.subscriptions
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.sources s
      where s.id = source_id
        and (s.owner_id is null or s.owner_id = (select auth.uid()))
    )
  );

create policy articles_select on public.articles
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy issues_select on public.issues
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy annotations_select on public.annotations
  for select to authenticated
  using (
    exists (
      select 1 from public.issues i
      where i.id = issue_id and i.user_id = (select auth.uid())
    )
  );

create policy vocab_select on public.vocab
  for select to authenticated
  using (
    exists (
      select 1 from public.issues i
      where i.id = issue_id and i.user_id = (select auth.uid())
    )
  );

create policy patterns_select on public.patterns
  for select to authenticated
  using (
    exists (
      select 1 from public.issues i
      where i.id = issue_id and i.user_id = (select auth.uid())
    )
  );

create policy audio_select on public.audio_assets
  for select to authenticated
  using (
    exists (
      select 1 from public.issues i
      where i.id = issue_id and i.user_id = (select auth.uid())
    )
  );

create policy jobs_select on public.jobs
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy prompts_select on public.prompt_templates
  for select to authenticated
  using (owner_id is null or owner_id = (select auth.uid()));

create policy prompts_insert on public.prompt_templates
  for insert to authenticated
  with check (owner_id = (select auth.uid()));

create policy prompts_update on public.prompt_templates
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create policy prompts_delete on public.prompt_templates
  for delete to authenticated
  using (owner_id = (select auth.uid()));

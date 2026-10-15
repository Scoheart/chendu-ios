# supabase

本地 Supabase。`config.toml` 来自 `supabase init`。迁移在 `migrations/`。

身份表（profiles、user_settings、generation_profiles）在 `20261011160000_identity.sql`。注册触发器同时插入三行。`tasks` 默认是空对象。

```bash
supabase start
supabase/tests/run_identity.sh
```

不要把 service role 写进仓库。

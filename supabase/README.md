# supabase

本地 Supabase。`config.toml` 来自 `supabase init`。迁移在 `migrations/`。

身份表在 `20261011160000_identity.sql`。内容、期次、job 和平台 prompt 在 `20261011161000_content.sql`，模板正文由 `seed.sql` 从 `packages/prompts` 写入 version 1。

```bash
supabase start
supabase/tests/run_identity.sh
supabase/tests/run_worker.sh
supabase/tests/run_schedule.sh
```

`run_worker.sh` 用夹具 RSS 和假模型跑领取、入库、坏 JSON 重试，以及 401 停止。TTS 在没有 key 时记为 skipped。

不要把 service role 写进仓库。

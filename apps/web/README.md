# apps/web

登录后的阅读器。Vite + React，直接连 Supabase，没有 BFF。

未登录只看到登录页。登录后可以看往期、点开批注、用 signed URL 播放音频、写笔记、改学习设置，以及看本月 `jobs.cost_usd` 合计。笔记的 `id` 和 `updated_at` 由浏览器生成，服务端不改写。

```bash
npm install
npm test
VITE_SUPABASE_URL=http://127.0.0.1:54321 VITE_SUPABASE_ANON_KEY=<anon key> npm run dev
```

anon key 用 `supabase status -o env` 里的 `ANON_KEY`。不要把 service role 放进环境变量或这个目录。

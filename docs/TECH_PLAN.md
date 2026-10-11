# 晨读技术实施计划

按 [ARCHITECTURE.md](./ARCHITECTURE.md) 把流水线拆成可独立合并、可独立验收的步骤。本文不改代码。工作量只用 S / M / L：一个模块、跨几个模块、跨客户端。不排日历。

## 本计划锁定的实现选择

架构第 13 节里还开着的问题，下面先定死，避免步骤互相等待。其余仍按架构。第 12 节的分阶段兜底不再执行：iOS 和 Web 只有 Supabase 一条数据路径，没有静态站回退，也没有过渡期。现有 Vercel 站保持原样，本计划不改它、不部署、也不接管它的每日发布。

| 选择 | 决定 |
|---|---|
| 仓库 | 继续用本仓库，不新建 monorepo。iOS 留在 `Chendu/`，等数据层换完再考虑搬到 `apps/ios`（不在本计划内）。 |
| Web | 新目录 `apps/web`：Vite + React + `supabase-js`。无 BFF。密钥和 service role 不进这个包。单独的 Vercel 项目。现有静态站不动。 |
| 生成进程 | 抓取、模型、TTS 跑在 `packages/pipeline` 的 worker CLI 里。Edge Function 只做入队和领取调度，不在里面合成音频。 |
| 登录 | v1 同时做 Sign in with Apple 和邮箱 magic link。密码登录不做。 |
| 数据路径 | 只有 Supabase。iOS 不解析静态站 HTML，不读 `issues.json`，不保留双路径。未登录只显示登录。 |

## 仓库布局（Step 1 落地）

```
Chendu/                  iOS，暂不搬
apps/web/                登录后的阅读器与设置
supabase/                config.toml、migrations/、functions/run-jobs/、seed.sql
packages/prompts/        select|annotate|vocab|patterns 的默认模板（git 为源）
packages/pipeline/       Deno：fetch、extract、llm、tts、job runner、价目表
docs/
```

`packages/prompts` 是模板正文的源。迁移用 seed 写入 `prompt_templates`（`owner_id` 为空，`version` 从 1 起）。改模板 = 改文件 + 新的 seed 版本，不覆盖用户已复制的行。

iOS、Web 只通过 PostgREST、RPC 和 Storage signed URL 访问。类型用 Supabase CLI 生成到 `packages/pipeline/database.types.ts`，iOS 手写映射到现有 `Issue` / `UserNote`，不共享 Swift/TS 模型。

## 你需要亲自做的事（汇总）

| 何时 | 做什么 |
|---|---|
| Step 1 | 无 |
| Step 2 起本地 | 本机 Docker，能跑 `supabase start` |
| Step 6 | 在 supabase.com 建项目；Auth 里打开 Apple 和 Email。Apple：Services ID、Sign in with Apple key（.p8）、Team ID、Bundle ID `com.scoheart.chendu`。把 key 配进 Supabase，不要发给别人、不要进 Git |
| Step 12 的真网测试 | 一把你自己的模型 key，只放本地环境变量 |
| Step 13 | 决定 worker 跑在哪。个人阶段可以是这台 Mac 的 launchd；要离开本机再给一台机器或托管进程 |
| Step 14 | Xcode 里给 Chendu target 加 Sign in with Apple。付费 Team 仍用 `com.scoheart.chendu`；免费 Personal Team 继续用 `com.scoheart.chendu.dev`，Supabase 的 Apple Services ID 要包含实际安装的 bundle id |
| Step 18 | 新建 Vercel 项目，只填 `SUPABASE_URL` 和 anon key |

service role、Vault 解密、cron 密钥只放 worker / Edge 的环境，不进 iOS，不进 `apps/web`。

## 步骤

每步一个 PR。验收不过不开始依赖它的下一步。

### Step 1 — 仓库骨架与默认 prompt

- **目标**：目录和模板就位，iOS 行为不变。
- **交付**：上表五个目录；`packages/prompts` 四个模板文件加占位符说明；`packages/pipeline` 的 `deno.json` 和一个空测试；根 README 加一段目录说明。
- **依赖**：无。
- **验收**：`deno test` 通过；`Chendu.xcodeproj` 仍能编过（不改 Swift）。
- **工作量**：S。
- **你要做的**：无。

### Step 2 — 本地 Supabase：身份与设置

- **目标**：注册即有 profile、设置和一份 active 的 generation profile。
- **交付**：`supabase init`；迁移含 `profiles`、`user_settings`、`generation_profiles`、`auth.users` 触发器、RLS；默认值与架构第 2 节一致。
- **依赖**：Step 1。
- **验收**：`supabase db reset` 后，用两个测试用户断言：各自只能读改自己的行；新用户三行都在；`tasks` 为空。
- **工作量**：M。
- **你要做的**：安装 Docker，本地 `supabase start`。

### Step 3 — 内容、期次、job、模板表

- **目标**：架构第 6 节除笔记外的表可迁移、可隔离。
- **交付**：`sources`、`subscriptions`、`articles`、`issues`（含 `config_snapshot`）、`annotations`、`vocab`、`patterns`、`audio_assets`、`jobs`、`prompt_templates`；seed 从 `packages/prompts` 写入 version 1；RLS 与架构第 7 节一致（生成结果表不对 `authenticated` 开放 insert）。
- **依赖**：Step 2。
- **验收**：用户 A 看不到 B 的 issue；A 不能 insert issue；A 能 insert 自己的 source，不能改 `owner_id is null` 的精选源；平台模板可读、不可 update。
- **工作量**：M。
- **你要做的**：无。

### Step 4 — 笔记与阅读进度

- **目标**：离线笔记能原样落表。
- **交付**：`user_notes`（客户端 uuid、墓碑 `deleted_at`）、`reading_progress`、RLS。禁止物理 delete。
- **依赖**：Step 3。
- **验收**：A 插入、更新、写墓碑成功；A 对 B 的行失败；delete SQL 被拒。
- **工作量**：S。
- **你要做的**：无。

### Step 5 — BYOK：Vault 与 RPC

- **目标**：明文 key 只在写入瞬间和 worker 里出现。
- **交付**：`provider_keys`、视图 `provider_keys_public`（无 `vault_secret_id`）；`save_provider_key`、`revoke_provider_key`（`security definer`）；表不对 `authenticated` 授权。
- **依赖**：Step 2。可与 Step 3、4 并行。
- **验收**：RPC 后视图有 `key_hint`、没有 secret；以用户 JWT 查 `vault.decrypted_secrets` 失败；service role 能读到该 secret；revoke 后 worker 用的查询返回空；日志夹具里一条带 key 的错误被打成 `sk-***`。
- **工作量**：M。
- **你要做的**：无（本地 Vault）。托管项目在 Step 6 确认 Vault 扩展已开。

### Step 6 — 托管项目与 Auth

- **目标**：云端库等于本地迁移；Apple 和 magic link 能登录。
- **交付**：`supabase link` 的说明写进 README；迁移应用到远程；Auth 重定向 URL 含 iOS scheme 和 web 本地端口。
- **依赖**：Step 2–5。
- **验收**：远程 `db diff` 为空；Apple 与邮箱各登入一次，`profiles` 有行。anon key 做 Step 3 的越权请求仍失败。
- **工作量**：S（代码）+ 你的控制台操作。
- **你要做的**：见汇总表。不要把 service role 写进仓库。

### Step 7 — 音频桶

- **目标**：mp3 私有，按用户路径隔离。
- **交付**：桶 `audio`，路径 `audio/{user_id}/{issue_id}/{kind}.mp3`；select 政策要求第一段等于 `auth.uid()`；insert/update 仅 service role。
- **依赖**：Step 6（本地可先于 Step 6 用 `supabase start` 验）。
- **验收**：service role 上传；所有者 signed URL 可下；另一用户对同一路径失败。
- **工作量**：S。
- **你要做的**：无。

### Step 8 — LLM provider 抽象

- **目标**：选文/批注不绑死一家。
- **交付**：`packages/pipeline/llm.ts`：`complete({provider, model, apiKey, schema, prompt})`，实现 OpenAI、Anthropic、xAI 的 chat 接口；统一 token 用量；`pricing.ts` 估算 `cost_usd`；错误脱敏。
- **依赖**：Step 1。
- **验收**：三家各一个录好的 HTTP 夹具测试，不访问外网；schema 不符时返回可重试错误；响应里的 key 不出现在抛出的 Error 里。
- **工作量**：M。
- **你要做的**：无。

### Step 9 — 抓取、抽取、节选

- **目标**：RSS / URL → 纯文本节选，遵守词数上限。
- **交付**：`fetch.ts`、`extract.ts`、`excerpt.ts`。`excerpt_words` 与源 license 上限取 min（保留版权 500，CC / public-domain 用源上配置的更大上限）。
- **依赖**：Step 1。
- **验收**：用存盘的 RSS 和 HTML 夹具：抽出发文日期、标题、链接；超长正文被截到词数；同一正文 `content_hash` 稳定。
- **工作量**：M。
- **你要做的**：无。

### Step 10 — 选文与批注（夹具）

- **目标**：pipeline 后半段在假模型下产出与现有 `Issue` 同形的 JSON。
- **交付**：`renderPrompt`、`select`、`annotate`；JSON schema 覆盖 blocks、annotations、vocab、patterns；失败可区分「该重试」和「该停」。
- **依赖**：Step 8、9，以及 Step 3 的模板正文。
- **验收**：假 LLM 返回合法 JSON 时得到一期对象；缺字段时判为可重试；`learner_level`、`explanation_lang`、深度、词条数出现在渲染后的 prompt 里。
- **工作量**：M。
- **你要做的**：无。

### Step 11 — TTS provider 抽象

- **目标**：声音和供应商可换，慢速是另一次合成而不是客户端变速。
- **交付**：`tts.ts`：`synthesize({provider, model, voice, text}) -> mp3 bytes`。v1 实现一家（OpenAI audio）；接口留第二家。`slow: true` 时用更慢的 speed 或第二段请求，写成 `kind=slow`。
- **依赖**：Step 8 的错误脱敏方式。
- **验收**：夹具返回固定字节；缺 key 时返回明确的 `skipped`，不抛到整期失败。真网试听放到 Step 12。
- **工作量**：M。
- **你要做的**：无。

### Step 12 — Job worker：排队、重试、费用、快照

- **目标**：本地一条命令跑完「领取 → 抓取 → 选文 → 批注 → TTS → 入库」。
- **交付**：`packages/pipeline/worker.ts`。领取用 `for update skip locked`。开始时把 profile、模板 id/version、模型、voice 写入 `jobs.config_snapshot`（无 key）。成功时同一事务写 article、issue、子表、`audio_assets`，并把同一 snapshot 抄到 issue。重试：2 / 10 / 30 分钟，最多 3 次；401/403 不重试并标 key 需重存。每天每用户最多一条成功 job。
- **依赖**：Step 3、4、5、7、10、11。
- **验收**：本地库里一个 RSS 夹具源 + 测试 key（或 TTS skipped）跑出 `status=ready` 的 issue；故意让模型返回坏 JSON，job 回到 `queued` 且 `attempts` 增加；改 profile 后再读该 issue，snapshot 不变；`cost_usd` 与 token 列非空。日志只有 `job_id` 和步骤名。
- **工作量**：L。
- **你要做的**：真网试跑时提供一把模型 key，放在本地环境变量。

### Step 13 — 调度与 worker 进程

- **目标**：到点自动入队；生成不靠 Edge 的时限。
- **交付**：迁移启用 `pg_cron`（或 Supabase scheduled function）每分钟调用只做入队的 `run-jobs`；入队条件是用户时区的 `delivery_time`，错过则当天补入队。worker CLI 单独轮询 `running` 领取。README 写 launchd 示例。推送只在 `push_enabled` 且 job 成功时发（v1 用一条 `pg_net` 或记录「待推送」，APNs 可后补，验收先看 jobs 行上的标志）。
- **依赖**：Step 6、12。
- **验收**：把某测试用户的 `delivery_time` 设成下一分钟，不手工 `enqueue_issue`，出现一条 `queued` job，worker 把它跑完。Edge 日志里没有 mp3 体积的请求。
- **工作量**：M。
- **你要做的**：指定 worker 跑在哪，并在那台机器上配置 service role 环境变量。

### Step 14 — iOS 登录

- **目标**：App 只有登录后的 Supabase session。未登录只显示登录，不读任何公开站点。
- **交付**：`Chendu/Auth/`（Apple + magic link）；session 存 Keychain。根界面在无 session 时只渲染登录页。
- **依赖**：Step 6。与 Step 12 并行。
- **验收**：模拟器 magic link（Inbucket）登入；真机 Apple 登入后 `profiles` 有行。退出后回到登录页，本地笔记仍在。工程里不再有读取 `chendu-english.vercel.app` 或解析 HTML 的运行路径。
- **工作量**：M。
- **你要做的**：Xcode capability 与 Apple Services ID（见汇总表）。

### Step 15 — iOS 数据层只读 Supabase

- **目标**：阅读器 UI 不变，`Issue` 只来自 Supabase。
- **交付**：删除 `SiteParser`、HTML 解析、`issues.json` 和静态站 URL。`Issue` 映射 issues 及嵌套 annotations / vocab / patterns / audio；列表按 `issue_date desc`；音频 signed URL 进离线缓存。
- **依赖**：Step 7、14。有一条 Step 12 产生的期最好，没有也能用夹具行。
- **验收**：测试账号能打开云端一期、点开批注、播放或下载 mp3。断网时打开已缓存的那期。未登录只看到登录页。仓库里没有第二套期次来源。
- **工作量**：L。
- **你要做的**：无。

### Step 16 — iOS 设置（架构第 2 节全部）

- **目标**：清单里每一项都能改，并写到对应的表或 RPC。
- **交付**：设置页分组：源与订阅、轮换与主题、按任务的 provider/模型/key/voice、深度与类型、CEFR、解释语言、节选词数、时区与推送时刻、复习词条数、主题与字体、同步开关。Key 只走 `save_provider_key`。Prompt 编辑 = 复制平台行再改自己的行；提供「恢复默认」。
- **依赖**：Step 5、14，以及 Step 3 的表。
- **验收**：改 `excerpt_words` 和 `learner_level` 后，下一轮 worker 的 `config_snapshot` 带新值；视图里看不到 secret；恢复默认后用户的 `prompt_templates` 行被删，再跑用平台 version。
- **工作量**：L。
- **你要做的**：无。

### Step 17 — 离线缓存与笔记同步

- **目标**：SwiftData 仍是第一存储；有网则按架构第 10 节同步。
- **交付**：推送 `updated_at` 更新的行和墓碑；拉取服务端更新；同一 id 后写覆盖；服务端不改客户端的 `updated_at`；脱离原文的锚点沿用现有 `quote` 回退。`reading_progress` 同样 LWW。`sync_notes = false` 时只留本地。
- **依赖**：Step 4、15。
- **验收**：飞机模式下写一条笔记，联网后另一客户端（SQL 或临时脚本）能读到；两端改同一 id，较新的 `updated_at` 留下；墓碑同步后另一端消失。导出 Markdown 仍可用。
- **工作量**：L。
- **你要做的**：无。

### Step 18 — Web 客户端

- **目标**：浏览器能完成和 iOS 相同的读、记、设置。不重做静态档案站。
- **交付**：`apps/web`：登录、往期、阅读器（点批注、播放 signed URL）、笔记、设置、费用（`jobs` 的 `cost_usd` 按月合计）。
- **依赖**：Step 6、12、16 的表和 RPC。可与 Step 15 并行。
- **验收**：同一账号在 web 改的笔记，iOS 同步后可见。构建产物里搜不到 service role。
- **工作量**：L。
- **你要做的**：建 Vercel 项目，只配 URL 和 anon key。

### Step 19 — 导入已有三期

- **目标**：把 2026-10-09 / 10 / 11 写进指定账号。没有过渡期，没有双路径，不改线上站，不停、也不接管每日发布。
- **交付**：一次性导入脚本。输入是这三期已经整理好的 JSON（或脚本内的同等夹具），输出是指定 `user_id` 下的 article、issue、批注和音频对象。`config_snapshot.origin = import`。音频写入该用户的 Storage 路径。脚本默认连本地库；不提供「继续读静态站」的开关。
- **依赖**：Step 12、15。
- **验收**：对本地库跑脚本后，该用户能读到这三期，顺序和批注与夹具一致；另一个用户读不到这些 `articles.raw_text`。脚本不访问、不写入 `chendu-english.vercel.app`，也不部署。
- **工作量**：M。
- **你要做的**：要导入线上库时，自己指定账号并在本地执行。本计划不代跑生产导入。

### Step 20 — CI、可观测、安全复查

- **目标**：以上验收变成自动的；日志和费用对得上。
- **交付**：GitHub Actions：`supabase db reset` + SQL 断言、`deno test`、iOS 单元测试（不跑必须真机的 UI 冒烟）。worker 日志字段固定为 `job_id`、`user_id`、`step`、`attempt`。CI 用密钥扫描拒绝 service role 出现在 `Chendu/` 和 `apps/web/`。
- **依赖**：Step 12、15。
- **验收**：故意把 service role 写进 iOS 文件时 CI 失败；一个失败 job 的 `last_error` 在仪表（先用 SQL）里能按 `job_id` 查到，且不含 key。
- **工作量**：M。
- **你要做的**：若仓库还没有 Actions 权限，打开它。

## 顺序

| 步 | 内容 | 依赖 | 量 |
|---|---|---|---|
| 1 | 仓库骨架、默认 prompt | — | S |
| 2 | 身份、user_settings、generation_profiles | 1 | M |
| 3 | 源、期次、job、模板表 | 2 | M |
| 4 | 笔记、阅读进度 | 3 | S |
| 5 | Vault 与 provider key RPC | 2 | M |
| 6 | 托管项目、Apple / 邮箱登录 | 2–5 | S |
| 7 | 私有音频桶 | 6 | S |
| 8 | LLM 抽象 | 1 | M |
| 9 | 抓取与节选 | 1 | M |
| 10 | 选文与批注 | 8、9 | M |
| 11 | TTS 抽象 | 8 | M |
| 12 | worker：队列、重试、费用、snapshot | 3–5、7、10、11 | L |
| 13 | cron 入队、worker 进程 | 6、12 | M |
| 14 | iOS 登录 | 6 | M |
| 15 | iOS 只读 Supabase | 7、14 | L |
| 16 | iOS 全部设置 | 5、14 | L |
| 17 | 离线与笔记同步 | 4、15 | L |
| 18 | Web | 6、12 | L |
| 19 | 导入已有三期到指定账号 | 12、15 | M |
| 20 | CI、日志、密钥扫描 | 12、15 | M |

可并行：5 与 3；8 和 9 与 2–4；14 与 12；18 与 15。

## 从 Step 1 开始

先做 Step 1，不要先建云项目。它不需要账号，也不改 App 行为，并且把 prompt 和 pipeline 的位置定下来，后面的迁移和 worker 都往这两个目录里加。

你这边唯一值得提前准备、但不阻塞 Step 1 的，是 Step 6 的 Supabase 项目和 Sign in with Apple 的 Services ID。等 Step 5 的本地验收过了再配到云端。

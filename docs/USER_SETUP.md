# 需要你做的事

本地迁移和测试不需要账号。下面这些会碰到控制台或密钥，只能由你做。不要把 service role、`.p8`、模型 key 发进 Git，也不要发给别人。

本文件不代替操作。仓库里没有托管项目的链接，也没有对 `chendu-english.vercel.app` 或任何 Vercel 项目做过部署。

## 托管 Supabase（Step 6）

1. 在 [supabase.com](https://supabase.com) 新建一个项目。不要复用别的产品的项目。
2. Authentication → Providers：打开 **Email**（magic link，不要密码）和 **Apple**。
3. Apple Developer 里准备：
   - Services ID（Sign in with Apple）
   - Sign in with Apple key，下载 `.p8`，记下 Key ID
   - Team ID
   - Bundle ID：付费 Team 用 `com.scoheart.chendu`；这台机器上免费 Personal Team 安装的是 `com.scoheart.chendu.dev`。Supabase 的 Apple 配置要包含**实际安装的那个** bundle id。
4. 把 Services ID、Team ID、Key ID、`.p8` 填进 Supabase 的 Apple provider。`.p8` 只留在你自己的机器。
5. Authentication → URL Configuration，Redirect URLs 加上：
   - `chendu://auth-callback`（iOS）
   - `http://127.0.0.1:5173`（本地 web）
6. 确认项目里 Vault 扩展是开的（Database → Extensions → `supabase_vault`）。
7. 在本机、这个仓库里执行（会要你登录 Supabase CLI，自己来）：

```bash
supabase link --project-ref <你的 project ref>
supabase db push
supabase db diff
```

`db diff` 应为空。用 Apple 和邮箱各登入一次，`profiles` 里各有一行。用 anon key 去插入别人的 `issues` 必须失败。

service role 只放 worker 的环境变量。`supabase status` 打出来的本地 demo key 不是云端的 key。

## 模型 key（Step 12 真网试跑）

要打到真实模型时，把 key 放在本机环境变量，例如 `OPENAI_API_KEY`。不要写进仓库、不要写进 iOS、不要写进 `apps/web`。不试真网时，worker 用夹具，TTS 可以是 `skipped`。

## Worker 放哪（Step 13）

个人阶段用这台 Mac 的 launchd 即可。离开本机再给一台机器。那台机器上配置 service role 和 `SUPABASE_URL`。Edge Function 只入队，不合成 mp3。

## Xcode（Step 14）

给 Chendu target 加上 Sign in with Apple capability。付费 Team 继续 `com.scoheart.chendu`。免费 Personal Team 继续 `com.scoheart.chendu.dev`，不要为了免费签名去注册主 bundle id。

模拟器登录用本地 magic link，不需要 Apple：

```bash
SUPABASE_URL=http://127.0.0.1:54321 SUPABASE_ANON_KEY=<anon key> scripts/magic_link.sh you@example.com
```

anon key 用 `supabase status -o env` 里的 `ANON_KEY`。不要把 service role 放进 Xcode 或环境。验证码在 Inbucket：<http://127.0.0.1:54324>。App 的 scheme 里可以设 `SUPABASE_URL` 和 `SUPABASE_ANON_KEY`，只这两项。

真机 Apple 登录要等 capability 和 Services ID 配好之后你自己登一次。这一步没有在真机上重装。

## Web（Step 18）

本地先装依赖再开页面。anon key 用 `supabase status -o env` 里的 `ANON_KEY`。

```bash
cd apps/web
npm install
VITE_SUPABASE_URL=http://127.0.0.1:54321 VITE_SUPABASE_ANON_KEY=<anon key> npm run dev
```

`npm test` 会构建，并确认产物里没有 service role。不要设置 service role。

要给别人用浏览器时，新建一个 Vercel 项目，只填 `VITE_SUPABASE_URL` 和 `VITE_SUPABASE_ANON_KEY`。不要填 service role。不要改现在的静态站项目，也不要部署到 `chendu-english.vercel.app`。这一步没有创建或部署 Vercel 项目。

## 导入已有三期（Step 19）

脚本只对你指定的 `user_id` 写入。要导入云端库时你自己执行，并自己指定数据库。不会自动停掉每天的手写发布，也不会改线上站。

# 晨读 iOS

Native SwiftUI reader (iOS 17+) for 晨读, a daily English close-reading issue. Personal use; not for the App Store. Issues come from the signed-in user's Supabase project.

- **Issue list**: newest first, with topic tag and date. Pull down to refresh.
- **Reader**: tap a highlighted phrase to open its handwritten note under the paragraph, one note at a time. Also shows review words (🔊 reads them aloud with system TTS), sentence patterns to imitate, the podcast link and source credits.
- **Audio**: plays the issue's normal and slow mp3s with background playback, lock-screen and Control Center controls, ±15 s skip and 0.8×–1.5× speed.
- **My notes**: long-press to select article text, then pick **加笔记** in the edit menu. Notes are highlighted, editable and deletable, and stored on the device with SwiftData. The **我的笔记** tab lists notes from every issue, with copy, Markdown export and a jump back to the passage.
- **Offline**: every opened issue is cached. The ⬇︎ button saves an issue's audio too, and Settings can save the latest 7 issues. When the network is down, the app reads from the cache.
- **Reminder**: an optional daily notification at 8:00 Beijing time. With it on, iOS also gets a background-refresh request to pre-cache the newest issue.

## Data source

The only source is Supabase. The list is `issues` ordered by `issue_date` descending, with annotations, vocab, patterns, and audio rows. Audio is a signed URL from the private `audio` bucket, then saved in the offline cache. There is no HTML parser and no static-site feed.

## Run on your iPhone

The **Personal** build configuration signs with the free Personal Team (`L9PM656L4T`) and the bundle id `com.scoheart.chendu.dev`, so the main id stays free for the paid team. Debug and Release are unchanged: `com.scoheart.chendu`, no team baked in. A free-team install expires after 7 days, and a device can hold only three such apps.

```bash
xcodebuild -project Chendu.xcodeproj -scheme Chendu -configuration Personal \
  -destination 'id=<device-udid>' -allowProvisioningUpdates \
  -derivedDataPath build/device build
xcrun devicectl device install app --device <device-udid> \
  build/device/Build/Products/Personal-iphoneos/Chendu.app
xcrun devicectl device process launch --device <device-udid> com.scoheart.chendu.dev
```

With the paid team signed in to Xcode, use Debug or Release and `com.scoheart.chendu` instead; that install lasts about a year.

## Run from Xcode

1. Open `Chendu.xcodeproj` in Xcode.
2. Select the **Chendu** target, open **Signing & Capabilities**, and choose your paid team under **Team**. Signing is automatic and the bundle id is `com.scoheart.chendu`.
3. Connect the iPhone (or pair it over Wi-Fi), select it as the run destination, and press **Run** (⌘R).
4. On first install, enable Developer Mode on the iPhone if asked (Settings › Privacy & Security › Developer Mode).

Builds installed straight from Xcode with a paid team expire after about a year. TestFlight builds last 90 days and update in place; see below.

## TestFlight (internal testing)

```bash
TEAM_ID=XXXXXXXXXX scripts/testflight.sh            # archive (Release) + upload
TEAM_ID=XXXXXXXXXX scripts/testflight.sh --archive-only
```

The build number defaults to a UTC timestamp. Authentication uses an App Store Connect API key if `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_PATH` are all set; otherwise it uses the account signed in to Xcode. One-time setup before the first upload:

1. Sign in to Xcode › Settings › Accounts with the Apple ID that has the paid membership.
2. In App Store Connect, create the app (My Apps › + › New App) with bundle id `com.scoheart.chendu`. Register the identifier first under developer.apple.com › Identifiers if it doesn't appear in the list.
3. After the first build finishes processing, go to TestFlight › Internal Testing, create a group, add yourself, and install the build with the TestFlight app on the iPhone.

## What you still do by hand

Hosted Supabase, Sign in with Apple, provider keys, the worker host, and the new Vercel project are listed in [docs/USER_SETUP.md](docs/USER_SETUP.md). Those steps are not done from this repo automatically.

## Layout

```
Chendu/               iOS app（本步不改 Swift）
apps/web/             登录后的阅读器（Vite + React）
supabase/             本地 Postgres、Auth、Storage
packages/prompts/     select / annotate / vocab / patterns 的默认模板
packages/pipeline/    Deno worker：抓取、模型、TTS、job
docs/                 架构与实施计划
```

产品只有 Supabase 一条数据路径。未登录只显示登录页。

## Worker

`supabase/functions/run-jobs` only calls `enqueue_due`. Speech and the model run in the Deno worker, outside the edge function. On this Mac, launchd can poll once a minute:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.scoheart.chendu.worker</string>
  <key>WorkingDirectory</key><string>/Users/scoheart/Code/scoheart/chendu-ios</string>
  <key>ProgramArguments</key>
  <array>
    <string>/Users/scoheart/.deno/bin/deno</string>
    <string>run</string>
    <string>--allow-net</string>
    <string>--allow-env</string>
    <string>--allow-read</string>
    <string>packages/pipeline/worker.ts</string>
  </array>
  <key>StartInterval</key><integer>60</integer>
  <key>EnvironmentVariables</key>
  <dict>
    <key>SUPABASE_URL</key><string>http://127.0.0.1:54321</string>
    <key>SUPABASE_SERVICE_ROLE_KEY</key><string>set-this-outside-git</string>
    <key>OPENAI_API_KEY</key><string>set-this-outside-git</string>
  </dict>
</dict>
</plist>
```

Put the real keys in the plist on the machine, or in a file launchd reads that is not in git. Do not commit them.

## Develop

```bash
brew install xcodegen          # project.yml is the source of truth; Chendu.xcodeproj is generated
xcodegen generate
xcodebuild -project Chendu.xcodeproj -scheme Chendu -destination 'platform=iOS Simulator,name=iPhone 17' test
```

`ChenduUITests/SmokeTests` launches to the login screen and does not open a network connection. Set `SUPABASE_URL` and `SUPABASE_ANON_KEY` when you want a signed-in simulator session against the local stack.

To regenerate the app icon and lock-screen artwork: `swift scripts/make_icon.swift`.

## Credits

The wordmark and section headings use [Ma Shan Zheng](https://fonts.google.com/specimen/Ma+Shan+Zheng) (SIL Open Font License, `Chendu/Resources/Fonts/OFL-MaShanZheng.txt`). Everything that carries the article — notes, summaries, dates, labels — uses the system font, and the English article body uses the system serif. Article excerpts are © their publishers and used for personal study only.

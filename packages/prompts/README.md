# 默认 prompt

Git 是模板正文的源。`owner_id` 为空的平台行由后续迁移从这些文件 seed 进 `prompt_templates`，`version` 从 1 起。

改默认模板 = 改这里的文件并提高 seed 版本。已经复制到用户名下的行不被覆盖。

四个任务：`select`、`annotate`、`vocab`、`patterns`。TTS 不在这里，只走 `generation_profiles.tasks.tts`。

占位符由 worker 在开跑时替换，不在客户端填：

| 占位符 | 来源 |
|---|---|
| `{{title}}` `{{source_url}}` `{{topic}}` `{{excerpt}}` | 抓取结果 |
| `{{learner_level}}` `{{explanation_lang}}` `{{annotation_depth}}` `{{annotation_kinds}}` | generation profile |
| `{{excerpt_words}}` `{{vocab_count}}` `{{include_ipa}}` `{{pattern_count}}` | generation profile |

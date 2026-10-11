-- Platform prompt templates, version 1. Bodies come from packages/prompts.

insert into public.prompt_templates (owner_id, task, version, body)
values (null, 'select', 1, $prompt_select$你是晨读的选文编辑。读者水平 {{learner_level}}，解释语言 {{explanation_lang}}。

从下面几篇候选里选一篇适合今天精读的文章。主题过滤是 {{topic}}；为空表示不限。节选不超过 {{excerpt_words}} 个英文词。

候选（JSON 数组，每项有 title、url、published_at、text）：

{{candidates}}

只返回 JSON，不要解释：

{"index": 0, "reason": "一句话"}

`index` 是候选数组下标。没有合适的就返回 {"index": null, "reason": "..."}。
$prompt_select$);

insert into public.prompt_templates (owner_id, task, version, body)
values (null, 'annotate', 1, $prompt_annotate$你是晨读的批注编辑。读者水平 {{learner_level}}，解释语言 {{explanation_lang}}，批注深度 {{annotation_depth}}，打开的类型 {{annotation_kinds}}。

原文标题：{{title}}
原文链接：{{source_url}}
主题：{{topic}}

节选（不超过 {{excerpt_words}} 个英文词，保持原文句子，不要改写英文）：

{{excerpt}}

把节选拆成阅读器的 blocks。一段英文是 kind=para，段与段之间用 kind=gap。需要批注的短语在 segment 上标 note（从 1 递增）。notes 与 note 数字一一对应。kind 只能是 vocab、grammar、idiom，且必须落在打开的类型里。解释用 {{explanation_lang}}，body 里用 **强调**。

只返回 JSON：

{
  "zh_title": "",
  "byline": "",
  "lead": "",
  "blocks": [{"kind": "para", "segments": [{"text": "", "note": 1}]}],
  "notes": [{"n": 1, "kind": "vocab", "tag": "", "head": "", "body": ""}]
}
$prompt_annotate$);

insert into public.prompt_templates (owner_id, task, version, body)
values (null, 'vocab', 1, $prompt_vocab$从下面这篇节选里挑 {{vocab_count}} 个值得复习的词或短语。读者水平 {{learner_level}}，解释语言 {{explanation_lang}}。标音：{{include_ipa}}（true 时 ipa 用斜线音标，false 时 ipa 为空字符串）。

标题：{{title}}
链接：{{source_url}}

{{excerpt}}

只返回 JSON 数组，长度等于 {{vocab_count}}：

[{"word": "", "ipa": "", "meaning": "", "example": ""}]

example 必须是节选里的原句，不要另造。
$prompt_vocab$);

insert into public.prompt_templates (owner_id, task, version, body)
values (null, 'patterns', 1, $prompt_patterns$从下面这篇节选里抽出 {{pattern_count}} 个可以模仿的英文句型。读者水平 {{learner_level}}，解释语言 {{explanation_lang}}。

标题：{{title}}
链接：{{source_url}}

{{excerpt}}

只返回 JSON 数组，长度等于 {{pattern_count}}：

[{"pattern": "", "pattern_zh": "", "source": "", "model": "", "model_zh": ""}]

source 是节选原句。model 是用同一句型造的一句新英文，model_zh 是它的 {{explanation_lang}} 翻译。
$prompt_patterns$);

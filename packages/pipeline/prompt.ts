export interface LearnerProfile {
  learnerLevel: string;
  explanationLang: string;
  annotationDepth: string;
  annotationKinds: string[];
  excerptWords: number;
  vocabCount: number;
  includeIpa: boolean;
  patternCount: number;
}

export function renderPrompt(template: string, vars: Record<string, string>): string {
  return template.replace(/\{\{(\w+)\}\}/g, (_match, key: string) => vars[key] ?? "");
}

export function profileVars(
  profile: LearnerProfile,
  extra: Record<string, string> = {},
): Record<string, string> {
  return {
    learner_level: profile.learnerLevel,
    explanation_lang: profile.explanationLang,
    annotation_depth: profile.annotationDepth,
    annotation_kinds: profile.annotationKinds.join(","),
    excerpt_words: String(profile.excerptWords),
    vocab_count: String(profile.vocabCount),
    include_ipa: String(profile.includeIpa),
    pattern_count: String(profile.patternCount),
    topic: "",
    title: "",
    source_url: "",
    excerpt: "",
    candidates: "",
    ...extra,
  };
}

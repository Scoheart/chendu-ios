export interface IssueSegment {
  text: string;
  note?: number;
}

export interface IssueBlock {
  kind: "para" | "gap";
  segments: IssueSegment[];
}

export interface IssueNote {
  n: number;
  kind: "vocab" | "grammar" | "idiom";
  tag: string;
  head: string;
  body: string;
  tilt: number;
}

export interface IssueWord {
  word: string;
  ipa: string;
  meaning: string;
  example: string;
}

export interface IssuePattern {
  pattern: string;
  patternZh: string;
  source: string;
  model: string;
  modelZh: string;
}

export interface IssueDraft {
  date: string;
  topic: string;
  topicLabel: string;
  dateLabel: string;
  title: string;
  zhTitle: string;
  byline: string;
  lead: string;
  blocks: IssueBlock[];
  notes: IssueNote[];
  credit: { text: string; links: { title: string; url: string }[] } | null;
  audio: { id: string; label: string; detail: string; file: string }[];
  words: IssueWord[];
  patterns: IssuePattern[];
  podcast: null;
}

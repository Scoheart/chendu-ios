import { createClient } from "@supabase/supabase-js";

const url = import.meta.env.VITE_SUPABASE_URL || "http://127.0.0.1:54321";
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || "";

export const supabase = createClient(url, anonKey);

export const issueSelect = [
  "id",
  "issue_date",
  "topic",
  "topic_label",
  "title",
  "zh_title",
  "byline",
  "lead",
  "blocks",
  "annotations(n,kind,tag,head,body)",
  "vocab(position,word,ipa,meaning,example)",
  "patterns(position,pattern,pattern_zh,source_sentence,model_sentence,model_zh)",
  "audio_assets(kind,storage_path)",
].join(",");

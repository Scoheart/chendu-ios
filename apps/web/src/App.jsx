import { useEffect, useState } from "react";
import { noteInsert } from "./notes.js";
import { issueSelect, supabase } from "./supabase.js";

export function App() {
  const [session, setSession] = useState(null);
  const [screen, setScreen] = useState("archive");

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSession(data.session));
    const { data } = supabase.auth.onAuthStateChange((_event, next) => setSession(next));
    return () => data.subscription.unsubscribe();
  }, []);

  if (!session) return <Login />;

  return (
    <main>
      <p className="wordmark">晨读</p>
      <nav>
        {[
          ["archive", "往期"],
          ["notes", "笔记"],
          ["settings", "设置"],
          ["cost", "费用"],
        ].map(([id, label]) => (
          <button key={id} className="section" aria-current={screen === id ? "page" : undefined} onClick={() => setScreen(id)}>
            {label}
          </button>
        ))}
        <button onClick={() => supabase.auth.signOut()}>退出</button>
      </nav>
      {screen === "archive" && <Archive onOpen={() => setScreen("reader")} />}
      {screen === "reader" && <Reader />}
      {screen === "notes" && <Notes userId={session.user.id} />}
      {screen === "settings" && <Settings userId={session.user.id} />}
      {screen === "cost" && <Cost />}
    </main>
  );
}

function Login() {
  const [email, setEmail] = useState("");
  const [message, setMessage] = useState("登录后才能阅读。");
  return (
    <main>
      <p className="wordmark">晨读</p>
      <p>{message}</p>
      <form onSubmit={async (event) => {
        event.preventDefault();
        const { error } = await supabase.auth.signInWithOtp({ email });
        setMessage(error ? "发送失败" : "链接已发出。本地验证码在 Inbucket。");
      }}>
        <label>
          邮箱
          <input value={email} onChange={(event) => setEmail(event.target.value)} type="email" required />
        </label>
        <button type="submit">发送登录链接</button>
      </form>
    </main>
  );
}

function Archive({ onOpen }) {
  const [rows, setRows] = useState([]);
  useEffect(() => {
    supabase.from("issues").select("id,issue_date,title,zh_title,topic_label,lead").order("issue_date", { ascending: false })
      .then(({ data }) => {
        setRows(data ?? []);
        if (data?.[0]) sessionStorage.setItem("chendu-issue", data[0].id);
      });
  }, []);
  return (
    <ul>
      {rows.map((row) => (
        <li key={row.id}>
          <button onClick={() => { sessionStorage.setItem("chendu-issue", row.id); onOpen(); }}>
            {row.issue_date} · {row.topic_label} · {row.title}
          </button>
        </li>
      ))}
    </ul>
  );
}

function Reader() {
  const [issue, setIssue] = useState(null);
  const [note, setNote] = useState(null);
  const [audioURL, setAudioURL] = useState("");
  useEffect(() => {
    const id = sessionStorage.getItem("chendu-issue");
    if (!id) return;
    supabase.from("issues").select(issueSelect).eq("id", id).single().then(({ data }) => setIssue(data));
  }, []);
  if (!issue) return <p>先从往期打开一期。</p>;
  const paragraphs = (issue.blocks ?? []).filter((block) => block.kind === "para");
  return (
    <article>
      <h1>{issue.title}</h1>
      <p>{issue.zh_title}</p>
      <p>{issue.lead}</p>
      {paragraphs.map((block, index) => (
        <p key={index}>
          {block.segments?.map((segment, segmentIndex) => (
            <span key={segmentIndex}>
              {segment.note
                ? <button onClick={() => setNote(issue.annotations?.find((item) => item.n === segment.note) ?? null)}>{segment.text}</button>
                : segment.text}
            </span>
          ))}
        </p>
      ))}
      {note && <aside className="note"><strong>{note.head}</strong><p>{note.body}</p></aside>}
      <button onClick={async () => {
        const path = issue.audio_assets?.find((item) => item.kind === "normal")?.storage_path ?? "";
        const object = path.replace(/^audio\//, "");
        const { data } = await supabase.storage.from("audio").createSignedUrl(object, 3600);
        setAudioURL(data?.signedUrl ?? "");
      }}>播放</button>
      {audioURL && <audio src={audioURL} controls />}
    </article>
  );
}

function Notes({ userId }) {
  const [rows, setRows] = useState([]);
  const [body, setBody] = useState("");
  async function load() {
    const { data } = await supabase.from("user_notes").select("id,quote,body,updated_at,deleted_at").is("deleted_at", null).order("updated_at", { ascending: false });
    setRows(data ?? []);
  }
  useEffect(() => { load(); }, []);
  return (
    <section>
      <ul>{rows.map((row) => <li key={row.id}>{row.quote} — {row.body}</li>)}</ul>
      <form onSubmit={async (event) => {
        event.preventDefault();
        const issueId = sessionStorage.getItem("chendu-issue");
        if (!issueId) return;
        const now = new Date().toISOString();
        await supabase.from("user_notes").insert(noteInsert({
          id: crypto.randomUUID(),
          userId,
          issueId,
          body,
          now,
        }));
        setBody("");
        load();
      }}>
        <textarea value={body} onChange={(event) => setBody(event.target.value)} />
        <button type="submit">记下</button>
      </form>
    </section>
  );
}

function Settings({ userId }) {
  const [level, setLevel] = useState("B1");
  const [words, setWords] = useState(400);
  const [secret, setSecret] = useState("");
  const [hint, setHint] = useState("");
  return (
    <form onSubmit={async (event) => {
      event.preventDefault();
      await supabase.from("generation_profiles").update({ learner_level: level, excerpt_words: Number(words) }).eq("user_id", userId);
      if (secret) {
        const { data } = await supabase.rpc("save_provider_key", { p_provider: "openai", p_label: "default", p_secret: secret });
        setHint(data?.[0]?.key_hint ?? "");
        setSecret("");
      }
    }}>
      <label>水平 <input value={level} onChange={(event) => setLevel(event.target.value)} /></label>
      <label>节选词数 <input value={words} onChange={(event) => setWords(event.target.value)} type="number" /></label>
      <label>模型 key <input value={secret} onChange={(event) => setSecret(event.target.value)} type="password" /></label>
      <button type="submit">保存</button>
      {hint && <p>已存 key 末四位 {hint}</p>}
    </form>
  );
}

function Cost() {
  const [total, setTotal] = useState(0);
  useEffect(() => {
    const start = new Date();
    start.setDate(1);
    start.setHours(0, 0, 0, 0);
    supabase.from("jobs").select("cost_usd,created_at").gte("created_at", start.toISOString()).then(({ data }) => {
      const sum = (data ?? []).reduce((acc, row) => acc + Number(row.cost_usd ?? 0), 0);
      setTotal(sum);
    });
  }, []);
  return <p>本月 cost_usd 合计 {total.toFixed(4)}</p>;
}

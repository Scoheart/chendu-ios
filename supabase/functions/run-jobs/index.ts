// Enqueue only. Generation and speech stay in the worker process.
Deno.serve(async () => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    return new Response("missing supabase env", { status: 500 });
  }
  const response = await fetch(`${supabaseUrl}/rest/v1/rpc/enqueue_due`, {
    method: "POST",
    headers: {
      apikey: serviceKey,
      authorization: `Bearer ${serviceKey}`,
      "content-type": "application/json",
    },
    body: "{}",
  });
  console.log(JSON.stringify({ step: "enqueue", status: response.status }));
  return new Response(await response.text(), { status: response.status });
});

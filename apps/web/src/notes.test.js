import assert from "node:assert/strict";
import test from "node:test";
import { noteInsert } from "./notes.js";

test("a web note keeps the client clock and does not send a tombstone", () => {
  const row = noteInsert({
    id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    userId: "11111111-1111-4111-8111-111111111111",
    issueId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    body: "记下",
    now: "2026-10-12T00:00:00.000Z",
  });
  assert.equal(row.id, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa");
  assert.equal(row.user_id, "11111111-1111-4111-8111-111111111111");
  assert.equal(row.issue_id, "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb");
  assert.equal(row.body, "记下");
  assert.equal(row.created_at, "2026-10-12T00:00:00.000Z");
  assert.equal(row.updated_at, row.created_at);
  assert.equal(Object.hasOwn(row, "deleted_at"), false);
});

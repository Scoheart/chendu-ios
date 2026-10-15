export function noteInsert({ id, userId, issueId, body, now }) {
  return {
    id,
    user_id: userId,
    issue_id: issueId,
    paragraph_index: 0,
    start_utf16: 0,
    length_utf16: 0,
    quote: "",
    body,
    created_at: now,
    updated_at: now,
  };
}

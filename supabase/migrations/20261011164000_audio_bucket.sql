-- Private audio. The object name is {user_id}/{issue_id}/{kind}.mp3.
-- The table column storage_path keeps the bucket prefix: audio/{user_id}/...

insert into storage.buckets (id, name, public)
values ('audio', 'audio', false)
on conflict (id) do nothing;

create policy audio_select_own on storage.objects
  for select to authenticated
  using (
    bucket_id = 'audio'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

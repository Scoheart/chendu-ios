-- The settings screen writes these columns. The next job must snapshot them.
update public.generation_profiles
set excerpt_words = 220, learner_level = 'C1'
where user_id = '11111111-1111-4111-8111-111111111111';

select public.enqueue_due('2026-10-12 08:00:00+08');

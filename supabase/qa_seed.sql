-- QA ONLY: this creates one controlled task so the end-to-end earning flow can be verified.
-- Do not use this as the production task source. Disable/delete it after QA.
insert into public.tasks (
  task_type,
  answer_mode,
  prompt,
  correct_answer,
  source_url,
  source_license,
  source_attribution,
  quality_score,
  active
)
select
  'text',
  'yes_no',
  'QA TASK: Is New Delhi the capital of India?',
  'YES',
  'https://www.india.gov.in/',
  'QA/internal test content',
  'TaskFlow QA',
  100,
  true
where not exists (
  select 1 from public.tasks
  where prompt = 'QA TASK: Is New Delhi the capital of India?'
);

-- After QA, disable it:
-- update public.tasks set active=false
-- where prompt = 'QA TASK: Is New Delhi the capital of India?';

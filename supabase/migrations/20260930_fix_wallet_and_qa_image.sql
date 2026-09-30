-- TaskFlow completion + QA image fix.
-- Run this ONCE in Supabase SQL Editor on the existing project.
-- Do not rerun the full schema just for this change.

create or replace function public.submit_task_answer(p_assignment_id uuid,p_answer text)
returns jsonb language plpgsql security definer set search_path=public,pg_catalog as $$
declare
 v_uid uuid:=auth.uid();
 v_assignment public.task_assignments;
 v_task public.tasks;
 v_correct boolean;
 v_reward numeric(12,2);
 v_remaining integer;
 v_balance numeric(12,2);
 v_transaction_id uuid;
 v_activation public.activation_status;
begin
 if v_uid is null then raise exception 'Not authenticated'; end if;

 select p.activation_status into v_activation
 from public.profiles p
 where p.id=v_uid;

 if v_activation<>'approved' then raise exception 'Account is not activated'; end if;

 select ta.* into v_assignment
 from public.task_assignments ta
 where ta.id=p_assignment_id
   and ta.user_id=v_uid
   and ta.status='available'
 for update;

 if not found then raise exception 'Task assignment is unavailable'; end if;

 select task_row.* into v_task
 from public.tasks task_row
 where task_row.id=v_assignment.task_id
   and task_row.active=true;

 if not found then raise exception 'Task is unavailable'; end if;

 v_correct:=upper(trim(p_answer))=upper(trim(v_task.correct_answer));
 v_reward:=case when v_correct then 0.01 else 0 end;

 update public.task_assignments
 set status='submitted',
     submitted_at=now(),
     answer=upper(trim(p_answer)),
     is_correct=v_correct,
     reward=v_reward
 where id=v_assignment.id;

 if v_reward>0 then
   update public.profiles
   set available_balance=available_balance+v_reward
   where id=v_uid
   returning available_balance into v_balance;

   insert into public.wallet_transactions(user_id,amount,kind,reference_id)
   values(v_uid,v_reward,'task_reward',v_assignment.id)
   returning id into v_transaction_id;
 else
   select p.available_balance into v_balance
   from public.profiles p
   where p.id=v_uid;
 end if;

 select p.task_credits into v_remaining
 from public.profiles p
 where p.id=v_uid;

 return jsonb_build_object(
   'status',case when v_remaining=0 then 'BATCH_COMPLETE' else 'OK' end,
   'correct',v_correct,
   'reward',v_reward,
   'available_balance',v_balance,
   'wallet_transaction_id',v_transaction_id,
   'remaining',v_remaining
 );
end $$;

revoke all on function public.submit_task_answer(uuid,text) from public;
grant execute on function public.submit_task_answer(uuid,text) to authenticated;

update public.tasks
set task_type='image',
    answer_mode='yes_no',
    prompt='QA TASK: Is this the flag of India?',
    asset_url='https://commons.wikimedia.org/wiki/Special:FilePath/Flag_of_India.png',
    source_url='https://commons.wikimedia.org/wiki/File:Flag_of_India.png',
    source_license='Public domain',
    source_attribution='Wikimedia Commons — Flag of India',
    correct_answer='YES',
    quality_score=100,
    active=true
where prompt in (
  'QA TASK: Is New Delhi the capital of India?',
  'QA TASK: Is this the flag of India?'
);

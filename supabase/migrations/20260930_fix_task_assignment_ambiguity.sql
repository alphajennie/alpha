-- Fix task assignment RPCs after schema deployment.
-- This migration removes PL/pgSQL record/table alias name collisions
-- that can produce errors such as: column reference "t.id" is ambiguous.

create or replace function public.get_next_task()
returns jsonb language plpgsql security definer set search_path=public,pg_catalog as $$
declare
 v_uid uuid:=auth.uid();
 v_assignment public.task_assignments;
 v_task public.tasks;
 v_credits integer;
 v_activation public.activation_status;
begin
 if v_uid is null then raise exception 'Not authenticated'; end if;

 select p.activation_status,p.task_credits
 into v_activation,v_credits
 from public.profiles p
 where p.id=v_uid
 for update;

 if v_activation<>'approved' then
   return jsonb_build_object('status','PENDING_ACTIVATION','activation_status',v_activation);
 end if;

 select ta.*
 into v_assignment
 from public.task_assignments ta
 join public.tasks task_row on task_row.id=ta.task_id
 where ta.user_id=v_uid
   and ta.status='available'
   and task_row.active=true
   and task_row.quality_score>=80
 order by ta.assigned_at
 limit 1;

 if found then
   select task_row.*
   into v_task
   from public.tasks task_row
   where task_row.id=v_assignment.task_id;

   return jsonb_build_object(
     'assignment_id',v_assignment.id,
     'task_id',v_task.id,
     'task_type',v_task.task_type,
     'answer_mode',v_task.answer_mode,
     'prompt',v_task.prompt,
     'asset_url',v_task.asset_url,
     'options',v_task.options,
     'remaining',v_credits
   );
 end if;

 if v_credits<=0 then
   return jsonb_build_object('status','NO_TASKS','remaining',0,'message','Your current task batch is complete.');
 end if;

 select task_row.*
 into v_task
 from public.tasks task_row
 where task_row.active=true
   and task_row.quality_score>=80
   and not exists(
     select 1
     from public.task_assignments existing_assignment
     where existing_assignment.user_id=v_uid
       and existing_assignment.task_id=task_row.id
   )
 order by random()
 limit 1;

 if not found then
   return jsonb_build_object(
     'status','NO_TASKS',
     'remaining',v_credits,
     'message','No verified tasks are available right now. The task queue is empty.'
   );
 end if;

 insert into public.task_assignments(user_id,task_id)
 values(v_uid,v_task.id)
 returning * into v_assignment;

 update public.profiles
 set task_credits=task_credits-1
 where id=v_uid
 returning task_credits into v_credits;

 return jsonb_build_object(
   'assignment_id',v_assignment.id,
   'task_id',v_task.id,
   'task_type',v_task.task_type,
   'answer_mode',v_task.answer_mode,
   'prompt',v_task.prompt,
   'asset_url',v_task.asset_url,
   'options',v_task.options,
   'remaining',v_credits
 );
end $$;

create or replace function public.submit_task_answer(p_assignment_id uuid,p_answer text)
returns jsonb language plpgsql security definer set search_path=public,pg_catalog as $$
declare
 v_uid uuid:=auth.uid();
 v_assignment public.task_assignments;
 v_task public.tasks;
 v_correct boolean;
 v_reward numeric(12,2);
 v_remaining integer;
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
     answer=p_answer,
     is_correct=v_correct,
     reward=v_reward
 where id=v_assignment.id;

 if v_reward>0 then
   update public.profiles
   set available_balance=available_balance+v_reward
   where id=v_uid;

   insert into public.wallet_transactions(user_id,amount,kind,reference_id)
   values(v_uid,v_reward,'task_reward',v_assignment.id);
 end if;

 select p.task_credits into v_remaining
 from public.profiles p
 where p.id=v_uid;

 return jsonb_build_object(
   'status',case when v_remaining=0 then 'BATCH_COMPLETE' else 'OK' end,
   'correct',v_correct,
   'remaining',v_remaining
 );
end $$;

revoke all on function public.get_next_task() from public;
grant execute on function public.get_next_task() to authenticated;
revoke all on function public.submit_task_answer(uuid,text) from public;
grant execute on function public.submit_task_answer(uuid,text) to authenticated;

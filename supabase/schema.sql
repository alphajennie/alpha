create extension if not exists pgcrypto;
create type public.task_type as enum ('image','text','data','ocr');
create type public.answer_mode as enum ('yes_no','four_option');
create type public.assignment_status as enum ('available','submitted','expired','rejected');

create table public.profiles(id uuid primary key references auth.users(id) on delete cascade,phone text unique,created_at timestamptz not null default now(),task_credits integer not null default 10 check(task_credits>=0),available_balance numeric(12,2) not null default 0 check(available_balance>=0),pending_balance numeric(12,2) not null default 0 check(pending_balance>=0),quality_score numeric(5,2) not null default 100 check(quality_score between 0 and 100));
create table public.tasks(id uuid primary key default gen_random_uuid(),task_type public.task_type not null,answer_mode public.answer_mode not null,prompt text not null,asset_url text,options jsonb,correct_answer text not null,source_url text,source_license text,source_attribution text,quality_score numeric(5,2) not null default 0,active boolean not null default false,created_at timestamptz not null default now(),check((answer_mode='yes_no' and options is null) or (answer_mode='four_option' and jsonb_array_length(options)=4)));
create table public.task_assignments(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,task_id uuid not null references public.tasks(id) on delete restrict,status public.assignment_status not null default 'available',assigned_at timestamptz not null default now(),submitted_at timestamptz,answer text,is_correct boolean,reward numeric(12,2) not null default 0,unique(user_id,task_id));
create table public.wallet_transactions(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,amount numeric(12,2) not null,kind text not null check(kind in('task_reward','ad_unlock','adjustment','withdrawal')),reference_id uuid,created_at timestamptz not null default now());
create table public.ad_unlocks(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,provider text not null,provider_event_id text not null unique,tasks_granted integer not null default 10 check(tasks_granted>0),verified_at timestamptz not null default now());
create index task_assignments_user_status on public.task_assignments(user_id,status);
create index tasks_active_type on public.tasks(active,task_type);

alter table public.profiles enable row level security;
alter table public.tasks enable row level security;
alter table public.task_assignments enable row level security;
alter table public.wallet_transactions enable row level security;
alter table public.ad_unlocks enable row level security;

create policy "profiles self read" on public.profiles for select using(auth.uid()=id);
create policy "assignments self read" on public.task_assignments for select using(auth.uid()=user_id);
create policy "wallet self read" on public.wallet_transactions for select using(auth.uid()=user_id);

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$begin insert into public.profiles(id,phone) values(new.id,new.phone) on conflict(id) do update set phone=excluded.phone; return new; end$$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create or replace function public.get_next_task() returns jsonb language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid();a public.task_assignments;t public.tasks;credits integer;
begin
 if uid is null then raise exception 'Not authenticated'; end if;
 select task_credits into credits from public.profiles where id=uid for update;
 select * into a from public.task_assignments where user_id=uid and status='available' order by assigned_at limit 1;
 if found then select * into t from public.tasks where id=a.task_id and active=true; if found then return jsonb_build_object('assignment_id',a.id,'task_id',t.id,'task_type',t.task_type,'answer_mode',t.answer_mode,'prompt',t.prompt,'asset_url',t.asset_url,'options',t.options,'remaining',credits); end if; end if;
 if credits<=0 then return jsonb_build_object('status','NO_TASKS','remaining',0); end if;
 select * into t from public.tasks where active=true order by random() limit 1;
 if not found then return jsonb_build_object('status','NO_TASKS','remaining',credits); end if;
 insert into public.task_assignments(user_id,task_id) values(uid,t.id) on conflict do nothing returning * into a;
 update public.profiles set task_credits=task_credits-1 where id=uid returning task_credits into credits;
 return jsonb_build_object('assignment_id',a.id,'task_id',t.id,'task_type',t.task_type,'answer_mode',t.answer_mode,'prompt',t.prompt,'asset_url',t.asset_url,'options',t.options,'remaining',credits);
end$$;

create or replace function public.submit_task_answer(p_assignment_id uuid,p_answer text) returns jsonb language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid();a public.task_assignments;t public.tasks;ok boolean;reward numeric(12,2);remaining integer;
begin
 if uid is null then raise exception 'Not authenticated'; end if;
 select * into a from public.task_assignments where id=p_assignment_id and user_id=uid and status='available' for update;
 if not found then raise exception 'Task assignment is unavailable'; end if;
 select * into t from public.tasks where id=a.task_id and active=true;
 if not found then raise exception 'Task is unavailable'; end if;
 ok:=upper(trim(p_answer))=upper(trim(t.correct_answer)); reward:=case when ok then 0.01 else 0 end;
 update public.task_assignments set status='submitted',submitted_at=now(),answer=p_answer,is_correct=ok,reward=reward where id=a.id;
 if reward>0 then update public.profiles set available_balance=available_balance+reward where id=uid; insert into public.wallet_transactions(user_id,amount,kind,reference_id) values(uid,reward,'task_reward',a.id); end if;
 select task_credits into remaining from public.profiles where id=uid;
 return jsonb_build_object('status',case when remaining=0 then 'BATCH_COMPLETE' else 'OK' end,'correct',ok,'remaining',remaining);
end$$;

revoke all on function public.get_next_task() from public;
grant execute on function public.get_next_task() to authenticated;
revoke all on function public.submit_task_answer(uuid,text) from public;
grant execute on function public.submit_task_answer(uuid,text) to authenticated;
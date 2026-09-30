create extension if not exists pgcrypto;

do $$ begin
 create type public.task_type as enum ('image','text','data','ocr');
exception when duplicate_object then null; end $$;
do $$ begin
 create type public.answer_mode as enum ('yes_no','four_option');
exception when duplicate_object then null; end $$;
do $$ begin
 create type public.assignment_status as enum ('available','submitted','expired','rejected');
exception when duplicate_object then null; end $$;
do $$ begin
 create type public.activation_status as enum ('pending','approved','rejected');
exception when duplicate_object then null; end $$;

create table if not exists public.profiles(
 id uuid primary key references auth.users(id) on delete cascade,
 name text,
 phone text unique,
 created_at timestamptz not null default now(),
 activation_status public.activation_status not null default 'pending',
 activated_at timestamptz,
 is_admin boolean not null default false,
 task_credits integer not null default 10 check(task_credits>=0),
 available_balance numeric(12,2) not null default 0 check(available_balance>=0),
 pending_balance numeric(12,2) not null default 0 check(pending_balance>=0),
 quality_score numeric(5,2) not null default 100 check(quality_score between 0 and 100)
);

alter table public.profiles add column if not exists name text;
alter table public.profiles add column if not exists activation_status public.activation_status not null default 'pending';
alter table public.profiles add column if not exists activated_at timestamptz;
alter table public.profiles add column if not exists is_admin boolean not null default false;

create table if not exists public.tasks(
 id uuid primary key default gen_random_uuid(),
 task_type public.task_type not null,
 answer_mode public.answer_mode not null,
 prompt text not null,
 asset_url text,
 options jsonb,
 correct_answer text not null,
 source_url text,
 source_license text,
 source_attribution text,
 quality_score numeric(5,2) not null default 0,
 active boolean not null default false,
 created_at timestamptz not null default now(),
 check((answer_mode='yes_no' and options is null) or (answer_mode='four_option' and jsonb_array_length(options)=4))
);

create table if not exists public.task_assignments(
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 task_id uuid not null references public.tasks(id) on delete restrict,
 status public.assignment_status not null default 'available',
 assigned_at timestamptz not null default now(),
 submitted_at timestamptz,
 answer text,
 is_correct boolean,
 reward numeric(12,2) not null default 0,
 unique(user_id,task_id)
);

create table if not exists public.wallet_transactions(
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 amount numeric(12,2) not null,
 kind text not null check(kind in('task_reward','ad_unlock','adjustment','withdrawal')),
 reference_id uuid,
 created_at timestamptz not null default now()
);

create table if not exists public.ad_unlocks(
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 provider text not null,
 provider_event_id text not null unique,
 tasks_granted integer not null default 10 check(tasks_granted>0),
 verified_at timestamptz not null default now()
);

create index if not exists task_assignments_user_status on public.task_assignments(user_id,status);
create index if not exists tasks_active_type on public.tasks(active,task_type);
create index if not exists profiles_activation_status on public.profiles(activation_status,created_at);
create unique index if not exists profiles_phone_unique on public.profiles(phone) where phone is not null;

alter table public.profiles enable row level security;
alter table public.tasks enable row level security;
alter table public.task_assignments enable row level security;
alter table public.wallet_transactions enable row level security;
alter table public.ad_unlocks enable row level security;

drop policy if exists "profiles self read" on public.profiles;
drop policy if exists "profiles admin read" on public.profiles;
drop policy if exists "assignments self read" on public.task_assignments;
drop policy if exists "wallet self read" on public.wallet_transactions;

create policy "profiles self read" on public.profiles for select to authenticated using(auth.uid()=id);
create policy "profiles admin read" on public.profiles for select to authenticated using(exists(select 1 from public.profiles p where p.id=auth.uid() and p.is_admin=true));
create policy "assignments self read" on public.task_assignments for select to authenticated using(auth.uid()=user_id);
create policy "wallet self read" on public.wallet_transactions for select to authenticated using(auth.uid()=user_id);

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path=public,pg_catalog as $$
begin
 insert into public.profiles(id,name,phone)
 values(new.id, null, null)
 on conflict(id) do nothing;
 return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

create or replace function public.submit_activation_request(p_name text,p_phone text)
returns jsonb language plpgsql security definer set search_path=public,pg_catalog as $$
declare uid uuid:=auth.uid(); clean_name text:=trim(regexp_replace(coalesce(p_name,''),'[[:space:]]+',' ','g')); clean_phone text:=regexp_replace(coalesce(p_phone,''),'[^0-9+]','','g'); existing_status public.activation_status;
begin
 if uid is null then raise exception 'Not authenticated'; end if;
 if length(clean_name)<2 or length(clean_name)>80 then raise exception 'Invalid name'; end if;
 if clean_phone !~ '^\+91[0-9]{10}$' then raise exception 'Invalid Indian mobile number'; end if;
 select activation_status into existing_status from public.profiles where id=uid for update;
 update public.profiles set name=clean_name,phone=clean_phone where id=uid;
 return jsonb_build_object('status',coalesce(existing_status,'pending'),'name',clean_name,'phone',clean_phone);
exception when unique_violation then
 raise exception 'This mobile number already has an application.';
end $$;

create or replace function public.get_my_activation_status()
returns jsonb language plpgsql security definer set search_path=public,pg_catalog as $$
declare uid uuid:=auth.uid(); r public.profiles;
begin
 if uid is null then raise exception 'Not authenticated'; end if;
 select * into r from public.profiles where id=uid;
 if not found then raise exception 'Profile not found'; end if;
 return jsonb_build_object('id',r.id,'name',r.name,'phone',r.phone,'status',r.activation_status,'created_at',r.created_at,'activated_at',r.activated_at);
end $$;

create or replace function public.is_current_user_admin()
returns boolean language sql security definer set search_path=public,pg_catalog as $$
 select exists(select 1 from public.profiles where id=auth.uid() and is_admin=true);
$$;

create or replace function public.list_activation_requests()
returns setof public.profiles language plpgsql security definer set search_path=public,pg_catalog as $$
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and is_admin=true) then raise exception 'Administrator access required'; end if;
 return query
 select * from public.profiles
 where activation_status='pending'
 order by created_at asc;
end $$;

create or replace function public.get_admin_overview()
returns jsonb language plpgsql security definer set search_path=public,pg_catalog as $
declare
 pending_count integer;
 approved_count integer;
 active_count integer;
 completed_count integer;
 reward_total numeric(12,2);
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and is_admin=true) then
  raise exception 'Administrator access required';
 end if;
 select count(*) into pending_count from public.profiles where activation_status='pending';
 select count(*) into approved_count from public.profiles where activation_status='approved';
 select count(*) into active_count from public.tasks where active=true and quality_score>=80;
 select count(*) into completed_count from public.task_assignments where status='submitted';
 select coalesce(sum(amount),0) into reward_total from public.wallet_transactions where kind='task_reward';
 return jsonb_build_object(
  'pending_applications',pending_count,
  'approved_users',approved_count,
  'active_tasks',active_count,
  'completed_tasks',completed_count,
  'rewards_issued',reward_total
 );
end $;

create or replace function public.set_activation_status(p_user_id uuid,p_status public.activation_status)
returns jsonb language plpgsql security definer set search_path=public,pg_catalog as $$
declare target public.profiles;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and is_admin=true) then raise exception 'Administrator access required'; end if;
 if p_status not in ('approved','rejected') then raise exception 'Invalid activation status'; end if;
 update public.profiles
 set activation_status=p_status,
     activated_at=case when p_status='approved' then coalesce(activated_at,now()) else null end,
     task_credits=case when p_status='approved' and activation_status<>'approved' then 10 else task_credits end
 where id=p_user_id
 returning * into target;
 if not found then raise exception 'Account not found'; end if;
 return jsonb_build_object('id',target.id,'status',target.activation_status);
end $$;

create or replace function public.get_next_task()
returns jsonb language plpgsql security definer set search_path=public,pg_catalog as $$
declare
 uid uuid:=auth.uid();
 a public.task_assignments;
 t public.tasks;
 credits integer;
 activation public.activation_status;
begin
 if uid is null then raise exception 'Not authenticated'; end if;
 select activation_status,task_credits into activation,credits from public.profiles where id=uid for update;
 if activation<>'approved' then return jsonb_build_object('status','PENDING_ACTIVATION','activation_status',activation); end if;

 select a.* into a
 from public.task_assignments a
 join public.tasks t on t.id=a.task_id
 where a.user_id=uid and a.status='available' and t.active=true and t.quality_score>=80
 order by a.assigned_at
 limit 1;

 if found then
   select * into t from public.tasks where id=a.task_id;
   return jsonb_build_object('assignment_id',a.id,'task_id',t.id,'task_type',t.task_type,'answer_mode',t.answer_mode,'prompt',t.prompt,'asset_url',t.asset_url,'options',t.options,'remaining',credits);
 end if;

 if credits<=0 then
   return jsonb_build_object('status','NO_TASKS','remaining',0,'message','Your current task batch is complete.');
 end if;

 select t.* into t
 from public.tasks t
 where t.active=true
   and t.quality_score>=80
   and not exists(select 1 from public.task_assignments ax where ax.user_id=uid and ax.task_id=t.id)
 order by random()
 limit 1;

 if not found then
   return jsonb_build_object('status','NO_TASKS','remaining',credits,'message','No verified tasks are available right now. The task queue is empty.');
 end if;

 insert into public.task_assignments(user_id,task_id)
 values(uid,t.id)
 returning * into a;

 update public.profiles
 set task_credits=task_credits-1
 where id=uid
 returning task_credits into credits;

 return jsonb_build_object(
  'assignment_id',a.id,
  'task_id',t.id,
  'task_type',t.task_type,
  'answer_mode',t.answer_mode,
  'prompt',t.prompt,
  'asset_url',t.asset_url,
  'options',t.options,
  'remaining',credits
 );
end $$;

create or replace function public.submit_task_answer(p_assignment_id uuid,p_answer text)
returns jsonb language plpgsql security definer set search_path=public,pg_catalog as $$
declare uid uuid:=auth.uid(); a public.task_assignments; t public.tasks; ok boolean; reward numeric(12,2); remaining integer; activation public.activation_status;
begin
 if uid is null then raise exception 'Not authenticated'; end if;
 select activation_status into activation from public.profiles where id=uid;
 if activation<>'approved' then raise exception 'Account is not activated'; end if;
 select * into a from public.task_assignments where id=p_assignment_id and user_id=uid and status='available' for update;
 if not found then raise exception 'Task assignment is unavailable'; end if;
 select * into t from public.tasks where id=a.task_id and active=true;
 if not found then raise exception 'Task is unavailable'; end if;
 ok:=upper(trim(p_answer))=upper(trim(t.correct_answer));
 reward:=case when ok then 0.01 else 0 end;
 update public.task_assignments set status='submitted',submitted_at=now(),answer=p_answer,is_correct=ok,reward=reward where id=a.id;
 if reward>0 then
   update public.profiles set available_balance=available_balance+reward where id=uid;
   insert into public.wallet_transactions(user_id,amount,kind,reference_id) values(uid,reward,'task_reward',a.id);
 end if;
 select task_credits into remaining from public.profiles where id=uid;
 return jsonb_build_object('status',case when remaining=0 then 'BATCH_COMPLETE' else 'OK' end,'correct',ok,'remaining',remaining);
end $$;

revoke all on function public.submit_activation_request(text,text) from public;
grant execute on function public.submit_activation_request(text,text) to authenticated;
revoke all on function public.get_my_activation_status() from public;
grant execute on function public.get_my_activation_status() to authenticated;
revoke all on function public.is_current_user_admin() from public;
grant execute on function public.is_current_user_admin() to authenticated;
revoke all on function public.list_activation_requests() from public;
grant execute on function public.list_activation_requests() to authenticated;
revoke all on function public.get_admin_overview() from public;
grant execute on function public.get_admin_overview() to authenticated;
revoke all on function public.set_activation_status(uuid,public.activation_status) from public;
grant execute on function public.set_activation_status(uuid,public.activation_status) to authenticated;
revoke all on function public.get_next_task() from public;
grant execute on function public.get_next_task() to authenticated;
revoke all on function public.submit_task_answer(uuid,text) from public;
grant execute on function public.submit_task_answer(uuid,text) to authenticated;

-- Create your first admin account through Supabase Authentication, then run:
-- update public.profiles set is_admin=true where id='<ADMIN_AUTH_USER_UUID>';

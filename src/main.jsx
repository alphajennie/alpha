import React,{useEffect,useState} from 'react';
import {createRoot} from 'react-dom/client';
import {ArrowLeft,Check,ChevronRight,Image,FileText,Database,ScanText,Sparkles,ShieldCheck,WalletCards,LogOut,Clock3,UserCheck,X,RefreshCw,Users,Layers3,IndianRupee,Activity,CircleAlert,Play,ClipboardCheck} from 'lucide-react';
import {supabase} from './lib/supabase';
import './styles.css';

const TASK_TYPES={image:{label:'Image verification',icon:Image},text:{label:'Text verification',icon:FileText},data:{label:'Data verification',icon:Database},ocr:{label:'OCR verification',icon:ScanText}};

function App(){
 const [session,setSession]=useState(null),[loading,setLoading]=useState(true),[view,setView]=useState(window.location.pathname==='/admin'?'admin':'home'),[task,setTask]=useState(null),[remaining,setRemaining]=useState(null),[error,setError]=useState(''),[status,setStatus]=useState(null),[profile,setProfile]=useState(null);
 useEffect(()=>{if(!supabase){setLoading(false);return}supabase.auth.getSession().then(({data})=>{setSession(data.session);setLoading(false)});const {data:{subscription}}=supabase.auth.onAuthStateChange((_e,s)=>setSession(s));return()=>subscription.unsubscribe()},[]);
 useEffect(()=>{if(session&&view!=='admin')loadStatus();},[session]);
 async function loadStatus(){
  setError('');
  const {data,error}=await supabase.rpc('get_my_activation_status');
  if(error){setError(error.message);return}
  setStatus(data);
  if(data?.status==='approved'){
   await loadProfile();
   setView('dashboard');
  }else if(data?.status==='rejected')setView('rejected');
  else setView('pending');
 }
 async function loadProfile(){
  if(!session?.user?.id)return;
  const {data,error}=await supabase.from('profiles').select('available_balance,task_credits,quality_score').eq('id',session.user.id).single();
  if(!error)setProfile(data);
 }
 async function loadTask(){
  setError('');
  const {data,error}=await supabase.rpc('get_next_task');
  if(error){setError(error.message);return}
  if(data?.status==='PENDING_ACTIVATION'){setStatus(s=>({...s,status:'pending'}));setView('pending');return}
  if(data?.status==='NO_TASKS'){
   setTask(null);setRemaining(data.remaining??profile?.task_credits??0);setError(data.message||'No verified tasks are available right now. The task queue is empty.');await loadProfile();return;
  }
  setTask(data);setRemaining(data.remaining??null);setError('');setView('task');
 }
 async function submit(answer){
  if(!task)return;
  setError('');
  const {data,error}=await supabase.rpc('submit_task_answer',{p_assignment_id:task.assignment_id,p_answer:answer});
  if(error){setError(error.message);return}
  setRemaining(data?.remaining??null);
  await loadProfile();
  if(data?.status==='BATCH_COMPLETE'){setTask(null);setView('unlock')}else await loadTask();
 }
 async function signOut(){await supabase.auth.signOut();setSession(null);setStatus(null);setProfile(null);setTask(null);setView('home')}
 if(loading)return <Shell><div className="loading">Loading secure session…</div></Shell>;
 if(!supabase)return <Shell><main className="container centered"><div className="card notice"><span className="eyebrow">CONFIGURATION REQUIRED</span><h2>Connect Supabase</h2><p>Add the two VITE_SUPABASE environment variables to your deployment.</p></div></main></Shell>;
 if(view==='admin')return <AdminGate session={session} onBack={()=>{window.history.replaceState({},'', '/');setView(session?'pending':'home')}}/>;
 if(!session&&view==='auth')return <Auth onBack={()=>setView('home')} onSuccess={(s)=>{setSession(s);setView('pending')}}/>;
 if(!session)return <Home onStart={()=>setView('auth')}/>;
 if(view==='task'&&task)return <Task task={task} remaining={remaining} error={error} onBack={()=>{setError('');setView('dashboard')}} onSubmit={submit}/>;
 if(view==='unlock')return <Unlock onBack={()=>setView('dashboard')} error={error} onRequest={()=>setError('More tasks are released only through an approved, verified unlock provider. No ad is being simulated.')}/>;
 if(view==='rejected')return <Rejected onSignOut={signOut}/>;
 if(view==='pending')return <Pending status={status} onRefresh={loadStatus} onSignOut={signOut}/>;
 return <Dashboard profile={profile} remaining={remaining} error={error} onTask={loadTask} onRefresh={loadProfile} onSignOut={signOut}/>;
}

function Shell({children}){return <div className="shell"><header className="nav"><div className="brand"><span className="mark"><Sparkles size={17}/></span>TaskFlow</div><span className="secure"><span/> Secure</span></header>{children}<footer>TaskFlow · Verified human data work</footer></div>}
function Home({onStart}){return <Shell><main className="container home"><section className="hero card"><div><span className="eyebrow">HUMAN DATA VERIFICATION</span><h1>Small tasks.<br/><em>Useful data.</em></h1><p>Apply with your name and mobile number. Every account is reviewed manually before task access is activated.</p><button className="primary" onClick={onStart}>Apply for access <ChevronRight size={18}/></button></div><div className="hero-art"><div className="floating a">PENDING</div><div className="hero-center"><ShieldCheck size={28}/><b>Manual approval</b><small>Quality-first access</small></div><div className="floating b">VERIFIED</div></div></section></main></Shell>}

function Auth({onBack,onSuccess}){const [name,setName]=useState(''),[phone,setPhone]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState('');
 async function submit(){setError('');const cleanName=name.trim().replace(/\s+/g,' '),n=phone.replace(/\D/g,'');if(cleanName.length<2||cleanName.length>80){setError('Enter your full name.');return}if(n.length!==10){setError('Enter a valid 10-digit Indian mobile number.');return}setBusy(true);let {data:authData,error:authError}=await supabase.auth.getSession();if(!authData.session){const r=await supabase.auth.signInAnonymously();authData=r.data;authError=r.error}if(authError){setBusy(false);setError(authError.message);return}const {data,error}=await supabase.rpc('submit_activation_request',{p_name:cleanName,p_phone:'+91'+n});setBusy(false);if(error){setError(error.message);return}onSuccess(authData.session||data?.session)}
 return <Shell><main className="auth-wrap"><div className="card auth"><button className="icon-btn" onClick={onBack}><ArrowLeft size={18}/></button><div className="brand auth-brand"><span className="mark"><Sparkles size={17}/></span>TaskFlow</div><span className="eyebrow">ACCESS REQUEST</span><h2>Join TaskFlow.</h2><p>Enter your name and mobile number. There is no OTP at this stage. An admin will review your application before activation.</p><label>Full name</label><input className="field" value={name} onChange={e=>setName(e.target.value)} placeholder="Your full name" autoComplete="name"/><label className="field-label">Mobile number</label><div className="phone"><b>+91</b><input value={phone} onChange={e=>setPhone(e.target.value.replace(/\D/g,'').slice(0,10))} inputMode="numeric" placeholder="98765 43210"/></div><button className="primary full" disabled={busy} onClick={submit}>{busy?'Submitting…':'Submit application'}<ChevronRight size={18}/></button>{error&&<div className="error">{error}</div>}<small>Your application is stored securely. Task access remains locked until manual approval.</small></div></main></Shell>}

function Pending({status,onRefresh,onSignOut}){return <Shell><main className="auth-wrap"><div className="card unlock pending-card"><div className="pending-icon"><Clock3 size={30}/></div><span className="eyebrow">ACCOUNT WAITING</span><h2>Pending activation.</h2><p>Your application has been received. An admin will review your account manually. You cannot receive tasks or rewards until the account is approved.</p><div className="status-box"><span>Applicant</span><b>{status?.name||'—'}</b><span>Mobile</span><b>{status?.phone||'—'}</b><span>Status</span><b className="status-pending">Pending review</b></div><button className="primary full" onClick={onRefresh}><RefreshCw size={17}/> Check status</button><button className="link" onClick={onSignOut}>Leave this device</button></div></main></Shell>}

function Rejected({onSignOut}){return <Shell><main className="auth-wrap"><div className="card unlock"><div className="rejected-icon"><X size={30}/></div><span className="eyebrow">ACCESS NOT ACTIVATED</span><h2>Application not approved.</h2><p>Your application is not currently approved for TaskFlow. Contact the administrator if you believe this is incorrect.</p><button className="primary full" onClick={onSignOut}>Return to start</button></div></main></Shell>}

function Dashboard({profile,remaining,error,onTask,onRefresh,onSignOut}){const credits=remaining??profile?.task_credits??0;return <Shell><main className="container"><div className="dashboard-head"><div><span className="eyebrow">YOUR WORKSPACE</span><h2>Ready when you are.</h2></div><div className="head-actions"><button className="icon-btn" onClick={onRefresh} title="Refresh"><RefreshCw size={18}/></button><button className="icon-btn" onClick={onSignOut} title="Sign out"><LogOut size={18}/></button></div></div><div className="dash-grid"><div className="card balance"><div className="icon-box"><WalletCards size={20}/></div><span className="muted">Available balance</span><strong>₹{Number(profile?.available_balance||0).toFixed(2)}</strong><small>Only server-validated task rewards are credited.</small></div><div className="card tasks"><div className="task-head"><span className="eyebrow">TASK QUEUE</span><span className="count">{credits}</span></div><h3>Verified data tasks</h3><p>Tasks are assigned by the server. The answer key stays in the database and is never sent to the browser before submission.</p><button className="primary" onClick={onTask}><Play size={16}/> Get next task <ChevronRight size={18}/></button>{error&&<div className="queue-warning"><CircleAlert size={17}/><div><b>Task queue status</b><span>{error}</span></div></div>}</div></div></main></Shell>}

function Task({task,remaining,error,onBack,onSubmit}){const meta=TASK_TYPES[task.task_type]||TASK_TYPES.data,Icon=meta.icon;return <Shell><main className="container task-page"><div className="task-top"><button className="icon-btn" onClick={onBack}><ArrowLeft size={18}/></button><span>{remaining??'—'} tasks remaining</span></div><div className="progress"><span style={{width:'8%'}}/></div><section className="card task-card"><div className="type"><Icon size={15}/>{meta.label}</div>{task.asset_url?<img className="asset" src={task.asset_url} alt="Task input"/>:<div className="asset-placeholder"><Icon size={30}/><span>Source content</span></div>}<h1>{task.prompt}</h1>{task.answer_mode==='yes_no'?<div className="answers two"><button onClick={()=>onSubmit('YES')}><Check/>YES</button><button onClick={()=>onSubmit('NO')}><span className="x">×</span>NO</button></div>:<div className="answers">{(task.options||[]).map((o,i)=><button key={i} onClick={()=>onSubmit(String.fromCharCode(65+i))}><b>{String.fromCharCode(65+i)}</b>{o}</button>)}</div>}{error&&<div className="error">{error}</div>}</section></main></Shell>}

function Unlock({onBack,onRequest,error}){return <Shell><main className="auth-wrap"><div className="card unlock"><div className="success"><Check size={30}/></div><span className="eyebrow">BATCH COMPLETE</span><h2>Ready for more?</h2><p>Your current task batch is complete. More work will be released only when the verified task supply and unlock system make it available.</p><button className="primary full" onClick={onRequest}>Check for more tasks <RefreshCw size={17}/></button><button className="link" onClick={onBack}>Back to dashboard</button>{error&&<div className="error">{error}</div>}</div></main></Shell>}

function AdminGate({session,onBack}){const [email,setEmail]=useState(''),[password,setPassword]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState(''),[authorized,setAuthorized]=useState(false);
 useEffect(()=>{if(session&&!session.user.is_anonymous)checkAdmin()},[session]);
 async function checkAdmin(){const {data,error}=await supabase.rpc('is_current_user_admin');if(error){setError(error.message);return}setAuthorized(Boolean(data))}
 async function login(){setError('');setBusy(true);const {data,error}=await supabase.auth.signInWithPassword({email,password});setBusy(false);if(error){setError(error.message);return}const {data:ok,error:e}=await supabase.rpc('is_current_user_admin');if(e||!ok){await supabase.auth.signOut();setError('This account is not an administrator.');return}setAuthorized(true)}
 if(authorized)return <AdminPanel onBack={onBack}/>;
 return <Shell><main className="auth-wrap"><div className="card auth"><button className="icon-btn" onClick={onBack}><ArrowLeft size={18}/></button><span className="eyebrow">ADMIN CONSOLE</span><h2>Control center.</h2><p>Sign in with the separate permanent Supabase administrator account.</p><label>Email</label><input className="field" value={email} onChange={e=>setEmail(e.target.value)} type="email" autoComplete="username"/><label className="field-label">Password</label><input className="field" value={password} onChange={e=>setPassword(e.target.value)} type="password" autoComplete="current-password"/><button className="primary full" disabled={busy} onClick={login}>{busy?'Signing in…':'Open admin console'}<ChevronRight size={18}/></button>{error&&<div className="error">{error}</div>}</div></main></Shell>}

function AdminPanel({onBack}){const [rows,setRows]=useState([]),[stats,setStats]=useState(null),[busy,setBusy]=useState(true),[error,setError]=useState('');
 async function load(){setBusy(true);setError('');const [requests,overview]=await Promise.all([supabase.rpc('list_activation_requests'),supabase.rpc('get_admin_overview')]);if(requests.error)setError(requests.error.message);else setRows(requests.data||[]);if(overview.error&&!requests.error)setError(overview.error.message);else setStats(overview.data||null);setBusy(false)}
 useEffect(()=>{load()},[]);
 async function decide(id,decision){setError('');const {error}=await supabase.rpc('set_activation_status',{p_user_id:id,p_status:decision});if(error){setError(error.message);return}await load()}
 async function logout(){await supabase.auth.signOut();window.location.href='/admin'}
 return <Shell><main className="container admin-page"><div className="admin-hero"><div><span className="eyebrow">ADMIN CONTROL CENTER</span><h2>Operate TaskFlow.</h2><p>Review applicants, monitor the live task inventory, and see whether the earning pipeline is actually ready.</p></div><div className="admin-actions"><button className="icon-btn" onClick={load} title="Refresh"><RefreshCw size={18}/></button><button className="icon-btn" onClick={logout} title="Sign out"><LogOut size={18}/></button></div></div>{error&&<div className="error">{error}</div>}<div className="admin-stats"><Stat icon={Users} label="Pending applications" value={stats?.pending_applications??rows.length} tone="amber"/><Stat icon={Layers3} label="Active tasks" value={stats?.active_tasks??0} tone="blue"/><Stat icon={ClipboardCheck} label="Completed tasks" value={stats?.completed_tasks??0} tone="green"/><Stat icon={IndianRupee} label="Rewards issued" value={'₹'+Number(stats?.rewards_issued||0).toFixed(2)} tone="dark"/></div><section className="admin-section"><div className="section-head"><div><span className="eyebrow">ACCESS</span><h3>Activation queue</h3></div><span className="section-status"><span className="live-dot"/>Live</span></div>{busy?<div className="card admin-empty">Loading control-center data…</div>:rows.length===0?<div className="card admin-empty"><UserCheck size={28}/><h3>No pending applications</h3><p>New applications will appear here automatically.</p></div>:<div className="admin-list">{rows.map(r=><div className="card admin-row" key={r.id}><div className="applicant"><div className="avatar">{(r.name||'?').slice(0,1).toUpperCase()}</div><div><span className="eyebrow">{new Date(r.created_at).toLocaleString()}</span><h3>{r.name}</h3><p>{r.phone}</p></div></div><div className="admin-row-actions"><button className="approve" onClick={()=>decide(r.id,'approved')}><Check size={16}/> Approve</button><button className="reject" onClick={()=>decide(r.id,'rejected')}><X size={16}/> Reject</button></div></div>)}</div>}</section><section className="admin-pipeline"><div className="pipeline-icon"><Activity size={20}/></div><div><span className="eyebrow">TASK PIPELINE</span><h3>{Number(stats?.active_tasks||0)>0?'Tasks are available to users.':'No verified task inventory yet.'}</h3><p>{Number(stats?.active_tasks||0)>0?'The Get next task flow has an active supply to draw from.':'This is why an approved user currently sees the dashboard instead of a task. The next build step is the licensed ingestion worker that imports, validates, deduplicates, and publishes tasks.'}</p></div></section></main></Shell>}
function Stat({icon:Icon,label,value,tone}){return <div className={'card stat-card '+tone}><div className="stat-icon"><Icon size={18}/></div><span>{label}</span><strong>{value}</strong></div>}

createRoot(document.getElementById('root')).render(<App/>);

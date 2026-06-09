// tasks.jsx — Tasks redesign (request #4) + shared task UI used by People/Meetings.
// Two variants: A = unified Smart List (grouped by when, with a Triage inbox on top),
//               B = unified Board with a dedicated Triage lane for meeting-extracted tasks.
// Both fold projects+initiatives into ONE view instead of separate database views.

/* ---- shared presentational helpers (exported) ---- */
function PriorityBadge({ p }){
  const def = PRIORITY[p]; if(!def || p==='low') return null;
  return <span className={'badge '+def.cls}>{def.icon&&<Icon name={def.icon} size={11}/>}{def.label}</span>;
}
function DueBadge({ due, overdue }){
  if(!due) return null;
  return <span className={'badge '+(overdue?'t-danger':'t-warn')}><Icon name="clock" size={11}/>{overdue?'Overdue':due}</span>;
}
function MeetingLink({ id, onOpen }){
  const m = meetingById(id); if(!m) return null;
  return (
    <button className="badge t-iris" style={{ cursor:'pointer', border:'none' }} onClick={(e)=>{e.stopPropagation(); onOpen&&onOpen(id);}} title={'From: '+m.title}>
      <Icon name="meetings" size={11}/>{m.title.length>22?m.title.slice(0,22)+'…':m.title}
    </button>
  );
}
function OwnerAvatar({ owner, size=21 }){
  if(!owner) return null;
  if(owner==='me') return <div className="av" style={{ width:size, height:size, fontSize:size*0.4, background:'var(--surface-3)', color:'var(--txt-2)' }}>me</div>;
  const p=personById(owner); if(!p) return null;
  return <Avatar name={p.name} size={size} grad={p.grad}/>;
}

function TaskCheckbox({ done, onToggle, accent }){
  return (
    <button onClick={(e)=>{e.stopPropagation(); onToggle&&onToggle();}}
      style={{ width:18, height:18, borderRadius:6, flex:'0 0 auto', cursor:'pointer', display:'grid', placeItems:'center',
        border: done?'none':'1.5px solid var(--line-2)', background: done?(accent||'var(--ok)'):'transparent', marginTop:1 }}>
      {done && <Icon name="check" size={12} color="#0e1a14" style={{ strokeWidth:3 }}/>}
    </button>
  );
}

// A full task row used in list views, person tabs, etc.
function TaskRow({ t, onToggle, onOpenMeeting, onOpenPerson, showProject=true, showMeeting=true }){
  const done = t.status==='done';
  const proj = PROJECTS.find(p=>p.name===t.project);
  return (
    <div className="card hover" style={{ padding:'11px 13px', opacity: done?0.62:1 }}>
      <div className="row" style={{ alignItems:'flex-start', gap:11 }}>
        <TaskCheckbox done={done} onToggle={onToggle} accent="var(--ok)"/>
        <div style={{ flex:1, minWidth:0 }}>
          <div style={{ fontSize:13.5, fontWeight:600, lineHeight:1.4, textDecoration: done?'line-through':'none', color: done?'var(--txt-2)':'var(--txt)' }}>{t.title}</div>
          <div className="row" style={{ gap:6, marginTop:8, flexWrap:'wrap' }}>
            {!done && <PriorityBadge p={t.priority}/>}
            {!done && t.due && <DueBadge due={t.due} overdue={t.due==='Overdue'}/>}
            {done && <span className="badge t-ok"><Icon name="check" size={11}/>Done</span>}
            {showProject && proj && <span className="chip t-gray" style={{ fontSize:10.5, padding:'2px 8px' }}><span className="dot" style={{ background:proj.color, width:6, height:6 }}/>{proj.name}</span>}
            {showMeeting && t.meeting && <MeetingLink id={t.meeting} onOpen={onOpenMeeting}/>}
          </div>
        </div>
        {t.owner && t.owner!=='me' ? (
          <button onClick={(e)=>{e.stopPropagation(); onOpenPerson&&onOpenPerson(t.owner);}} style={{ border:'none', background:'transparent', cursor:'pointer', padding:0 }} title={personById(t.owner)?.name}>
            <OwnerAvatar owner={t.owner}/>
          </button>
        ) : <OwnerAvatar owner={t.owner}/>}
      </div>
    </div>
  );
}

/* ---------------- the Tasks page ---------------- */
function TasksView({ variant, route, onOpenMeeting, onOpenPerson }){
  const [tasks,setTasks] = React.useState(()=>TASKS.map(t=>({...t})));
  const [view,setView] = React.useState('smart'); // smart | board | calendar
  const [smartView,setSmartView] = React.useState('all'); // all | today | week | overdue | inbox | project ids

  React.useEffect(()=>{ setView(variant==='B'?'board':'smart'); },[variant]);

  const inbox = tasks.filter(t=>t.fromMeeting && !t.confirmed);
  const confirmed = tasks.filter(t=>t.confirmed);

  const toggle = (id)=> setTasks(ts=>ts.map(t=>t.id===id?{...t, status: t.status==='done'?'open':'done'}:t));
  const acceptInbox = (id, project)=> setTasks(ts=>ts.map(t=>t.id===id?{...t, confirmed:true, project: project||t.project}:t));
  const dismissInbox = (id)=> setTasks(ts=>ts.filter(t=>t.id!==id));

  /* sub-nav */
  const counts = {
    all: confirmed.filter(t=>t.status!=='done').length,
    today: confirmed.filter(t=>['Today','Wed'].includes(t.due) && t.status!=='done').length,
    week: confirmed.filter(t=>t.due && t.status!=='done').length,
    overdue: confirmed.filter(t=>t.due==='Overdue').length,
    inbox: inbox.length,
  };
  const SmartItem = ({ id, label, icon, color, count, danger })=>(
    <button className={'subnav-it'+(smartView===id?' on':'')} onClick={()=>setSmartView(id)}>
      <Icon name={icon} size={15} color={smartView===id?'var(--accent)':(color||'currentColor')}/>
      <span style={{ flex:1, textAlign:'left' }}>{label}</span>
      {count>0 && <span className={'badge '+(danger?'t-danger':'t-gray')} style={{ fontSize:10 }}>{count}</span>}
    </button>
  );

  return (
    <div className="main" style={{ flexDirection:'row' }}>
      {/* unified sub-nav: smart views + projects + initiatives in one place */}
      <div className="tasks-subnav">
        <div className="eyebrow" style={{ padding:'2px 8px 7px' }}>Workspace</div>
        <SmartItem id="inbox" label="Triage inbox" icon="inbox" count={counts.inbox} danger/>
        <SmartItem id="all" label="All tasks" icon="layers" count={counts.all}/>
        <SmartItem id="today" label="My day" icon="today" count={counts.today}/>
        <SmartItem id="week" label="This week" icon="calendar" count={counts.week}/>
        <SmartItem id="overdue" label="Overdue" icon="alert" color="var(--danger)" count={counts.overdue} danger/>
        <div className="eyebrow" style={{ padding:'16px 8px 7px' }}>Projects</div>
        {PROJECTS.map(p=>(
          <button key={p.id} className={'subnav-it'+(smartView===p.id?' on':'')} onClick={()=>setSmartView(p.id)}>
            <span className="dot" style={{ background:p.color }}/><span style={{ flex:1, textAlign:'left' }}>{p.name}</span>
            <span className="faint" style={{ fontSize:11 }}>{confirmed.filter(t=>t.project===p.name && t.status!=='done').length}</span>
          </button>
        ))}
        <div className="eyebrow" style={{ padding:'16px 8px 7px' }}>Initiatives</div>
        {INITIATIVES.map(i=>(
          <button key={i.id} className="subnav-it"><Icon name="layers" size={15}/><span style={{ flex:1, textAlign:'left' }}>{i.name}</span></button>
        ))}
      </div>

      {/* main */}
      <div style={{ flex:1, minWidth:0, display:'flex', flexDirection:'column' }}>
        <div className="row" style={{ padding:'16px 24px 14px', justifyContent:'space-between', borderBottom:'1px solid var(--line)' }}>
          <div className="row" style={{ gap:12 }}>
            <h1 style={{ fontSize:21, fontWeight:800, letterSpacing:'-.5px' }}>{smartLabel(smartView)}</h1>
            <span className="faint" style={{ fontSize:12.5 }}>{confirmed.filter(t=>t.status!=='done').length} open · {inbox.length} to triage</span>
          </div>
          <div className="vseg">
            <button className={view==='smart'?'on':''} onClick={()=>setView('smart')}><Icon name="list" size={14}/> List</button>
            <button className={view==='board'?'on':''} onClick={()=>setView('board')}><Icon name="board" size={14}/> Board</button>
            <button className={view==='calendar'?'on':''} onClick={()=>setView('calendar')}><Icon name="calendar" size={14}/> Calendar</button>
          </div>
        </div>

        <div className="scroll" style={{ padding:'18px 24px 28px' }}>
          {view==='board'
            ? <TaskBoard tasks={confirmed} inbox={inbox} smartView={smartView}
                onToggle={toggle} acceptInbox={acceptInbox} dismissInbox={dismissInbox}
                onOpenMeeting={onOpenMeeting} onOpenPerson={onOpenPerson}/>
            : view==='calendar'
            ? <TaskCalendar tasks={confirmed}/>
            : <TaskSmartList tasks={confirmed} inbox={inbox} smartView={smartView}
                onToggle={toggle} acceptInbox={acceptInbox} dismissInbox={dismissInbox}
                onOpenMeeting={onOpenMeeting} onOpenPerson={onOpenPerson}/>}
        </div>
      </div>
    </div>
  );
}

function smartLabel(v){
  const map={ all:'All tasks', today:'My day', week:'This week', overdue:'Overdue', inbox:'Triage inbox' };
  if(map[v]) return map[v];
  const p=PROJECTS.find(p=>p.id===v); return p?p.name:'Tasks';
}

/* ---- Triage inbox card (meeting-extracted action items awaiting confirm) ---- */
function TriageCard({ items, acceptInbox, dismissInbox, onOpenMeeting }){
  if(items.length===0) return null;
  return (
    <div className="card anim-in" style={{ padding:0, marginBottom:20, borderColor:'rgba(255,145,115,.32)', overflow:'hidden' }}>
      <div className="row" style={{ padding:'12px 16px', background:'linear-gradient(135deg, rgba(255,145,115,.16), rgba(183,156,255,.12))' }}>
        <Icon name="inbox" size={16} color="var(--accent)"/>
        <b style={{ fontSize:13.5 }}>From your meetings</b>
        <span className="badge t-coral" style={{ marginLeft:8 }}>{items.length} to triage</span>
        <span className="faint" style={{ marginLeft:'auto', fontSize:11.5 }}>Confirm to add · pick a project</span>
      </div>
      <div className="col" style={{ padding:'8px 12px 12px', gap:8 }}>
        {items.map(t=>(
          <div key={t.id} className="row" style={{ alignItems:'flex-start', gap:11, padding:'9px 10px', borderRadius:11, background:'var(--surface-2)' }}>
            <Icon name="sparkles" size={15} color="var(--accent)" style={{ marginTop:2, flex:'0 0 auto' }}/>
            <div style={{ flex:1, minWidth:0 }}>
              <div style={{ fontSize:13, fontWeight:600 }}>{t.title}</div>
              <div className="row" style={{ gap:6, marginTop:6, flexWrap:'wrap' }}>
                <MeetingLink id={t.meeting} onOpen={onOpenMeeting}/>
                {t.due && <DueBadge due={t.due}/>}
                {t.owner && <span className="chip t-gray" style={{ fontSize:10.5, padding:'2px 8px' }}><OwnerAvatar owner={t.owner} size={14}/>{t.owner==='me'?'You':personById(t.owner)?.name.split(' ')[0]}</span>}
              </div>
            </div>
            <div className="row" style={{ gap:6, flex:'0 0 auto' }}>
              <ProjectAssign onPick={(proj)=>acceptInbox(t.id, proj)}/>
              <button className="btn primary xs" onClick={()=>acceptInbox(t.id)}><Icon name="check" size={12}/> Add</button>
              <button className="iconbtn" style={{ width:28, height:28 }} onClick={()=>dismissInbox(t.id)} title="Dismiss"><Icon name="trash" size={13} color="var(--txt-3)"/></button>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
function ProjectAssign({ onPick }){
  const [open,setOpen]=React.useState(false);
  return (
    <div style={{ position:'relative' }}>
      <button className="btn secondary xs" onClick={()=>setOpen(o=>!o)}><Icon name="layers" size={12}/> Project</button>
      {open && (<>
        <div className="pop-overlay" onClick={()=>setOpen(false)}/>
        <div className="pop anim-in" style={{ top:'110%', right:0, width:190 }}>
          <div className="eyebrow" style={{ marginBottom:7 }}>Add to project</div>
          {PROJECTS.map(p=>(
            <button key={p.id} className="seg-opt" style={{ width:'100%' }} onClick={()=>{onPick(p.name); setOpen(false);}}>
              <span className="dot" style={{ background:p.color }}/>{p.name}
            </button>
          ))}
        </div>
      </>)}
    </div>
  );
}

/* ---- Smart list: groups by when, mixing all projects ---- */
function TaskSmartList({ tasks, inbox, smartView, onToggle, acceptInbox, dismissInbox, onOpenMeeting, onOpenPerson }){
  let list = tasks;
  if(smartView==='today') list = tasks.filter(t=>['Today','Wed'].includes(t.due));
  else if(smartView==='week') list = tasks.filter(t=>t.due);
  else if(smartView==='overdue') list = tasks.filter(t=>t.due==='Overdue');
  else if(PROJECTS.find(p=>p.id===smartView)) list = tasks.filter(t=>t.project===PROJECTS.find(p=>p.id===smartView).name);

  const groups = [
    { key:'doing', label:'In progress', items:list.filter(t=>t.status==='doing') },
    { key:'open',  label:'To do', items:list.filter(t=>t.status==='open') },
    { key:'done',  label:'Completed', items:list.filter(t=>t.status==='done') },
  ].filter(g=>g.items.length);

  return (
    <div style={{ maxWidth:760 }}>
      {(smartView==='inbox' || smartView==='all') && <TriageCard items={inbox} acceptInbox={acceptInbox} dismissInbox={dismissInbox} onOpenMeeting={onOpenMeeting}/>}
      {smartView==='inbox' && inbox.length===0 && <Empty icon="inbox" text="Triage inbox is clear — new action items from meetings will land here."/>}
      {smartView!=='inbox' && groups.map(g=>(
        <div key={g.key} style={{ marginBottom:20 }}>
          <div className="row" style={{ marginBottom:9, gap:8 }}>
            <span className="dot" style={{ background:STATUS[g.key].dot }}/>
            <b style={{ fontSize:13 }}>{g.label}</b>
            <span className="faint" style={{ fontSize:11.5 }}>{g.items.length}</span>
          </div>
          <div className="col" style={{ gap:8 }}>
            {g.items.map(t=>(
              <TaskRow key={t.id} t={t} onToggle={()=>onToggle(t.id)} onOpenMeeting={onOpenMeeting} onOpenPerson={onOpenPerson} showProject={!PROJECTS.find(p=>p.id===smartView)}/>
            ))}
          </div>
        </div>
      ))}
      {smartView!=='inbox' && groups.length===0 && <Empty icon="tasks" text="Nothing here yet."/>}
    </div>
  );
}

/* ---- Board with a Triage lane for meeting-extracted tasks ---- */
function TaskBoard({ tasks, inbox, smartView, onToggle, acceptInbox, dismissInbox, onOpenMeeting, onOpenPerson }){
  let list = tasks;
  if(PROJECTS.find(p=>p.id===smartView)) list = tasks.filter(t=>t.project===PROJECTS.find(p=>p.id===smartView).name);
  const lanes = [
    { key:'inbox', label:'Triage', dot:'var(--accent)', items:inbox, triage:true },
    { key:'open', label:'To do', dot:STATUS.open.dot, items:list.filter(t=>t.status==='open') },
    { key:'doing', label:'In progress', dot:STATUS.doing.dot, items:list.filter(t=>t.status==='doing') },
    { key:'done', label:'Completed', dot:STATUS.done.dot, items:list.filter(t=>t.status==='done') },
  ];
  return (
    <div style={{ display:'flex', gap:14, alignItems:'flex-start' }}>
      {lanes.map(l=>(
        <div key={l.key} className="kanban-lane" style={ l.triage?{ borderColor:'rgba(255,145,115,.28)', background:'rgba(255,145,115,.05)' }:{} }>
          <div className="row" style={{ padding:'3px 6px 8px' }}>
            <span className="dot" style={{ background:l.dot }}/>
            <b style={{ fontSize:12.5 }}>{l.label}</b>
            <span className="faint" style={{ fontSize:11 }}>{l.items.length}</span>
          </div>
          <div className="col" style={{ gap:8 }}>
            {l.items.map(t=> l.triage
              ? <TriageMiniCard key={t.id} t={t} accept={()=>acceptInbox(t.id)} dismiss={()=>dismissInbox(t.id)} onOpenMeeting={onOpenMeeting}/>
              : <BoardCard key={t.id} t={t} onToggle={()=>onToggle(t.id)} onOpenMeeting={onOpenMeeting} onOpenPerson={onOpenPerson}/>)}
            {l.items.length===0 && <div className="faint" style={{ fontSize:11.5, padding:'10px 6px' }}>{l.triage?'All triaged ✓':'—'}</div>}
          </div>
        </div>
      ))}
    </div>
  );
}
function BoardCard({ t, onToggle, onOpenMeeting, onOpenPerson }){
  const done=t.status==='done';
  const bar=PRIORITY[t.priority]?.bar;
  return (
    <div className="card hover" style={{ padding:'11px 12px 11px 13px', position:'relative', overflow:'hidden', opacity:done?0.62:1 }}>
      {bar && bar!=='transparent' && <span style={{ position:'absolute', left:0, top:0, bottom:0, width:3, background:bar }}/>}
      <div className="row" style={{ gap:8, marginBottom: (t.project)?7:0 }}>
        {t.project && <span className="chip t-gray" style={{ fontSize:10, padding:'2px 7px' }}>{t.project}</span>}
        {t.meeting && <MeetingLink id={t.meeting} onOpen={onOpenMeeting}/>}
      </div>
      <div className="row" style={{ alignItems:'flex-start', gap:9 }}>
        <TaskCheckbox done={done} onToggle={onToggle}/>
        <div style={{ flex:1, fontSize:13, fontWeight:600, lineHeight:1.4, textDecoration:done?'line-through':'none', color:done?'var(--txt-2)':'var(--txt)' }}>{t.title}</div>
      </div>
      <div className="row" style={{ marginTop:10, gap:7 }}>
        {!done && <PriorityBadge p={t.priority}/>}
        {!done && t.due && <DueBadge due={t.due}/>}
        {done && <span className="badge t-ok"><Icon name="check" size={11}/>Done</span>}
        <span style={{ marginLeft:'auto' }}><OwnerAvatar owner={t.owner}/></span>
      </div>
    </div>
  );
}
function TriageMiniCard({ t, accept, dismiss, onOpenMeeting }){
  return (
    <div className="card" style={{ padding:'11px 12px', borderColor:'rgba(255,145,115,.22)' }}>
      <div className="row" style={{ gap:7, marginBottom:7 }}><Icon name="sparkles" size={13} color="var(--accent)"/><MeetingLink id={t.meeting} onOpen={onOpenMeeting}/></div>
      <div style={{ fontSize:13, fontWeight:600, lineHeight:1.4 }}>{t.title}</div>
      <div className="row" style={{ marginTop:9, gap:6 }}>
        {t.due && <DueBadge due={t.due}/>}
        <OwnerAvatar owner={t.owner}/>
        <div className="row" style={{ gap:5, marginLeft:'auto' }}>
          <button className="btn primary xs" onClick={accept}><Icon name="check" size={11}/></button>
          <button className="iconbtn" style={{ width:24, height:24 }} onClick={dismiss}><Icon name="trash" size={11} color="var(--txt-3)"/></button>
        </div>
      </div>
    </div>
  );
}

function TaskCalendar({ tasks }){
  const days=['Mon','Tue','Wed','Thu','Fri'];
  return (
    <div style={{ display:'grid', gridTemplateColumns:'repeat(5,1fr)', gap:12, maxWidth:980 }}>
      {days.map(d=>(
        <div key={d} className="card" style={{ padding:12, minHeight:200 }}>
          <div className="row" style={{ marginBottom:10 }}><b style={{ fontSize:12.5 }}>{d}</b><span className="faint" style={{ fontSize:11, marginLeft:'auto' }}>Jun {9+days.indexOf(d)}</span></div>
          <div className="col" style={{ gap:7 }}>
            {tasks.filter(t=>t.due===d).map(t=>(
              <div key={t.id} className="card" style={{ padding:'8px 10px', background:'var(--surface-2)', borderColor:'transparent' }}>
                <div style={{ fontSize:11.5, fontWeight:600, lineHeight:1.35 }}>{t.title}</div>
                <div className="row" style={{ gap:5, marginTop:6 }}><PriorityBadge p={t.priority}/><span style={{ marginLeft:'auto' }}><OwnerAvatar owner={t.owner} size={16}/></span></div>
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}

function Empty({ icon, text }){
  return (
    <div className="col" style={{ alignItems:'center', justifyContent:'center', padding:'48px 20px', textAlign:'center', gap:10 }}>
      <div style={{ width:52, height:52, borderRadius:16, background:'var(--surface-2)', display:'grid', placeItems:'center' }}><Icon name={icon} size={22} color="var(--txt-3)"/></div>
      <div className="faint" style={{ fontSize:13, maxWidth:300 }}>{text}</div>
    </div>
  );
}

Object.assign(window, { TasksView, TaskRow, PriorityBadge, DueBadge, MeetingLink, OwnerAvatar, TaskCheckbox, Empty });

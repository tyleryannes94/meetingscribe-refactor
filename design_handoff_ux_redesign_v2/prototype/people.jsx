// people.jsx — People redesign (request #3).
// Two-pane layout: identity/contact/summary fixed left → tabbed work area right.
// Tabs: Overview · Meetings · Tasks · Messages · Notes
// Full "Analyze…" popover with timeframe + preset (not just all-time).
// Variant A = spacious identity left (~290px) + full-width tabs.
// Variant B = compact identity left (~240px) + wider content.

const TABS_PERSON = ['overview','meetings','tasks','messages','notes'];
const TAB_LABELS = { overview:'Overview', meetings:'Meetings', tasks:'Tasks', messages:'Messages', notes:'Notes' };
const TAB_ICONS  = { overview:'today', meetings:'meetings', tasks:'tasks', messages:'chat', notes:'doc' };

/* ---------- Analysis Popover (Analyze… button) ---------- */
const PRESETS = [
  { id:'relationshipSummary', label:'Relationship summary', icon:'heart' },
  { id:'sentimentTrends',     label:'Sentiment & trends',  icon:'trend' },
  { id:'topicsThemes',        label:'Topics & themes',     icon:'tag'   },
  { id:'communicationStyle',  label:'Communication style', icon:'chat'  },
  { id:'actionItems',         label:'Pending action items',icon:'tasks' },
  { id:'custom',              label:'Custom prompt…',      icon:'edit'  },
];
const SCOPES = [
  { id:'last30',  label:'Last 30 days' },
  { id:'last90',  label:'Last 90 days' },
  { id:'last6mo', label:'Last 6 months' },
  { id:'year',    label:'This year' },
  { id:'recent1000', label:'Recent 1000' },
  { id:'allTime', label:'All time' },
];

function AnalyzePopover({ onClose, onRun }){
  const [preset,setPreset]=React.useState('relationshipSummary');
  const [scope,setScope]=React.useState('last90');
  const [custom,setCustom]=React.useState('');
  return (
    <div className="pop anim-in" style={{ width:320, right:0, top:'110%' }}>
      <div className="row" style={{ marginBottom:12, justifyContent:'space-between' }}>
        <b style={{ fontSize:13.5 }}>Analyze messages</b>
        <button className="iconbtn" style={{ width:22, height:22 }} onClick={onClose}><Icon name="chevR" size={13} color="var(--txt-3)"/></button>
      </div>
      <div className="eyebrow" style={{ marginBottom:7 }}>What to analyze</div>
      <div className="col" style={{ gap:5 }}>
        {PRESETS.map(p=>(
          <button key={p.id} className={'seg-opt'+(preset===p.id?' on':'')} onClick={()=>setPreset(p.id)}>
            <Icon name={p.icon} size={15}/>{p.label}
            {preset===p.id&&<Icon name="check" size={13} style={{ marginLeft:'auto' }} color="var(--accent)"/>}
          </button>
        ))}
      </div>
      {preset==='custom' && (
        <textarea value={custom} onChange={e=>setCustom(e.target.value)} placeholder="Describe what you want to know…"
          style={{ width:'100%', marginTop:10, background:'var(--surface-2)', border:'1px solid var(--line)', borderRadius:10,
            color:'var(--txt)', padding:'9px 11px', fontSize:12.5, resize:'vertical', minHeight:68, fontFamily:'inherit', outline:'none' }}/>
      )}
      <div className="eyebrow" style={{ margin:'14px 0 7px' }}>Time range</div>
      <div style={{ display:'flex', flexWrap:'wrap', gap:6 }}>
        {SCOPES.map(s=>(
          <button key={s.id} className={'minichip'+(scope===s.id?' on':'')} onClick={()=>setScope(s.id)}>{s.label}</button>
        ))}
      </div>
      <button className="btn primary block" style={{ marginTop:14, padding:'10px' }}
        onClick={()=>{ onRun(preset, scope, custom); onClose(); }}>
        <Icon name="sparkles" size={14}/> Run analysis
      </button>
    </div>
  );
}

/* ---------- Add-email mini popover ---------- */
function AddEmailPopover({ onAdd, onClose }){
  const [val,setVal]=React.useState('');
  return (
    <div className="pop anim-in" style={{ width:260, top:'110%', left:0, padding:12 }}>
      <b style={{ fontSize:12.5, display:'block', marginBottom:8 }}>Add email address</b>
      <div className="field" style={{ padding:'7px 10px' }}>
        <input value={val} onChange={e=>setVal(e.target.value)} placeholder="name@example.com" autoFocus
          onKeyDown={e=>{ if(e.key==='Enter'&&val.trim()){ onAdd(val.trim()); onClose(); }}}/>
      </div>
      <div className="row" style={{ gap:7, marginTop:9 }}>
        <button className="btn primary xs" style={{ flex:1 }} onClick={()=>{ if(val.trim()){ onAdd(val.trim()); onClose(); }}}>Add</button>
        <button className="btn ghost xs" onClick={onClose}>Cancel</button>
      </div>
    </div>
  );
}

/* ---------- Person detail — left pane ---------- */
function PersonLeft({ person, onEdit, variant }){
  const [showAddEmail,setShowAddEmail]=React.useState(false);
  const [emails,setEmails]=React.useState(person.emails||[]);
  const cadenceColor = { Healthy:'var(--ok)', Slipping:'var(--warn)', 'At risk':'var(--danger)', New:'var(--info)' }[person.cadence]||'var(--info)';
  const narrow = variant==='B';

  return (
    <div style={{ width: narrow?240:288, flex:'0 0 auto', borderRight:'1px solid var(--line)',
      background:'var(--bg)', display:'flex', flexDirection:'column', overflowY:'auto' }}>
      <div style={{ padding: narrow?'18px 16px':'22px 18px', borderBottom:'1px solid var(--line)' }}>
        <Avatar name={person.name} size={narrow?54:64} grad={person.grad} radius="18px" style={{ marginBottom:12 }}/>
        <h1 style={{ fontSize: narrow?17:20, fontWeight:800, letterSpacing:'-.4px', marginBottom:3 }}>{person.name}</h1>
        <div className="muted" style={{ fontSize:12.5 }}>{person.role} · {person.company}</div>
        <div className="row" style={{ gap:5, marginTop:9, flexWrap:'wrap' }}>
          {person.tags?.map(t=>(
            <span key={t} className="chip t-gray" style={{ fontSize:10.5, padding:'3px 9px' }}>{t}</span>
          ))}
        </div>
        {/* Cadence nudge if slipping/at risk */}
        {person.cadence!=='Healthy' && person.cadence!=='New' && (
          <div className="card" style={{ padding:'9px 12px', marginTop:12, borderColor:'rgba(255,206,107,.28)' }}>
            <div className="row" style={{ gap:7 }}>
              <Icon name="clock" size={14} color="var(--warn)"/>
              <span style={{ fontSize:11.5, flex:1 }}>Last spoke <b>{person.lastSpokeDays}d ago</b> · usually every {person.cadenceDays}d</span>
            </div>
            <button className="btn primary xs" style={{ marginTop:7, width:'100%' }}>Reconnect</button>
          </div>
        )}
        {/* Quick actions */}
        <div className="row" style={{ gap:6, marginTop:12, flexWrap:'wrap' }}>
          <button className="btn secondary xs"><Icon name="calendar" size={12}/> Log encounter</button>
          <button className="btn secondary xs"><Icon name="sparkles" size={12}/> Suggest</button>
        </div>
      </div>

      {/* Contact info */}
      <div style={{ padding:'14px 18px', borderBottom:'1px solid var(--line)' }}>
        <div className="eyebrow" style={{ marginBottom:9 }}>Contact</div>
        <div className="col" style={{ gap:8 }}>
          {/* Email rows with + add inline */}
          {emails.map((e,i)=>(
            <div key={i} className="row" style={{ gap:8, fontSize:12.5 }}>
              <Icon name="mail" size={13} color="var(--txt-3)" style={{ flex:'0 0 auto' }}/>
              <a href={'mailto:'+e} style={{ color:'var(--lilac)', textDecoration:'none', flex:1, overflow:'hidden', textOverflow:'ellipsis', whiteSpace:'nowrap' }}>{e}</a>
              {i===0 && <span className="badge t-gray" style={{ fontSize:9.5, padding:'1px 5px' }}>primary</span>}
            </div>
          ))}
          {/* Add email button */}
          <div style={{ position:'relative' }}>
            <button className="row" style={{ gap:7, fontSize:12, color:'var(--txt-3)', background:'transparent', border:'none', cursor:'pointer', padding:0 }} onClick={()=>setShowAddEmail(o=>!o)}>
              <Icon name="plus" size={13}/> Add email
            </button>
            {showAddEmail && (<>
              <div className="pop-overlay" onClick={()=>setShowAddEmail(false)}/>
              <AddEmailPopover onAdd={e=>setEmails(em=>[...em,e])} onClose={()=>setShowAddEmail(false)}/>
            </>)}
          </div>
          {person.phone && (
            <div className="row" style={{ gap:8, fontSize:12.5 }}>
              <Icon name="phone" size={13} color="var(--txt-3)" style={{ flex:'0 0 auto' }}/>
              <span>{person.phone}</span>
            </div>
          )}
          {person.location && (
            <div className="row" style={{ gap:8, fontSize:12.5 }}>
              <Icon name="map" size={13} color="var(--txt-3)" style={{ flex:'0 0 auto' }}/>
              <span className="muted">{person.location}</span>
            </div>
          )}
          {person.birthday && (
            <div className="row" style={{ gap:8, fontSize:12.5 }}>
              <Icon name="gift" size={13} color="var(--txt-3)" style={{ flex:'0 0 auto' }}/>
              <span className="muted">{person.birthday}</span>
            </div>
          )}
          <div className="row" style={{ gap:8, fontSize:12.5 }}>
            <Icon name="clock" size={13} color="var(--txt-3)" style={{ flex:'0 0 auto' }}/>
            <span className="muted">First met {person.firstMet}</span>
          </div>
        </div>
      </div>

      {/* Relationship cadence */}
      <div style={{ padding:'14px 18px' }}>
        <div className="eyebrow" style={{ marginBottom:9 }}>Cadence</div>
        <div className="row" style={{ gap:8, fontSize:12.5 }}>
          <span className="badge" style={{ background: cadenceColor+'28', color: cadenceColor }}>{person.cadence}</span>
          <span className="muted">every ~{person.cadenceDays}d</span>
        </div>
        {/* encounter heatmap (mini) */}
        <div style={{ marginTop:10, display:'flex', gap:3, flexWrap:'wrap' }}>
          {Array.from({length:13}).map((_,i)=>(
            <div key={i} style={{ width:16, height:16, borderRadius:5,
              background: i%3===0?'var(--accent)': i%4===0?'var(--accent-soft)':'var(--surface-2)',
              opacity: 0.6+i*0.03 }} title={`Week ${i+1}`}/>
          ))}
        </div>
        <div className="faint" style={{ fontSize:10.5, marginTop:6 }}>Last 13 weeks</div>
      </div>
    </div>
  );
}

/* ---------- Person detail — right pane with tabs ---------- */
function PersonRight({ person, onOpenMeeting, onOpenPerson }){
  const [tab,setTab]=React.useState('overview');
  const [analyzeOpen,setAnalyzeOpen]=React.useState(false);
  const [analysisResult,setAnalysisResult]=React.useState(null);

  const personMeetings = MEETINGS.filter(m=>m.attendees?.includes(person.id)||person.id==='maya');
  const personTasks = TASKS.filter(t=>t.confirmed && (t.owner===person.id || t.owner===person.name));

  const runAnalysis = (preset, scope, custom)=>{
    const label = PRESETS.find(p=>p.id===preset)?.label || preset;
    const scopeLabel = SCOPES.find(s=>s.id===scope)?.label || scope;
    setAnalysisResult({
      preset: label, scope: scopeLabel,
      text:`Analysis running locally via Ollama… Based on ${person.msg?.total||0} messages (${scopeLabel}): ${person.name} communicates primarily via email for decisions, Slack for async updates. Response cadence is ${person.msg?.replyMedian||'~4h'}, healthy. You initiate ${person.msg?.youInitiate||60}% of threads.`
    });
  };

  return (
    <div style={{ flex:1, minWidth:0, display:'flex', flexDirection:'column' }}>
      <div style={{ padding:'0 24px', borderBottom:'1px solid var(--line)', paddingTop:14 }}>
        <div className="tabbar" style={{ gap:2 }}>
          {TABS_PERSON.map(t=>(
            <button key={t} className={'tab'+(tab===t?' active':'')} onClick={()=>setTab(t)}>
              <Icon name={TAB_ICONS[t]} size={14}/>{TAB_LABELS[t]}
            </button>
          ))}
        </div>
      </div>
      <div className="scroll" style={{ padding:'20px 24px 28px' }}>
        {tab==='overview' && <PersonOverview person={person}/>}
        {tab==='meetings' && <PersonMeetings meetings={personMeetings} person={person} onOpenMeeting={onOpenMeeting}/>}
        {tab==='tasks' && <PersonTasks person={person} onOpenMeeting={onOpenMeeting}/>}
        {tab==='messages' && (
          <PersonMessages person={person} analyzeOpen={analyzeOpen}
            setAnalyzeOpen={setAnalyzeOpen} onRun={runAnalysis} result={analysisResult}/>
        )}
        {tab==='notes' && <PersonNotes person={person}/>}
      </div>
    </div>
  );
}

function PersonOverview({ person }){
  return (
    <div style={{ maxWidth:640 }}>
      {/* Memories */}
      <div style={{ marginBottom:22 }}>
        <div className="row" style={{ marginBottom:10, justifyContent:'space-between' }}>
          <div className="eyebrow">Memories</div>
          <button className="btn ghost xs"><Icon name="plus" size={12}/> Add</button>
        </div>
        <div className="col" style={{ gap:8 }}>
          {person.memories?.map((m,i)=>(
            <div key={i} className="card hover" style={{ padding:'10px 13px', fontSize:13, lineHeight:1.5 }}>{m}</div>
          ))}
        </div>
      </div>
      {/* Favorites */}
      <div style={{ marginBottom:22 }}>
        <div className="row" style={{ marginBottom:10, justifyContent:'space-between' }}>
          <div className="eyebrow">Favorite things</div>
          <button className="btn ghost xs"><Icon name="plus" size={12}/> Add</button>
        </div>
        <div className="row" style={{ gap:6, flexWrap:'wrap' }}>
          {(person.favorites||['(none yet)']).map((f,i)=>(
            <span key={i} className="chip t-gray"><Icon name="heart" size={11}/>{f}</span>
          ))}
        </div>
      </div>
      {/* AI suggestions */}
      <div>
        <div className="row" style={{ marginBottom:10, justifyContent:'space-between' }}>
          <div className="eyebrow">AI suggestions</div>
          <button className="btn secondary xs"><Icon name="sparkles" size={12}/> Refresh</button>
        </div>
        <div className="card" style={{ padding:'13px 15px' }}>
          <div className="muted" style={{ fontSize:12.5 }}>Let AI propose tags, relationships, and encounters from this person's meetings and profile.</div>
          <button className="btn primary xs" style={{ marginTop:10 }}><Icon name="sparkles" size={12}/> Generate suggestions</button>
        </div>
      </div>
    </div>
  );
}

function PersonMeetings({ meetings, person, onOpenMeeting }){
  return (
    <div style={{ maxWidth:640 }}>
      <div className="row" style={{ marginBottom:14, justifyContent:'space-between' }}>
        <div className="eyebrow">{meetings.length} shared meetings</div>
        <button className="btn secondary xs"><Icon name="plus" size={12}/> Add {person.name.split(' ')[0]} to a meeting</button>
      </div>
      <div className="col" style={{ gap:9 }}>
        {meetings.map(m=>(
          <div key={m.id} className="card click hover" style={{ padding:'11px 14px' }} onClick={()=>onOpenMeeting&&onOpenMeeting(m.id)}>
            <div className="row" style={{ gap:10 }}>
              <span className="dot" style={{ background: m.status==='recording'?'var(--danger)':m.status==='scheduled'?'var(--info)':'var(--ok)' }}/>
              <div style={{ flex:1, minWidth:0 }}>
                <div style={{ fontWeight:600, fontSize:13.5 }}>{m.title}</div>
                <div className="faint" style={{ fontSize:11.5, marginTop:2 }}>{m.date} · {m.dur} · {m.attendees?.length||0} attendees</div>
              </div>
              <div className="row" style={{ gap:6 }}>
                {m.tags?.slice(0,2).map(t=><span key={t} className="chip t-gray" style={{ fontSize:10.5, padding:'2px 8px' }}>{t}</span>)}
                {m.status==='summary' && <span className="badge t-ok"><Icon name="sparkles" size={11}/>Summary</span>}
                {m.status==='recording' && <span className="live"><span className="recdot"/>Live</span>}
              </div>
              <Icon name="chevR" size={15} color="var(--txt-3)"/>
            </div>
          </div>
        ))}
        {meetings.length===0 && <Empty icon="meetings" text="No shared meetings yet."/>}
      </div>
    </div>
  );
}

function PersonTasks({ person, onOpenMeeting }){
  const [tasks, setTasks] = React.useState(()=>
    TASKS.filter(t=>t.confirmed && (t.owner===person.id || t.owner===person.name)).map(t=>({...t}))
  );
  const toggle=(id)=>setTasks(ts=>ts.map(t=>t.id===id?{...t,status:t.status==='done'?'open':'done'}:t));
  return (
    <div style={{ maxWidth:640 }}>
      <div className="row" style={{ marginBottom:14, justifyContent:'space-between' }}>
        <div className="eyebrow">{tasks.filter(t=>t.status!=='done').length} open tasks</div>
        <button className="btn secondary xs"><Icon name="plus" size={12}/> New task for {person.name.split(' ')[0]}</button>
      </div>
      {tasks.length===0 ? <Empty icon="tasks" text="No tasks linked to this person yet." /> : (
        <div className="col" style={{ gap:8 }}>
          {tasks.map(t=><TaskRow key={t.id} t={t} onToggle={()=>toggle(t.id)} onOpenMeeting={onOpenMeeting} showProject/>)}
        </div>
      )}
    </div>
  );
}

function PersonMessages({ person, analyzeOpen, setAnalyzeOpen, onRun, result }){
  const m=person.msg;
  return (
    <div style={{ maxWidth:640 }}>
      {/* Stats overview */}
      <div className="card" style={{ padding:'16px 18px', marginBottom:18 }}>
        <div className="row" style={{ justifyContent:'space-between', marginBottom:16 }}>
          <div><div style={{ fontSize:26, fontWeight:800 }}>{m.total}</div><div className="faint" style={{ fontSize:11 }}>total messages</div></div>
          <div><div style={{ fontSize:26, fontWeight:800, color:'var(--accent)' }}>{m.replyMedian}</div><div className="faint" style={{ fontSize:11 }}>median reply</div></div>
          <div><div style={{ fontSize:26, fontWeight:800, color:'var(--ok)' }}>{m.youInitiate}%</div><div className="faint" style={{ fontSize:11 }}>you initiate</div></div>
          <div><div style={{ fontSize:26, fontWeight:800, color:'var(--lilac)' }}>{m.last30}</div><div className="faint" style={{ fontSize:11 }}>last 30d</div></div>
        </div>
        <div style={{ display:'flex', gap:3, height:36, alignItems:'flex-end' }}>
          {(m.bars||[]).map((h,i)=>(
            <div key={i} style={{ flex:1, borderRadius:3, height:h+'%',
              background: i===3?'var(--accent)':'var(--accent-soft)' }}/>
          ))}
        </div>
        <div className="faint" style={{ fontSize:10.5, marginTop:7 }}>Activity last 7 weeks</div>
      </div>

      {/* Analyze block */}
      <div>
        <div className="row" style={{ marginBottom:12, justifyContent:'space-between' }}>
          <div className="eyebrow">Analysis</div>
          <div style={{ position:'relative' }}>
            <button className="btn secondary xs" onClick={()=>setAnalyzeOpen(o=>!o)}>
              <Icon name="sparkles" size={12}/> Analyze…
            </button>
            {analyzeOpen && (<>
              <div className="pop-overlay" onClick={()=>setAnalyzeOpen(false)}/>
              <AnalyzePopover onClose={()=>setAnalyzeOpen(false)} onRun={onRun}/>
            </>)}
          </div>
        </div>
        {result ? (
          <div className="card anim-in" style={{ padding:'14px 16px' }}>
            <div className="row" style={{ gap:8, marginBottom:9 }}>
              <Icon name="sparkles" size={15} color="var(--lilac)"/>
              <b style={{ fontSize:13 }}>{result.preset}</b>
              <span className="badge t-gray" style={{ marginLeft:'auto' }}>{result.scope}</span>
            </div>
            <p style={{ fontSize:13, lineHeight:1.6, color:'var(--txt-2)' }}>{result.text}</p>
            <button className="btn ghost xs" style={{ marginTop:10 }}><Icon name="doc" size={12}/> Save to notes</button>
          </div>
        ) : (
          <div className="card" style={{ padding:'14px 16px' }}>
            <div className="muted" style={{ fontSize:12.5 }}>Choose a preset and time range to analyze {person.name.split(' ')[0]}'s communication patterns, sentiment, and topics.</div>
          </div>
        )}
      </div>
    </div>
  );
}

function PersonNotes({ person }){
  const [text,setText]=React.useState('');
  return (
    <div style={{ maxWidth:640 }}>
      <div className="row" style={{ marginBottom:14, justifyContent:'space-between' }}>
        <div className="eyebrow">Notes</div>
        <button className="btn secondary xs"><Icon name="plus" size={12}/> New note</button>
      </div>
      <textarea value={text} onChange={e=>setText(e.target.value)}
        placeholder={"Add a note about "+person.name+"…"}
        style={{ width:'100%', minHeight:120, background:'var(--surface)', border:'1px solid var(--line)',
          borderRadius:12, color:'var(--txt)', padding:'12px 14px', fontSize:13.5, lineHeight:1.6,
          fontFamily:'inherit', resize:'none', outline:'none', marginBottom:14 }}/>
      <div className="col" style={{ gap:9 }}>
        {person.memories?.map((m,i)=>(
          <div key={i} className="card hover" style={{ padding:'11px 14px', fontSize:13, lineHeight:1.5, position:'relative' }}>
            {m}
            <button className="iconbtn" style={{ position:'absolute', right:8, top:8, width:22, height:22 }}><Icon name="edit" size={12}/></button>
          </div>
        ))}
      </div>
    </div>
  );
}

/* ---------- The people list (left sidebar within the section) ---------- */
function PeopleList({ selected, onSelect }){
  const [q,setQ]=React.useState('');
  const [filter,setFilter]=React.useState('All');
  const filters=['All','Colleagues','Clients','Prospects'];
  const list = PEOPLE.filter(p=>{
    const mq=!q||p.name.toLowerCase().includes(q.toLowerCase())||p.company?.toLowerCase().includes(q.toLowerCase());
    const mf=filter==='All'||p.relationship===filter.slice(0,-1)||(filter==='Colleagues'&&p.relationship==='Colleague')||(filter==='Clients'&&p.relationship==='Client')||(filter==='Prospects'&&p.relationship==='Prospect');
    return mq&&mf;
  });
  return (
    <div style={{ width:288, flex:'0 0 auto', borderRight:'1px solid var(--line)', background:'var(--bg)', display:'flex', flexDirection:'column' }}>
      <div style={{ padding:'16px 14px 10px' }}>
        <div className="row" style={{ justifyContent:'space-between' }}>
          <h1 style={{ fontSize:19, fontWeight:700 }}>People</h1>
          <button className="btn primary sm"><Icon name="plus" size={14}/> Add</button>
        </div>
        <div className="field" style={{ marginTop:11, padding:'7px 11px' }}>
          <Icon name="search" size={15}/><input value={q} onChange={e=>setQ(e.target.value)} placeholder="Search name, company, role…"/>
        </div>
        <div className="row" style={{ gap:6, marginTop:10, flexWrap:'wrap' }}>
          {filters.map(f=>(
            <button key={f} className={'minichip'+(filter===f?' on':'')} onClick={()=>setFilter(f)}>{f}</button>
          ))}
        </div>
      </div>
      <div className="scroll" style={{ padding:'4px 9px 14px' }}>
        {list.map(p=>(
          <button key={p.id} onClick={()=>onSelect(p.id)}
            className="row" style={{ gap:11, padding:'9px 11px', borderRadius:10, cursor:'pointer', width:'100%',
              background: selected===p.id?'var(--accent-soft)':'transparent', border:'1px solid',
              borderColor: selected===p.id?'rgba(255,145,115,.28)':'transparent', textAlign:'left', marginBottom:2 }}>
            <Avatar name={p.name} size={32} grad={p.grad}/>
            <div style={{ flex:1, minWidth:0 }}>
              <div style={{ fontWeight:600, fontSize:13.5, overflow:'hidden', textOverflow:'ellipsis', whiteSpace:'nowrap' }}>{p.name}</div>
              <div className="faint" style={{ fontSize:11.5 }}>{p.role} · {p.company}</div>
            </div>
            <span className="faint" style={{ fontSize:11 }}>{p.lastSpokeDays}d</span>
          </button>
        ))}
      </div>
    </div>
  );
}

/* ---------- The full People section ---------- */
function PeopleView({ variant, onOpenMeeting }){
  const [selectedId,setSelectedId]=React.useState('maya');
  const person = personById(selectedId)||PEOPLE[0];

  return (
    <div style={{ display:'flex', flex:1, minWidth:0, minHeight:0 }}>
      <PeopleList selected={selectedId} onSelect={setSelectedId}/>
      <PersonLeft person={person} variant={variant}/>
      <PersonRight person={person} onOpenMeeting={onOpenMeeting} onOpenPerson={setSelectedId}/>
    </div>
  );
}

Object.assign(window, { PeopleView, AnalyzePopover });

// shell.jsx — window chrome, nav rail, tailored top toolbar, Ask-AI rail.

const NAV = [
  { group:'WORKSPACE', items:[
    { id:'today', label:'Today', icon:'today' },
    { id:'meetings', label:'Meetings', icon:'meetings' },
    { id:'people', label:'People', icon:'people' },
  ]},
  { group:'ORGANIZE', items:[
    { id:'tasks', label:'Tasks', icon:'tasks', count:7 },
    { id:'voice', label:'Voice Notes', icon:'voice' },
  ]},
];

function NavRail({ route, onRoute, onSidebar }){
  return (
    <nav className="rail">
      <div className="brand">
        <span className="mark"><Icon name="voice" size={15} color="#221636"/></span>
        <b>MeetingScribe</b>
      </div>
      {NAV.map(sec=>(
        <React.Fragment key={sec.group}>
          <div className="navgroup">{sec.group}</div>
          {sec.items.map(it=>(
            <button key={it.id} className={'navitem'+(route===it.id?' active':'')} onClick={()=>onRoute(it.id)}>
              <Icon name={it.icon} size={17}/> {it.label}
              {it.count!=null && <span className="ct">{it.count}</span>}
            </button>
          ))}
        </React.Fragment>
      ))}
      <div className="spacer" />
      <div className="railfoot">
        <div className="seg">
          <span><Icon name="today" size={11}/>Light</span>
          <span className="on"><svg viewBox="0 0 24 24" width="11" height="11" fill="none" stroke="currentColor"><path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/></svg>Dark</span>
        </div>
        <div className="kbd"><Icon name="search" size={12}/>⌘K</div>
        <button className="iconbtn"><Icon name="settings" size={15}/></button>
      </div>
    </nav>
  );
}

// Tailored top-right toolbar. Named buttons that change per page.
// (Request #1: "include names and are tailored to the page user is on".)
function TopBar({ route, recording, onSidebar, onAction, chatOpen, onToggleChat }){
  const A = (id, label, icon, cls)=> (
    <button key={id} className={'tbtn'+(cls?' '+cls:'')} onClick={()=>onAction(id)}>
      <Icon name={icon} size={15}/>{label && <span>{label}</span>}
    </button>
  );

  let actions;
  switch(route){
    case 'today':
      actions = [ A('search','Search','search'), <div className="tbtn-div" key="d"/>,
        A('voice','Voice note','mic'), A('record','Record','record','rec'), A('new-meeting','New meeting','plus','accent') ];
      break;
    case 'meetings':
      actions = [ A('search','Search','search'), A('import-cal','Import calendar','calendar'),
        <div className="tbtn-div" key="d"/>, A('record','Record','record','rec'), A('new-meeting','New meeting','plus','accent') ];
      break;
    case 'people':
      actions = [ A('search','Search','search'), A('import-people','Import','upload'),
        <div className="tbtn-div" key="d"/>, A('add-person','Add person','plus','accent') ];
      break;
    case 'tasks':
      actions = [ A('search','Search','search'), A('task-filter','Filter','filter'),
        <div className="tbtn-div" key="d"/>, A('new-task','New task','plus','accent') ];
      break;
    case 'voice':
      actions = [ A('search','Search','search'), <div className="tbtn-div" key="d"/>,
        A('voice','New voice note','mic','accent') ];
      break;
    default:
      actions = [ A('search','Search','search') ];
  }

  return (
    <div className="titlebar">
      <div className="lights"><i className="c"></i><i className="m"></i><i className="x"></i></div>
      <button className="sidebtn" onClick={onSidebar} title="Toggle sidebar"><Icon name="sidebar" size={15}/></button>
      <div className="tname"><Icon name="voice" size={13} color="var(--lilac)"/> MeetingScribe</div>
      <div className="topbar">
        {recording && (
          <button className="tbtn rec" onClick={()=>onAction('stop-meeting')}>
            <span className="recdot"/> Stop recording
          </button>
        )}
        {actions}
        <div className="tbtn-div" />
        <button className={'tbtn icon'+(chatOpen?' solid':'')} onClick={onToggleChat} title="Ask AI"><Icon name="chat" size={15}/></button>
      </div>
    </div>
  );
}

/* ---------------- Ask-AI rail (collapsible right pane) ---------------- */
function ChatRail({ open, context }){
  const [msgs,setMsgs] = React.useState([]);
  const [draft,setDraft] = React.useState('');
  if(!open) return null;
  const prompts = context?.prompts || [
    'Summarize what needs my attention today.',
    'What are my open tasks across all meetings?',
    'Draft follow-ups from this morning’s calls.',
  ];
  const send = (text)=>{
    const q = text ?? draft; if(!q.trim()) return;
    setMsgs(m=>[...m, {role:'you', text:q}, {role:'ai', text:'Running locally via Ollama — here’s a quick take based on your '+(context?.scopeLabel||'workspace')+'.'}]);
    setDraft('');
  };
  return (
    <aside style={{ width:330, flex:'0 0 auto', borderLeft:'1px solid var(--line)', background:'var(--bg)',
      display:'flex', flexDirection:'column', minHeight:0 }}>
      <div style={{ padding:'16px 16px 10px' }}>
        <div className="row" style={{ gap:8 }}>
          <Icon name="sparkles" size={16} color="var(--lilac)"/>
          <b style={{ fontSize:14 }}>{context?.title || 'Ask AI'}</b>
        </div>
      </div>
      <div className="scroll" style={{ padding:'4px 16px 12px' }}>
        {msgs.length===0 ? (
          <div>
            <div className="eyebrow" style={{ marginBottom:10 }}>Try asking</div>
            <div className="col" style={{ gap:8 }}>
              {prompts.map((p,i)=>(
                <button key={i} className="card click" style={{ padding:'10px 12px', textAlign:'left', display:'flex', gap:8, alignItems:'flex-start', fontSize:12.5, color:'var(--txt-2)' }} onClick={()=>send(p)}>
                  <Icon name="sparkles" size={14} color="var(--lilac)" style={{ flex:'0 0 auto', marginTop:1 }}/>{p}
                </button>
              ))}
            </div>
            <div className="row" style={{ gap:7, marginTop:14, fontSize:11, color:'var(--txt-3)' }}>
              <Icon name="globe" size={13}/> Running locally via Ollama. No API key, no outbound traffic.
            </div>
          </div>
        ) : (
          <div className="col" style={{ gap:10 }}>
            {msgs.map((m,i)=>(
              <div key={i} style={{ alignSelf: m.role==='you'?'flex-end':'flex-start', maxWidth:'86%',
                background: m.role==='you'?'var(--lilac-soft)':'var(--surface)', border:'1px solid var(--line)',
                borderRadius:14, padding:'9px 12px', fontSize:12.5, color: m.role==='you'?'#cbb8ff':'var(--txt)' }}>{m.text}</div>
            ))}
          </div>
        )}
      </div>
      <div style={{ padding:'10px 14px 14px', borderTop:'1px solid var(--line)' }}>
        <div className="field" style={{ padding:'8px 10px' }}>
          <input value={draft} onChange={e=>setDraft(e.target.value)} onKeyDown={e=>e.key==='Enter'&&send()} placeholder="Message…" />
          <button className="iconbtn" style={{ width:26, height:26 }} onClick={()=>send()}><Icon name="send" size={14} color="var(--accent)"/></button>
        </div>
      </div>
    </aside>
  );
}

Object.assign(window, { NavRail, TopBar, ChatRail });

// meetings.jsx — Meetings redesign (request #2).
// Variant A = pinned "Now / Next" hero band + timeline-grouped list.
// Variant B = three filter tabs (Today · Upcoming · Past with recordings).
// Detail pane: clickable attendee chips → person view,
//   Notion-style notes editor, Actions tab with push-to-Tasks,
//   Summary with decisions+action items.

/* ---- Meetings list sidebar ---- */
function MeetingsList({ selectedId, onSelect, liveMeetingId, variant }){
  const [q,setQ]=React.useState('');
  const [viewFilter,setViewFilter]=React.useState('all'); // all | upcoming | past

  const liveM = MEETINGS.find(m=>m.id===liveMeetingId);
  const today = MEETINGS.filter(m=>m.when==='today' && m.id!==liveMeetingId);
  const upcoming = MEETINGS.filter(m=>m.when==='upcoming');
  const past = MEETINGS.filter(m=>m.when==='past');

  const filtered = (list)=> q ? list.filter(m=>m.title.toLowerCase().includes(q.toLowerCase())) : list;

  const MRow = ({m, indent})=>(
    <button key={m.id} onClick={()=>onSelect(m.id)}
      style={{ width:'100%', textAlign:'left', background: selectedId===m.id?'var(--lilac-soft)':' transparent',
        border:'1px solid', borderColor: selectedId===m.id?'rgba(183,156,255,.32)':'transparent',
        borderRadius:10, padding:'9px 11px', cursor:'pointer', marginBottom:3 }}>
      <div className="row" style={{ gap:9 }}>
        {m.status==='recording'&&<span className="recdot"/>}
        <div style={{ flex:1, minWidth:0 }}>
          <div style={{ fontWeight:600, fontSize:13, overflow:'hidden', textOverflow:'ellipsis', whiteSpace:'nowrap',
            color: selectedId===m.id?'var(--txt)':'var(--txt-2)' }}>{m.title}</div>
          <div className="faint" style={{ fontSize:11, marginTop:2 }}>{m.time} · {m.dur}{m.attendees?.length?` · ${m.attendees.length} attendees`:''}</div>
        </div>
        {m.status==='summary'&&<span className="dot" style={{ background:'var(--ok)' }}/>}
        {m.status==='transcribed'&&<span className="dot" style={{ background:'var(--ok)' }}/>}
        {m.status==='scheduled'&&<span className="dot" style={{ background:'var(--surface-2)', border:'1px solid var(--line-2)' }}/>}
        {m.status==='recording'&&<span className="dot" style={{ background:'var(--danger)' }}/>}
      </div>
    </button>
  );

  return (
    <div style={{ width:280, flex:'0 0 auto', borderRight:'1px solid var(--line)', background:'var(--bg)', display:'flex', flexDirection:'column' }}>
      <div style={{ padding:'16px 14px 10px' }}>
        <div className="row" style={{ justifyContent:'space-between', marginBottom:11 }}>
          <h1 style={{ fontSize:19, fontWeight:700 }}>Meetings</h1>
          <span className="faint" style={{ fontSize:11.5 }}>{upcoming.length+today.length} today · {past.length} past</span>
        </div>
        <div className="field" style={{ padding:'7px 11px' }}>
          <Icon name="search" size={15}/><input value={q} onChange={e=>setQ(e.target.value)} placeholder="Search meetings…"/>
        </div>
        {variant==='B' && (
          <div className="row" style={{ gap:5, marginTop:10 }}>
            {['all','upcoming','past'].map(f=>(
              <button key={f} className={'minichip'+(viewFilter===f?' on':'')} style={{ textTransform:'capitalize' }} onClick={()=>setViewFilter(f)}>{f}</button>
            ))}
          </div>
        )}
      </div>

      <div className="scroll" style={{ padding:'4px 10px 16px' }}>
        {/* NOW — live recording (always shown) */}
        {liveM && (viewFilter==='all'||viewFilter==='upcoming') && (
          <div style={{ marginBottom:8 }}>
            <div className="eyebrow" style={{ padding:'6px 6px 5px', color:'var(--danger)' }}>● NOW</div>
            <MRow m={liveM}/>
          </div>
        )}
        {/* TODAY */}
        {(viewFilter==='all') && filtered(today).length>0 && (
          <div style={{ marginBottom:8 }}>
            <div className="eyebrow" style={{ padding:'6px 6px 5px' }}>TODAY</div>
            {filtered(today).map(m=><MRow key={m.id} m={m}/>)}
          </div>
        )}
        {/* UPCOMING */}
        {(viewFilter==='all'||viewFilter==='upcoming') && filtered(upcoming).length>0 && (
          <div style={{ marginBottom:8 }}>
            <div className="eyebrow" style={{ padding:'6px 6px 5px' }}>UPCOMING TODAY</div>
            {filtered(upcoming).map(m=><MRow key={m.id} m={m}/>)}
          </div>
        )}
        {/* PAST */}
        {(viewFilter==='all'||viewFilter==='past') && filtered(past).length>0 && (
          <div style={{ marginBottom:8 }}>
            <div className="eyebrow" style={{ padding:'6px 6px 5px' }}>PAST · RECORDED</div>
            {filtered(past).map(m=><MRow key={m.id} m={m}/>)}
          </div>
        )}
      </div>
    </div>
  );
}

/* ---- Notion-style notes editor ---- */
// Clean block editor with toolbar that appears on focus/selection.
function NotionEditor({ placeholder, onChange }){
  const [content,setContent]=React.useState('');
  const [toolbarPos,setToolbarPos]=React.useState(null);
  const [focused,setFocused]=React.useState(false);
  const ref=React.useRef();

  const handleKey=(e)=>{
    const txt=ref.current.innerText;
    setContent(txt);
    onChange&&onChange(txt);
    // show floating toolbar
    const sel=window.getSelection();
    if(sel&&sel.toString().length>0){ const r=sel.getRangeAt(0).getBoundingClientRect(); const p=ref.current.getBoundingClientRect(); setToolbarPos({ top: r.top-p.top-42, left: r.left-p.left }); }
    else setToolbarPos(null);
  };
  const execCmd=(cmd,val)=>{ ref.current.focus(); document.execCommand(cmd,false,val); ref.current.onInput&&ref.current.onInput(); };

  const tools = [
    { icon:'bold', cmd:'bold', title:'Bold', label:'B', style:{ fontWeight:800 } },
    { icon:'italic', cmd:'italic', title:'Italic', label:'I', style:{ fontStyle:'italic' } },
    { icon:'code', cmd:'formatBlock', val:'pre', title:'Code' },
    { icon:'quote', cmd:'formatBlock', val:'blockquote', title:'Quote' },
    { icon:'list', cmd:'insertUnorderedList', title:'Bullet list' },
    { icon:'checkCircle', cmd:'insertOrderedList', title:'Numbered list' },
    { icon:'at', title:'@ Link' },
    { icon:'link', title:'Link' },
  ];

  return (
    <div style={{ position:'relative' }}>
      {/* Block toolbar (always at top of editor area) */}
      <div className="row" style={{ gap:3, padding:'7px 0 10px', flexWrap:'wrap' }}>
        {['H1','H2','H3'].map(h=>(
          <button key={h} className="btn ghost xs" style={{ padding:'4px 8px', fontSize:11, fontWeight:800 }}
            onClick={()=>execCmd('formatBlock',h.toLowerCase())}>{h}</button>
        ))}
        <div style={{ width:1, height:18, background:'var(--line)', margin:'0 3px' }}/>
        {tools.map(t=>(
          <button key={t.icon} className="btn ghost xs" style={{ padding:'4px 7px' }} title={t.title}
            onClick={()=>{ if(t.cmd) execCmd(t.cmd,t.val); }}>
            {t.label ? <span style={t.style||{}}>{t.label}</span> : <Icon name={t.icon} size={14}/>}
          </button>
        ))}
        <div style={{ width:1, height:18, background:'var(--line)', margin:'0 3px' }}/>
        <button className="btn ghost xs" style={{ padding:'4px 7px' }} title="/ for blocks"><span style={{ fontFamily:'monospace', fontSize:12 }}>/</span></button>
      </div>

      {/* Floating selection toolbar */}
      {toolbarPos && (
        <div className="pop" style={{ position:'absolute', top:toolbarPos.top, left:Math.max(0,toolbarPos.left),
          padding:'6px 8px', display:'flex', gap:4, zIndex:20 }}>
          {['Bold','Italic','Underline'].map(c=>(
            <button key={c} className="btn ghost xs" style={{ padding:'3px 7px' }} onClick={()=>execCmd(c.toLowerCase())}>{c[0]}</button>
          ))}
          <button className="btn ghost xs" style={{ padding:'3px 7px' }} title="Link"><Icon name="link" size={12}/></button>
        </div>
      )}

      <div style={{ position:'relative', minHeight:260 }}>
        <div ref={ref} contentEditable suppressContentEditableWarning
          onFocus={()=>setFocused(true)} onBlur={()=>{ setFocused(false); setToolbarPos(null); }}
          onInput={handleKey} onMouseUp={handleKey}
          style={{ minHeight:260, outline:'none', fontSize:14, lineHeight:1.8, color:'var(--txt)',
            caretColor:'var(--accent)', padding:'4px 0' }}>
        </div>
        {(!content||content==='\n') && !focused && (
          <div className="faint" style={{ position:'absolute', top:4, left:0, fontSize:14, pointerEvents:'none', lineHeight:1.8 }}>
            {placeholder||'Type / for blocks, @ to link a meeting or person…'}
          </div>
        )}
      </div>
    </div>
  );
}

/* ---- Meeting detail — right pane ---- */
function MeetingDetail({ meeting, onOpenPerson, onPushToTasks, liveMeetingId }){
  const [tab,setTab]=React.useState(meeting.status==='recording'?'notes':'summary');
  const [actionItems,setActionItems]=React.useState([
    { id:'a1', title:'Circulate revised contract terms to legal', done:false, due:'Wed', owner:'devon', pushed:false },
    { id:'a2', title:'Build usage-based pricing model', done:false, due:'Fri', owner:'jules', pushed:false },
    { id:'a3', title:'Share recording link', done:true, due:'', owner:'me', pushed:true },
  ]);
  const [noteContent,setNoteContent]=React.useState('');
  const isLive=meeting.id===liveMeetingId;

  const pushToTasks=(id)=> setActionItems(ai=>ai.map(a=>a.id===id?{...a,pushed:true}:a));
  const pushAll=()=> setActionItems(ai=>ai.map(a=>({...a,pushed:true})));

  React.useEffect(()=>{ setTab(meeting.status==='recording'?'notes':'summary'); },[meeting.id]);

  const tabs=[
    { id:'summary', label:'Summary', icon:'sparkles' },
    { id:'notes', label:'Notes', icon:'edit' },
    { id:'actions', label:'Actions', icon:'tasks', badge: actionItems.filter(a=>!a.pushed&&!a.done).length },
    { id:'transcript', label:'Transcript', icon:'doc' },
    { id:'chat', label:'Ask AI', icon:'chat' },
  ];

  return (
    <div style={{ flex:1, minWidth:0, display:'flex', flexDirection:'column' }}>
      {/* Header */}
      <div style={{ padding:'20px 26px 0', borderBottom:'1px solid var(--line)' }}>
        <div className="row" style={{ justifyContent:'space-between', alignItems:'flex-start', marginBottom:11 }}>
          <div style={{ flex:1, minWidth:0 }}>
            <h1 style={{ fontSize:22, fontWeight:800, letterSpacing:'-.4px' }}>{meeting.title}</h1>
            <div className="muted" style={{ fontSize:12.5, marginTop:5 }}>
              {meeting.date} · {meeting.range} · {meeting.source}
            </div>
          </div>
          <div className="row" style={{ gap:7, flex:'0 0 auto' }}>
            {isLive
              ? <button className="btn rec sm"><span className="recdot"/> Stop recording</button>
              : meeting.status==='scheduled'
              ? <button className="btn primary sm"><Icon name="video" size={14}/> Join &amp; record</button>
              : <button className="btn secondary sm"><Icon name="refresh" size={14}/> Re-transcribe</button>}
            <button className="btn secondary sm"><Icon name="download" size={14}/></button>
          </div>
        </div>

        {/* Attendees — all clickable to open person detail. Non-People contacts get + Add to People */}
        <div className="row" style={{ gap:6, flexWrap:'wrap', marginBottom:11 }}>
          {meeting.attendees?.map(id=>{
            const p=personById(id);
            if(!p) return null;
            return (
              <button key={id} className="chip t-gray" style={{ cursor:'pointer', border:'1px solid transparent' }}
                onClick={()=>onOpenPerson&&onOpenPerson(id)}>
                <Avatar name={p.name} size={18} grad={p.grad} style={{ borderRadius:'34%' }}/>{p.name.split(' ')[0]}
              </button>
            );
          })}
          {meeting.extra?.map((e,i)=>(
            <button key={i} className="chip t-gray" style={{ cursor:'pointer' }} title="Add to People">
              <Icon name="contact" size={11}/>
              {e.split('@')[0]}
              <span className="badge t-iris" style={{ fontSize:9, padding:'1px 5px' }}>+ People</span>
            </button>
          ))}
          {meeting.attendees?.length > 0 && (
            <button className="chip t-gray" style={{ cursor:'pointer' }}>
              <Icon name="plus" size={11}/> Add people
            </button>
          )}
        </div>

        {/* Meeting link + tags */}
        <div className="row" style={{ gap:10, marginBottom:13, flexWrap:'wrap' }}>
          {meeting.link && (
            <span className="row" style={{ gap:6, fontSize:12.5, color:'var(--accent)' }}>
              <Icon name="video" size={13}/>{meeting.link}
            </span>
          )}
          {meeting.tags?.map(t=><span key={t} className="chip t-gray" style={{ fontSize:11 }}>{t}</span>)}
        </div>

        {/* Live recording bar */}
        {isLive && (
          <div className="row" style={{ gap:10, padding:'8px 12px', background:'rgba(255,122,138,.1)', border:'1px solid rgba(255,122,138,.28)', borderRadius:10, marginBottom:13 }}>
            <span className="live"><span className="recdot"/>RECORDING</span>
            <Waveform color="rgba(255,122,138,.7)" bars={12} small/>
            <span className="faint" style={{ fontSize:11.5, marginLeft:'auto' }}>Mic: Active · System: Active</span>
          </div>
        )}

        {/* Tabs */}
        <div className="tabbar">
          {tabs.map(t=>(
            <button key={t.id} className={'tab'+(tab===t.id?' active':'')} onClick={()=>setTab(t.id)}>
              <Icon name={t.icon} size={14}/>{t.label}
              {t.badge>0&&<span className="badge t-iris" style={{ fontSize:9.5, padding:'1px 6px', marginLeft:2 }}>{t.badge}</span>}
            </button>
          ))}
        </div>
      </div>

      {/* Tab body */}
      <div className="scroll" style={{ padding:'20px 26px 30px' }}>
        {tab==='summary' && <MeetingSummary meeting={meeting} actionItems={actionItems} onPushOne={pushToTasks} onPushAll={pushAll}/>}
        {tab==='notes' && (
          <div>
            <div className="card" style={{ padding:'16px 18px' }}>
              <NotionEditor placeholder="Start taking notes… Type / for blocks, @ to link a meeting or person." onChange={setNoteContent}/>
            </div>
            {noteContent && (
              <div className="row" style={{ gap:8, marginTop:12 }}>
                <button className="btn secondary xs"><Icon name="tasks" size={12}/> Push notes → Tasks</button>
                <button className="btn secondary xs"><Icon name="download" size={12}/> Export</button>
              </div>
            )}
          </div>
        )}
        {tab==='actions' && <MeetingActions actionItems={actionItems} setActionItems={setActionItems} onPushOne={pushToTasks} onPushAll={pushAll}/>}
        {tab==='transcript' && <MeetingTranscript/>}
        {tab==='chat' && <MeetingChat meeting={meeting}/>}
      </div>
    </div>
  );
}

function MeetingSummary({ meeting, actionItems, onPushOne, onPushAll }){
  const unpushed=actionItems.filter(a=>!a.pushed&&!a.done);
  return (
    <div style={{ display:'grid', gridTemplateColumns:'1.7fr 1fr', gap:26 }}>
      <div>
        <div className="eyebrow" style={{ color:'var(--accent)', marginBottom:10 }}>AI SUMMARY</div>
        <p style={{ fontSize:14, lineHeight:1.7, color:'var(--txt)' }}>The team reviewed the Skio integration timeline and aligned on a phased rollout. Maya raised concerns about the contract redline still pending legal review; Devon committed to circulating the revised terms by Wednesday.</p>
        <p style={{ fontSize:14, lineHeight:1.7, color:'var(--txt-2)', marginTop:10 }}>Pricing for the enterprise tier was discussed — the group leaned toward usage-based bands rather than seat licensing, pending a model from Jules.</p>
        <div className="eyebrow" style={{ margin:'20px 0 10px' }}>DECISIONS</div>
        <div className="col" style={{ gap:9 }}>
          {['Ship Skio integration in two phases — read API first, write-back in phase 2.','Move to usage-based pricing bands for enterprise.'].map((d,i)=>(
            <div key={i} className="row" style={{ alignItems:'flex-start', gap:9 }}>
              <Icon name="checkCircle" size={16} color="var(--ok)" style={{ flex:'0 0 auto', marginTop:2 }}/>
              <span style={{ fontSize:13.5 }}>{d}</span>
            </div>
          ))}
        </div>
      </div>
      <div className="col" style={{ gap:14 }}>
        <div className="card" style={{ padding:'14px 15px' }}>
          <div className="row" style={{ marginBottom:12 }}>
            <b style={{ fontSize:14 }}>Action items</b>
            <span className="badge t-iris" style={{ marginLeft:'auto' }}>{actionItems.length}</span>
            {unpushed.length>0&&(
              <button className="btn primary xs" onClick={onPushAll}><Icon name="tasks" size={12}/> Push all → Tasks</button>
            )}
          </div>
          <div className="col" style={{ gap:10 }}>
            {actionItems.map(a=>(
              <div key={a.id} className="row" style={{ alignItems:'flex-start', gap:9 }}>
                <div style={{ width:16, height:16, borderRadius:5, flex:'0 0 auto', marginTop:1, display:'grid', placeItems:'center',
                  border: a.done?'none':'1.5px solid var(--line-2)', background: a.done?'var(--ok)':'transparent' }}>
                  {a.done&&<Icon name="check" size={11} color="#0e1a14" style={{ strokeWidth:3 }}/>}
                </div>
                <div style={{ flex:1 }}>
                  <div style={{ fontSize:13, fontWeight:500, textDecoration:a.done?'line-through':'none', color:a.done?'var(--txt-3)':'var(--txt)' }}>{a.title}</div>
                  <div className="row" style={{ gap:6, marginTop:5 }}>
                    {a.due&&<DueBadge due={a.due}/>}
                    {a.owner&&<OwnerAvatar owner={a.owner} size={18}/>}
                    {a.pushed
                      ? <span className="badge t-ok" style={{ marginLeft:'auto', fontSize:10 }}><Icon name="tasks" size={10}/>In Tasks</span>
                      : !a.done && <button className="btn ghost xs" style={{ marginLeft:'auto', fontSize:10.5, padding:'2px 7px' }} onClick={()=>onPushOne(a.id)}>→ Tasks</button>}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
        <div className="card" style={{ padding:'13px 15px' }}>
          <div className="row" style={{ gap:12 }}>
            <button style={{ width:38, height:38, borderRadius:'50%', background:'var(--accent)', border:'none', cursor:'pointer', display:'grid', placeItems:'center' }}>
              <Icon name="play" size={15} color="#2a1208"/>
            </button>
            <div style={{ flex:1 }}>
              <div style={{ height:5, borderRadius:3, background:'var(--surface-2)', position:'relative' }}>
                <div style={{ position:'absolute', left:0, top:0, bottom:0, width:'34%', borderRadius:3, background:'var(--accent)' }}/>
              </div>
              <div className="row faint" style={{ justifyContent:'space-between', fontSize:11, marginTop:6 }}><span>14:18</span><span>42:00</span></div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function MeetingActions({ actionItems, setActionItems, onPushOne, onPushAll }){
  const unpushed=actionItems.filter(a=>!a.pushed&&!a.done);
  const toggle=(id)=>setActionItems(ai=>ai.map(a=>a.id===id?{...a,done:!a.done}:a));
  return (
    <div style={{ maxWidth:620 }}>
      <div className="row" style={{ marginBottom:14, justifyContent:'space-between' }}>
        <div className="eyebrow">Action items from this meeting</div>
        {unpushed.length>0&&(
          <button className="btn primary sm" onClick={onPushAll}><Icon name="tasks" size={14}/> Push all {unpushed.length} → Tasks</button>
        )}
      </div>
      <div className="col" style={{ gap:9 }}>
        {actionItems.map(a=>(
          <div key={a.id} className="card hover" style={{ padding:'12px 14px', opacity: a.done?.62:1 }}>
            <div className="row" style={{ alignItems:'flex-start', gap:11 }}>
              <TaskCheckbox done={a.done} onToggle={()=>toggle(a.id)} accent="var(--ok)"/>
              <div style={{ flex:1 }}>
                <div style={{ fontSize:13.5, fontWeight:600, textDecoration:a.done?'line-through':'none', color:a.done?'var(--txt-2)':'var(--txt)' }}>{a.title}</div>
                <div className="row" style={{ gap:7, marginTop:8, flexWrap:'wrap' }}>
                  {a.due&&<DueBadge due={a.due}/>}
                  {a.owner&&<span className="chip t-gray" style={{ fontSize:10.5, padding:'2px 8px' }}><OwnerAvatar owner={a.owner} size={14}/>{a.owner==='me'?'You':personById(a.owner)?.name.split(' ')[0]||a.owner}</span>}
                  {a.pushed
                    ? <span className="badge t-ok"><Icon name="tasks" size={11}/>In Tasks</span>
                    : !a.done && <button className="btn secondary xs" onClick={()=>onPushOne(a.id)}><Icon name="tasks" size={11}/> → Tasks</button>}
                </div>
              </div>
              <button className="iconbtn" style={{ width:24, height:24 }}><Icon name="more" size={14}/></button>
            </div>
          </div>
        ))}
      </div>
      <button className="btn ghost xs" style={{ marginTop:12 }}><Icon name="plus" size={12}/> Add action item</button>
    </div>
  );
}

function MeetingTranscript(){
  const lines=[
    { t:'00:00', spk:'Maya Kerr', txt:'Let\'s kick off. Quick status on the Skio integration — where are we?' },
    { t:'00:14', spk:'Devon Vale', txt:'Contract redline is still with legal. I\'ll circulate the revised terms by Wednesday.' },
    { t:'00:48', spk:'Jules Lin', txt:'On the pricing side, I\'m modeling the usage-based bands. Should have numbers Friday.' },
    { t:'01:22', spk:'Maya Kerr', txt:'Good. Let\'s align on phased rollout — read API first, write-back in phase two.' },
  ];
  return (
    <div style={{ maxWidth:680 }}>
      {lines.map((l,i)=>(
        <div key={i} className="row" style={{ alignItems:'flex-start', gap:13, padding:'11px 0', borderBottom:'1px solid var(--line)' }}>
          <span className="faint" style={{ fontSize:11.5, fontVariantNumeric:'tabular-nums', flex:'0 0 38px' }}>{l.t}</span>
          <Avatar name={l.spk} size={26} grad={gradFor(l.spk)} style={{ marginTop:1 }}/>
          <div>
            <div style={{ fontWeight:700, fontSize:12.5 }}>{l.spk}</div>
            <div style={{ fontSize:13.5, lineHeight:1.6, marginTop:2 }}>{l.txt}</div>
          </div>
        </div>
      ))}
    </div>
  );
}

function MeetingChat({ meeting }){
  const prompts=[
    'Summarize the key decisions from this meeting.',
    'What did Maya commit to?',
    'Draft a follow-up email to all attendees.',
    'List all open action items with owners.',
  ];
  const [msgs,setMsgs]=React.useState([]);
  const [draft,setDraft]=React.useState('');
  const send=(text)=>{
    const q=text??draft; if(!q.trim()) return;
    setMsgs(m=>[...m,{role:'you',text:q},{role:'ai',text:'Based on this meeting\'s transcript and summary: Devon committed to the contract by Wednesday, Jules will model pricing by Friday. The phased rollout was agreed.'}]);
    setDraft('');
  };
  return (
    <div style={{ maxWidth:600 }}>
      {msgs.length===0&&(
        <div className="col" style={{ gap:8, marginBottom:20 }}>
          {prompts.map((p,i)=>(
            <button key={i} className="card click" style={{ padding:'10px 13px', textAlign:'left', fontSize:13, color:'var(--txt-2)', display:'flex', gap:9, alignItems:'flex-start' }} onClick={()=>send(p)}>
              <Icon name="sparkles" size={14} color="var(--lilac)" style={{ flex:'0 0 auto', marginTop:1 }}/>{p}
            </button>
          ))}
        </div>
      )}
      <div className="col" style={{ gap:10, marginBottom:16 }}>
        {msgs.map((m,i)=>(
          <div key={i} style={{ alignSelf: m.role==='you'?'flex-end':'flex-start', maxWidth:'85%',
            background: m.role==='you'?'var(--lilac-soft)':'var(--surface)', border:'1px solid var(--line)',
            borderRadius:14, padding:'9px 13px', fontSize:13, color: m.role==='you'?'#cbb8ff':'var(--txt)' }}>{m.text}</div>
        ))}
      </div>
      <div className="field">
        <input value={draft} onChange={e=>setDraft(e.target.value)} onKeyDown={e=>e.key==='Enter'&&send()} placeholder="Ask about this meeting…"/>
        <button className="iconbtn" style={{ width:26, height:26 }} onClick={()=>send()}><Icon name="send" size={14} color="var(--accent)"/></button>
      </div>
    </div>
  );
}

/* ---- The full Meetings section ---- */
function MeetingsView({ variant, onOpenPerson, liveMeetingId, onPushToTasks }){
  const [selectedId,setSelectedId]=React.useState(liveMeetingId||'m-sync');
  const selected=meetingById(selectedId)||MEETINGS[0];
  return (
    <div style={{ display:'flex', flex:1, minWidth:0, minHeight:0 }}>
      <MeetingsList selectedId={selectedId} onSelect={setSelectedId} liveMeetingId={liveMeetingId} variant={variant}/>
      <MeetingDetail meeting={selected} onOpenPerson={onOpenPerson} onPushToTasks={onPushToTasks} liveMeetingId={liveMeetingId}/>
    </div>
  );
}

Object.assign(window, { MeetingsView, NotionEditor, MeetingDetail });

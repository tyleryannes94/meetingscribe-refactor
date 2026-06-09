// today.jsx — Today dashboard (home screen). Lightweight; the 4 redesign areas are the star.

function TodayView({ onRoute, liveMeeting, onStartVoice }){
  const now=new Date(), days=['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
  const months=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  const label=`${days[now.getDay()]}, ${months[now.getMonth()]} ${now.getDate()}`;
  const overdue=TASKS.filter(t=>t.confirmed&&t.status!=='done'&&t.due==='Overdue');
  const dueToday=TASKS.filter(t=>t.confirmed&&t.status!=='done'&&['Today','Wed','Thu'].includes(t.due));
  const inbox=TASKS.filter(t=>!t.confirmed);

  return (
    <div className="scroll">
      <div className="page">
        <div className="pagehead" style={{ marginBottom:24 }}>
          <div>
            <h1>{label}</h1>
            <div className="sub">
              {MEETINGS.filter(m=>m.when==='today').length} today · {MEETINGS.filter(m=>m.when==='upcoming').length} upcoming
              {inbox.length>0&&<> · <span style={{ color:'var(--accent)' }}>{inbox.length} to triage</span></>}
            </div>
          </div>
        </div>

        <div style={{ display:'flex', gap:24, alignItems:'flex-start' }}>
          {/* LEFT FEED */}
          <div style={{ flex:1.5, minWidth:0, display:'flex', flexDirection:'column', gap:14 }}>
            <button className="btn primary block" onClick={()=>onRoute('meetings')}>
              <Icon name="record" size={16}/> Record Meeting
            </button>
            <div style={{ display:'flex', gap:8, flexWrap:'wrap' }}>
              <button className="pill" style={{ background:'rgba(255,206,107,.16)', color:'#ffd98a' }} onClick={onStartVoice}>
                <Icon name="mic" size={14}/> Voice note
              </button>
              <button className="pill" style={{ background:'rgba(116,224,188,.16)', color:'#9aedd0' }} onClick={()=>onRoute('tasks')}>
                <Icon name="tasks" size={14}/> New task
              </button>
              <button className="pill" style={{ background:'var(--lilac-soft)', color:'#cbb8ff' }}>
                <Icon name="doc" size={14}/> New page
              </button>
              {inbox.length>0 && (
                <button className="pill" style={{ background:'var(--accent-soft)', color:'#ffb59f' }} onClick={()=>onRoute('tasks')}>
                  <Icon name="inbox" size={14}/> {inbox.length} to triage
                </button>
              )}
            </div>

            {/* Up next */}
            {MEETINGS.filter(m=>m.when==='upcoming').slice(0,1).map(m=>(
              <div key={m.id} className="card" style={{ padding:'16px', borderColor:'rgba(255,145,115,.35)' }}>
                <div className="row" style={{ alignItems:'flex-start' }}>
                  <div style={{ flex:1 }}>
                    <div className="eyebrow" style={{ color:'var(--accent)' }}>UP NEXT</div>
                    <div style={{ fontSize:15.5, fontWeight:700, marginTop:5 }}>{m.title}</div>
                    <div className="muted" style={{ fontSize:12.5, marginTop:2 }}>Starts at {m.time} · {m.link?'Google Meet':'Calendar'}</div>
                  </div>
                  <div className="row" style={{ gap:8 }}>
                    <button className="btn primary sm" onClick={()=>onRoute('meetings')}><Icon name="video" size={14}/> Join &amp; record</button>
                    <button className="btn secondary sm" onClick={()=>onRoute('meetings')}>Open</button>
                  </div>
                </div>
              </div>
            ))}

            {/* Live meeting alert */}
            {liveMeeting && (
              <div className="card anim-in" style={{ padding:'14px 16px', borderColor:'rgba(255,122,138,.38)' }}>
                <div className="row" style={{ gap:8 }}>
                  <span className="recdot"/>
                  <div style={{ flex:1 }}>
                    <div className="live">RECORDING NOW</div>
                    <div style={{ fontWeight:600, marginTop:3 }}>{liveMeeting.title}</div>
                  </div>
                  <button className="btn primary sm" onClick={()=>onRoute('meetings')}><Icon name="edit" size={13}/> Open &amp; add notes</button>
                </div>
              </div>
            )}

            {/* Today's meetings */}
            <div>
              <div className="eyebrow" style={{ marginBottom:9 }}>TODAY</div>
              <div className="col" style={{ gap:9 }}>
                {MEETINGS.filter(m=>m.when==='today'||m.when==='upcoming').slice(0,4).map(m=>(
                  <button key={m.id} className="card click hover" style={{ padding:'13px 15px' }} onClick={()=>onRoute('meetings')}>
                    <div className="row">
                      <div className="avstack" style={{ flex:'0 0 auto' }}>
                        {m.attendees?.slice(0,3).map(id=>{ const p=personById(id); return p?<Avatar key={id} name={p.name} size={28} grad={p.grad}/>:null; })}
                      </div>
                      <div style={{ flex:1, minWidth:0, marginLeft:8 }}>
                        <div style={{ fontWeight:600, fontSize:13.5 }}>{m.title}</div>
                        <div className="faint" style={{ fontSize:12 }}>{m.time} · {m.attendees?.length||0} attendees{m.status==='summary'?' · summary ready':m.status==='transcribed'?' · transcribed':''}</div>
                      </div>
                      {m.tags?.slice(0,1).map(t=><span key={t} className="chip t-iris" style={{ fontSize:11 }}>{t}</span>)}
                      <Icon name="chevR" size={15} color="var(--txt-3)"/>
                    </div>
                  </button>
                ))}
              </div>
            </div>
          </div>

          {/* RIGHT COLUMN */}
          <div style={{ flex:1, minWidth:0, display:'flex', flexDirection:'column', gap:14 }}>
            {/* Needs attention */}
            <div className="card" style={{ padding:'15px' }}>
              <div className="row" style={{ marginBottom:11 }}>
                <Icon name="alert" size={16} color="var(--warn)"/>
                <b style={{ fontSize:14 }}>Needs attention</b>
                <span className="badge t-warn" style={{ marginLeft:'auto' }}>{overdue.length+dueToday.length}</span>
              </div>
              <div className="col" style={{ gap:8 }}>
                {overdue.map(t=>(
                  <div key={t.id} className="row" style={{ fontSize:12.5 }}>
                    <span className="dot" style={{ background:'var(--danger)' }}/>
                    <span style={{ flex:1 }}>{t.title}</span>
                    <span className="badge t-danger">Overdue</span>
                  </div>
                ))}
                {dueToday.slice(0,3).map(t=>(
                  <div key={t.id} className="row" style={{ fontSize:12.5 }}>
                    <span className="dot" style={{ background:'var(--warn)' }}/>
                    <span style={{ flex:1 }}>{t.title}</span>
                    <span className="badge t-warn">Today</span>
                  </div>
                ))}
              </div>
              {(overdue.length+dueToday.length)>0&&<button className="btn ghost xs" style={{ marginTop:10, width:'100%' }} onClick={()=>onRoute('tasks')}>View all in Tasks →</button>}
            </div>

            {/* People nudges */}
            <div className="card" style={{ padding:'15px' }}>
              <div className="row" style={{ marginBottom:11 }}>
                <Icon name="people" size={16} color="var(--accent)"/>
                <b style={{ fontSize:14 }}>Stay connected</b>
              </div>
              <div className="col" style={{ gap:8 }}>
                {PEOPLE.filter(p=>p.cadence!=='Healthy'&&p.cadence!=='New').slice(0,3).map(p=>(
                  <div key={p.id} className="row" style={{ fontSize:12.5 }}>
                    <Avatar name={p.name} size={26} grad={p.grad}/>
                    <div style={{ flex:1 }}>
                      <div style={{ fontWeight:600 }}>{p.name}</div>
                      <div className="faint" style={{ fontSize:11 }}>Last {p.lastSpokeDays}d ago · usually every {p.cadenceDays}d</div>
                    </div>
                    <span className="badge" style={{ background: p.cadence==='Slipping'?'rgba(255,206,107,.16)':'rgba(255,122,138,.16)', color: p.cadence==='Slipping'?'var(--warn)':'var(--danger)' }}>{p.cadence}</span>
                  </div>
                ))}
              </div>
            </div>

            {/* On this day */}
            <div className="card" style={{ padding:'15px' }}>
              <div className="row" style={{ marginBottom:11 }}>
                <Icon name="clock" size={16} color="var(--accent)"/>
                <b style={{ fontSize:14 }}>On this day</b>
              </div>
              <div className="col" style={{ gap:9 }}>
                {[{title:'Kickoff — Purple Party 2026',when:'1 year ago'},{title:'Slack Huddle — Infra',when:'3 months ago'}].map((x,i)=>(
                  <div key={i} className="row" style={{ fontSize:12.5, cursor:'pointer' }}>
                    <div style={{ flex:1 }}>
                      <div style={{ fontWeight:600 }}>{x.title}</div>
                      <div className="faint" style={{ fontSize:11 }}>{x.when}</div>
                    </div>
                    <Icon name="chevR" size={14} color="var(--txt-3)"/>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function VoiceNotesView(){
  return (
    <div className="scroll"><div className="page">
      <div className="pagehead" style={{ marginBottom:20 }}><div><h1>Voice Notes</h1><div className="sub">12 recordings</div></div></div>
      <div className="col" style={{ gap:10, maxWidth:640 }}>
        {[{t:'Ad-hoc note — API thoughts',d:'Today 12:18',dur:'4m 12s'},{t:'Weekly ideas dump',d:'Jun 8 · 8:44 PM',dur:'18m'},{t:'Quick capture — Theo call notes',d:'Jun 5',dur:'2m 3s'}].map((n,i)=>(
          <div key={i} className="card hover" style={{ padding:'13px 15px' }}>
            <div className="row">
              <div style={{ width:36, height:36, borderRadius:11, background:'rgba(255,206,107,.18)', display:'grid', placeItems:'center' }}><Icon name="mic" size={17} color="var(--gold)"/></div>
              <div style={{ flex:1 }}>
                <div style={{ fontWeight:600, fontSize:13.5 }}>{n.t}</div>
                <div className="faint" style={{ fontSize:11.5, marginTop:2 }}>{n.d} · {n.dur}</div>
              </div>
              <button className="iconbtn" style={{ width:32, height:32, borderRadius:'50%', background:'var(--surface-2)', border:'1px solid var(--line)' }}><Icon name="play" size={13} color="var(--gold)"/></button>
            </div>
          </div>
        ))}
      </div>
    </div></div>
  );
}

Object.assign(window, { TodayView, VoiceNotesView });

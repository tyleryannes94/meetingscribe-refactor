// recording.jsx — the two distinct recording indicators (request #1).
//   • Meeting recording  -> in-app DOCKED bar, bottom-right of the app window,
//     with a "quick open" that jumps into the live meeting note. Never floats over other apps.
//   • Voice note          -> a FLOATING, draggable hover pill (simulated bottom-right),
//     visually distinct (gold), the kind that sits above any app.
// Style A = full labelled bars/pills. Style B = compact orb that expands on hover.

function useTicker(active){
  const [s,setS]=React.useState(0);
  React.useEffect(()=>{ if(!active) return; const id=setInterval(()=>setS(x=>x+1),1000); return ()=>clearInterval(id); },[active]);
  React.useEffect(()=>{ if(!active) setS(0); },[active]);
  return s;
}
function fmt(s){ const m=Math.floor(s/60), ss=s%60; return `${m}:${String(ss).padStart(2,'0')}`; }

function Waveform({ color, bars=14, small }){
  return (
    <div style={{ display:'flex', alignItems:'center', gap:2, height: small?14:18 }}>
      {Array.from({length:bars}).map((_,i)=>(
        <span key={i} style={{ width:2.5, borderRadius:2, background:color,
          height: `${30 + Math.abs(Math.sin(i*1.3))*70}%`,
          animation:`wf 1s ease-in-out ${i*0.07}s infinite alternate` }} />
      ))}
      <style>{`@keyframes wf{from{transform:scaleY(.4)}to{transform:scaleY(1)}}
        @media (prefers-reduced-motion: reduce){[style*="wf"]{animation:none!important}}`}</style>
    </div>
  );
}

/* ---------------- Meeting docked bar (in-app, bottom-right) ---------------- */
function MeetingRecordBar({ meeting, style, onOpen, onStop }){
  const t = useTicker(true);
  if(!meeting) return null;
  const names = (meeting.attendees||[]).map(id=>personById(id)?.name).filter(Boolean);

  if(style==='B'){
    return (
      <div className="anim-in" style={{ position:'absolute', right:18, bottom:18, zIndex:40 }}>
        <div style={{ display:'flex', alignItems:'center', gap:10, background:'rgba(30,25,37,.96)',
          border:'1px solid rgba(255,122,138,.4)', borderRadius:999, padding:'7px 8px 7px 13px',
          boxShadow:'0 14px 40px rgba(0,0,0,.5)', backdropFilter:'blur(8px)' }}>
          <span className="recdot" />
          <span style={{ fontSize:12.5, fontWeight:800, color:'#ffa6b0', fontVariantNumeric:'tabular-nums' }}>{fmt(t)}</span>
          <span style={{ fontSize:12.5, fontWeight:600, maxWidth:170, overflow:'hidden', textOverflow:'ellipsis', whiteSpace:'nowrap' }}>{meeting.title}</span>
          <button className="btn primary xs" onClick={onOpen}><Icon name="edit" size={12}/> Notes</button>
          <button className="iconbtn" style={{ width:26, height:26 }} title="Stop" onClick={onStop}><Icon name="stop" size={12} color="#ffa6b0"/></button>
        </div>
      </div>
    );
  }
  // Style A — labelled card with quick-open into the live note
  return (
    <div className="anim-in" style={{ position:'absolute', right:18, bottom:18, width:308, zIndex:40,
      background:'rgba(30,25,37,.97)', border:'1px solid rgba(255,122,138,.38)', borderRadius:16,
      boxShadow:'0 18px 50px rgba(0,0,0,.55)', overflow:'hidden', backdropFilter:'blur(10px)' }}>
      <div style={{ height:3, background:'linear-gradient(90deg,var(--danger),var(--accent))' }} />
      <div style={{ padding:'12px 14px' }}>
        <div className="row" style={{ gap:8 }}>
          <span className="recdot" />
          <span className="live">RECORDING MEETING</span>
          <span style={{ marginLeft:'auto', fontSize:12.5, fontWeight:800, color:'#ffa6b0', fontVariantNumeric:'tabular-nums' }}>{fmt(t)}</span>
        </div>
        <div style={{ fontWeight:700, fontSize:13.5, marginTop:9 }}>{meeting.title}</div>
        <div className="faint" style={{ fontSize:11.5, marginTop:2 }}>{names.slice(0,3).join(', ')}{names.length>3?` +${names.length-3}`:''} · System + Mic</div>
        <div className="row" style={{ marginTop:10, gap:8 }}>
          <Waveform color="rgba(255,122,138,.7)" bars={10} small />
          <div className="row" style={{ gap:7, marginLeft:'auto' }}>
            <button className="btn primary xs" onClick={onOpen} title="Jump into the live note">
              <Icon name="edit" size={12}/> Open &amp; add notes
            </button>
            <button className="iconbtn" style={{ width:28, height:28, background:'rgba(255,122,138,.14)' }} title="Stop recording" onClick={onStop}>
              <Icon name="stop" size={12} color="#ffa6b0"/>
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ---------------- Voice note hover pill (floats over any app) ---------------- */
// Draggable. Lives in a layer that represents "above the OS", visually detached
// from the app chrome (gold, rounded, soft shadow) so it reads as a system-wide HUD.
function VoiceHoverPill({ active, style, onStop, onCancel }){
  const t = useTicker(active);
  const [pos,setPos] = React.useState({ x: null, y: null });
  const drag = React.useRef(null);
  if(!active) return null;

  const startDrag = (e)=>{
    const host = e.currentTarget.closest('.win').getBoundingClientRect();
    drag.current = { sx:e.clientX, sy:e.clientY,
      ox: pos.x==null ? host.width-280 : pos.x, oy: pos.y==null ? host.height-150 : pos.y };
    const move=(ev)=> setPos({ x: drag.current.ox+(ev.clientX-drag.current.sx), y: drag.current.oy+(ev.clientY-drag.current.sy) });
    const up=()=>{ window.removeEventListener('mousemove',move); window.removeEventListener('mouseup',up); };
    window.addEventListener('mousemove',move); window.addEventListener('mouseup',up);
  };
  const place = pos.x==null ? { right:18, bottom:78 } : { left:pos.x, top:pos.y };

  if(style==='B'){
    return (
      <div className="anim-in" style={{ position:'absolute', ...place, zIndex:50 }}>
        <div onMouseDown={startDrag} style={{ display:'flex', alignItems:'center', gap:9, cursor:'grab',
          background:'rgba(255,206,107,.95)', color:'#3a2c08', borderRadius:999, padding:'8px 10px 8px 12px',
          boxShadow:'0 16px 44px rgba(0,0,0,.5), 0 0 0 4px rgba(255,206,107,.18)' }}>
          <Icon name="mic" size={15}/>
          <span style={{ fontSize:12.5, fontWeight:800, fontVariantNumeric:'tabular-nums' }}>{fmt(t)}</span>
          <button onClick={onStop} title="Save voice note" style={{ border:'none', cursor:'pointer', width:24, height:24, borderRadius:'50%', background:'#3a2c08', color:'#ffce6b', display:'grid', placeItems:'center' }}><Icon name="stop" size={11}/></button>
        </div>
      </div>
    );
  }
  // Style A — labelled floating HUD pill with grip + waveform
  return (
    <div className="anim-in" style={{ position:'absolute', ...place, zIndex:50, width:236 }}>
      <div style={{ background:'rgba(34,26,8,.96)', border:'1px solid rgba(255,206,107,.45)', borderRadius:14,
        boxShadow:'0 18px 50px rgba(0,0,0,.55), 0 0 0 5px rgba(255,206,107,.1)', backdropFilter:'blur(10px)', overflow:'hidden' }}>
        <div onMouseDown={startDrag} className="row" style={{ gap:7, padding:'8px 11px', cursor:'grab', background:'rgba(255,206,107,.1)' }}>
          <Icon name="grip" size={13} color="rgba(255,206,107,.6)"/>
          <span style={{ fontSize:10.5, fontWeight:800, letterSpacing:.6, color:'#ffce6b' }}>VOICE NOTE · OVER ANY APP</span>
        </div>
        <div className="row" style={{ gap:10, padding:'11px 13px' }}>
          <span style={{ width:30, height:30, borderRadius:'50%', background:'#ffce6b', color:'#3a2c08', display:'grid', placeItems:'center', flex:'0 0 auto' }}><Icon name="mic" size={15}/></span>
          <Waveform color="rgba(255,206,107,.85)" bars={8} small />
          <span style={{ marginLeft:'auto', fontSize:12.5, fontWeight:800, color:'#ffce6b', fontVariantNumeric:'tabular-nums' }}>{fmt(t)}</span>
        </div>
        <div className="row" style={{ gap:7, padding:'0 11px 11px' }}>
          <button className="btn xs" style={{ flex:1, background:'#ffce6b', color:'#3a2c08' }} onClick={onStop}><Icon name="check" size={12}/> Save note</button>
          <button className="iconbtn" style={{ width:30, height:30 }} title="Discard" onClick={onCancel}><Icon name="trash" size={13} color="var(--txt-3)"/></button>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { MeetingRecordBar, VoiceHoverPill, Waveform, fmtRec:fmt });

import Foundation

/// Static web assets served by the embedded server. Inlined as Swift string
/// constants (rather than SwiftPM resources) so the existing Makefile bundling
/// step needs no changes — the whole phone UI ships inside the binary.
///
/// The app is a single self-contained HTML document (CSS + vanilla JS inline);
/// it talks to `/api/*` with the session cookie that the QR-link handshake set.
enum WebAssets {

    static let notFoundHTML = """
    <!doctype html><meta charset="utf-8">
    <title>Not found</title>
    <body style="font-family:-apple-system,sans-serif;padding:2rem;color:#333">
    <h1>404</h1><p>Nothing here.</p></body>
    """

    static let unlockHTML = """
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <title>MeetingScribe — Connect</title>
    <style>
      :root { color-scheme: dark; }
      body { font-family:-apple-system,BlinkMacSystemFont,sans-serif; background:#0f1115; color:#e7e9ee;
             margin:0; min-height:100vh; display:flex; align-items:center; justify-content:center; padding:1.5rem; }
      .card { max-width:340px; width:100%; text-align:center; }
      h1 { font-size:1.3rem; margin:0 0 .5rem; }
      p { color:#9aa3b2; line-height:1.5; }
      input { width:100%; box-sizing:border-box; padding:.85rem; border-radius:12px; border:1px solid #2a2f3a;
              background:#171a21; color:#fff; font-size:1rem; margin:1rem 0 .75rem; }
      button { width:100%; padding:.85rem; border:0; border-radius:12px; background:#3b82f6; color:#fff;
               font-size:1rem; font-weight:600; }
    </style>
    </head>
    <body>
      <form class="card" action="/" method="get">
        <h1>MeetingScribe</h1>
        <p>Scan the QR code in MeetingScribe → Settings → Phone access, or paste your access token below.</p>
        <input name="t" placeholder="Access token" autocapitalize="off" autocomplete="off" spellcheck="false">
        <button type="submit">Connect</button>
      </form>
    </body>
    </html>
    """

    static let appHTML = """
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <meta name="theme-color" content="#0f1115">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-title" content="MeetingScribe">
    <title>MeetingScribe</title>
    <style>
      :root { color-scheme: dark; --bg:#0f1115; --panel:#171a21; --line:#262b36; --muted:#9aa3b2; --accent:#3b82f6; }
      * { box-sizing:border-box; -webkit-tap-highlight-color:transparent; }
      body { margin:0; font-family:-apple-system,BlinkMacSystemFont,"SF Pro",sans-serif; background:var(--bg); color:#e7e9ee; }
      header { position:sticky; top:0; z-index:5; display:flex; align-items:center; gap:.25rem;
               padding:max(env(safe-area-inset-top),.6rem) .75rem .6rem; background:rgba(15,17,21,.92);
               backdrop-filter:saturate(180%) blur(12px); border-bottom:1px solid var(--line); }
      header h1 { font-size:1.05rem; font-weight:600; margin:0; flex:1; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
      #back { background:none; border:0; color:var(--accent); font-size:1.7rem; line-height:1; padding:0 .4rem; }
      main { padding:.5rem .75rem 6rem; max-width:720px; margin:0 auto; }
      nav { position:fixed; bottom:0; left:0; right:0; display:flex; background:rgba(15,17,21,.95);
            backdrop-filter:blur(12px); border-top:1px solid var(--line); padding-bottom:env(safe-area-inset-bottom); }
      nav button { flex:1; background:none; border:0; color:var(--muted); font-size:.62rem; padding:.5rem 0 .55rem; }
      nav button .ic { display:block; font-size:1.2rem; margin-bottom:.1rem; }
      nav button.active { color:var(--accent); }
      .list { display:flex; flex-direction:column; gap:.4rem; }
      .row { display:flex; align-items:center; gap:.6rem; width:100%; text-align:left; background:var(--panel);
             border:1px solid var(--line); border-radius:14px; padding:.7rem .8rem; color:inherit; }
      .row-main { flex:1; min-width:0; background:none; border:0; color:inherit; text-align:left; padding:0; }
      .row-title { font-size:.97rem; font-weight:500; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
      .row-title.strike { text-decoration:line-through; color:var(--muted); }
      .row-sub { font-size:.78rem; color:var(--muted); margin-top:.15rem; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
      .chev { color:var(--muted); }
      .empty { color:var(--muted); text-align:center; padding:2.5rem 1rem; }
      .loading { color:var(--muted); text-align:center; padding:2rem; }
      .chips { display:flex; gap:.4rem; overflow-x:auto; padding:.25rem 0 .6rem; }
      .chip { flex:0 0 auto; background:var(--panel); border:1px solid var(--line); color:var(--muted);
              border-radius:999px; padding:.35rem .8rem; font-size:.82rem; }
      .chip.active { background:var(--accent); border-color:var(--accent); color:#fff; }
      .chip.add { color:var(--accent); }
      .checkbox { flex:0 0 auto; width:26px; height:26px; border-radius:50%; border:1.5px solid #3a4250;
                  background:none; color:#fff; font-size:.85rem; }
      .checkbox.on { background:#22a06b; border-color:#22a06b; }
      .detail { display:flex; flex-direction:column; gap:.35rem; }
      .detail label { font-size:.78rem; color:var(--muted); margin-top:.7rem; }
      .detail input, .detail textarea, .detail select {
        width:100%; background:var(--panel); border:1px solid var(--line); color:#fff;
        border-radius:12px; padding:.7rem; font-size:1rem; font-family:inherit; }
      .detail textarea { resize:vertical; }
      .prose { background:var(--panel); border:1px solid var(--line); border-radius:12px; padding:.7rem;
               white-space:pre-wrap; word-wrap:break-word; font-size:.9rem; line-height:1.45; max-height:55vh; overflow:auto; }
      details { background:var(--panel); border:1px solid var(--line); border-radius:12px; padding:.6rem .7rem; margin-top:.5rem; }
      summary { color:var(--muted); }
      button.primary { margin-top:1rem; background:var(--accent); border:0; color:#fff; border-radius:12px;
                       padding:.8rem; font-size:1rem; font-weight:600; }
      button.danger { margin-top:.6rem; background:none; border:1px solid #5a2530; color:#ff8198; border-radius:12px; padding:.7rem; }
      .pill { display:inline-block; font-size:.72rem; padding:.15rem .55rem; border-radius:999px;
              background:#222834; color:#cdd3de; margin:.15rem .2rem 0 0; border:1px solid var(--line); }
      .pill.dot::before { content:"●"; margin-right:.3rem; }
      .toast { position:fixed; left:50%; bottom:5.5rem; transform:translateX(-50%); background:#22a06b; color:#fff;
               padding:.55rem 1rem; border-radius:999px; font-size:.85rem; opacity:0; transition:opacity .2s; z-index:20; }
      .toast.show { opacity:1; }
      .section-h { font-size:.78rem; color:var(--muted); text-transform:uppercase; letter-spacing:.04em; margin:1.1rem 0 .4rem; }
      .meta { display:flex; flex-wrap:wrap; gap:.3rem .9rem; font-size:.82rem; color:var(--muted); margin:.3rem 0; }
      .kv { background:var(--panel); border:1px solid var(--line); border-radius:12px; padding:.55rem .7rem; margin-bottom:.35rem; }
      .kv .k { font-size:.72rem; color:var(--muted); text-transform:uppercase; letter-spacing:.03em; }
      .kv .v { font-size:.95rem; margin-top:.1rem; word-wrap:break-word; }
      .card2 { background:var(--panel); border:1px solid var(--line); border-radius:12px; padding:.6rem .75rem; margin-bottom:.35rem; }
      .card2 .t { font-weight:500; font-size:.92rem; }
      .card2 .s { font-size:.78rem; color:var(--muted); margin-top:.15rem; white-space:pre-wrap; }
      audio { width:100%; margin:.3rem 0 .5rem; }
      .subtask { display:flex; align-items:center; gap:.55rem; padding:.35rem 0; }
      .subtask .sb { width:22px; height:22px; border-radius:6px; border:1.5px solid #3a4250; background:none; color:#fff; font-size:.75rem; flex:0 0 auto; }
      .subtask .sb.on { background:#22a06b; border-color:#22a06b; }
      .subtask .st { font-size:.92rem; }
      .subtask .st.strike { text-decoration:line-through; color:var(--muted); }
      a { color:var(--accent); }
    </style>
    </head>
    <body>
      <header><button id="back" hidden>&lsaquo;</button><h1 id="title">MeetingScribe</h1></header>
      <main id="view"></main>
      <nav id="tabs">
        <button data-tab="today"><span class="ic">&#127968;</span>Today</button>
        <button data-tab="meetings"><span class="ic">&#128197;</span>Meetings</button>
        <button data-tab="tasks"><span class="ic">&#9989;</span>Tasks</button>
        <button data-tab="projects"><span class="ic">&#128193;</span>Projects</button>
        <button data-tab="people"><span class="ic">&#128100;</span>People</button>
        <button data-tab="notes"><span class="ic">&#127908;</span>Notes</button>
        <button data-tab="search"><span class="ic">&#128269;</span>Search</button>
        <button data-tab="chat"><span class="ic">&#129302;</span>Ask AI</button>
      </nav>
      <div class="toast" id="toast"></div>
    <script>
    const view = document.getElementById('view');
    const titleEl = document.getElementById('title');
    const backBtn = document.getElementById('back');
    let stack = [];

    async function api(method, path, body){
      const opts = { method, headers:{} };
      if (body !== undefined){ opts.headers['Content-Type']='application/json'; opts.body=JSON.stringify(body); }
      const res = await fetch('/api'+path, opts);
      if (res.status === 401){ location.href='/'; throw new Error('unauthorized'); }
      if (!res.ok){ throw new Error('HTTP '+res.status); }
      if (res.status === 204) return null;
      return res.json();
    }
    function esc(s){ return (s==null?'':String(s)).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }
    function fmtDate(iso){ if(!iso) return ''; const d=new Date(iso); return isNaN(d.getTime())?'':d.toLocaleString([],{month:'short',day:'numeric',year:'numeric',hour:'2-digit',minute:'2-digit'}); }
    function fmtDay(iso){ if(!iso) return ''; const d=new Date(iso); return isNaN(d.getTime())?'':d.toLocaleDateString([],{month:'short',day:'numeric',year:'numeric'}); }
    function dayValue(iso){ if(!iso) return ''; const d=new Date(iso); if(isNaN(d.getTime())) return ''; return d.toISOString().slice(0,10); }
    function dur(sec){ sec=Math.round(sec||0); const m=Math.floor(sec/60), s=sec%60; return m+':'+(s<10?'0':'')+s; }
    function toast(msg){ const t=document.getElementById('toast'); t.textContent=msg; t.classList.add('show'); setTimeout(()=>t.classList.remove('show'),1400); }

    function go(render, title){ stack.push({render,title}); paint(); }
    function back(){ if(stack.length>1){ stack.pop(); paint(); } }
    backBtn.onclick = back;
    async function paint(){
      const top = stack[stack.length-1];
      titleEl.textContent = top.title;
      backBtn.hidden = stack.length<=1;
      view.innerHTML = '<div class="loading">Loading…</div>';
      try { await top.render(); }
      catch(e){ view.innerHTML = '<div class="empty">'+esc(e.message)+'</div>'; }
    }

    const TABS = {
      today:['Today', renderToday],
      meetings:['Meetings', renderMeetings],
      tasks:['Tasks', renderTasks],
      projects:['Projects', renderProjects],
      people:['People', renderPeople],
      notes:['Voice notes', renderNotes],
      search:['Search', renderSearch],
      chat:['Ask AI', renderChat]
    };
    let chatLog=[];
    const HEALTH_COLORS = { thriving:'#74e0bc', steady:'#8ab4ff', drifting:'#ffce6b', overdue:'#ff7a8a' };
    const RELTYPES = [['unset','—'],['romantic_partner','Partner'],['family_member','Family'],['close_friend','Close Friend'],['friend','Friend'],['colleague','Colleague'],['acquaintance','Acquaintance']];
    function healthPill(h){
      if(!h) return '';
      const c = HEALTH_COLORS[h.band] || '#9aa3b2';
      const label = (h.band||'').charAt(0).toUpperCase()+(h.band||'').slice(1);
      return '<span class="pill" style="color:'+c+';border-color:'+c+'66">'+esc(label)+' '+h.score+'</span>';
    }
    function openTab(tab){
      document.querySelectorAll('#tabs button').forEach(b=>b.classList.toggle('active', b.dataset.tab===tab));
      const t = TABS[tab];
      stack = [{render:t[1], title:t[0]}];
      paint();
    }
    document.querySelectorAll('#tabs button').forEach(b=> b.onclick=()=>openTab(b.dataset.tab));

    function listRow(title, sub, onClick, trailing){
      const row=document.createElement('button'); row.className='row';
      row.innerHTML='<div class="row-main"><div class="row-title">'+esc(title)+'</div><div class="row-sub">'+esc(sub)+'</div></div>'+(trailing||'<span class="chev">&rsaquo;</span>');
      row.onclick=onClick; return row;
    }
    function kv(k,v){ return '<div class="kv"><div class="k">'+esc(k)+'</div><div class="v">'+esc(v)+'</div></div>'; }
    function pills(arr){ return (arr||[]).map(x=>'<span class="pill">'+esc(x)+'</span>').join(''); }
    function sectionH(t){ return '<div class="section-h">'+esc(t)+'</div>'; }
    function labelDots(labels){ return (labels||[]).map(l=>'<span class="pill dot" style="color:'+esc(l.colorHex||'#ccc')+'">'+esc(l.name)+'</span>').join(''); }

    // ---- Today (home) ----
    async function renderToday(){
      const data = await api('GET','/today');
      view.innerHTML='';
      let any=false;
      if(data.drift && data.drift.length){
        any=true;
        const sh=document.createElement('div'); sh.innerHTML=sectionH('Stay connected'); view.appendChild(sh);
        const list=document.createElement('div'); list.className='list';
        data.drift.forEach(p=>{
          const h=p.health||{};
          const sub=[p.relationshipLabel, (h.daysSinceLast!=null? h.daysSinceLast+'d since contact':'')].filter(Boolean).join(' · ');
          list.appendChild(listRow(p.name, sub, ()=>go(()=>renderPersonDetail(p.id), p.name), healthPill(h)+'<span class="chev">&rsaquo;</span>'));
        });
        view.appendChild(list);
      }
      if(data.dueTasks && data.dueTasks.length){
        any=true;
        const sh=document.createElement('div'); sh.innerHTML=sectionH('Due soon'); view.appendChild(sh);
        const list=document.createElement('div'); list.className='list';
        data.dueTasks.forEach(t=> list.appendChild(taskRow(t, ()=>go(()=>renderTaskDetail(t.id),'Task'))));
        view.appendChild(list);
      }
      if(data.recentMeetings && data.recentMeetings.length){
        any=true;
        const sh=document.createElement('div'); sh.innerHTML=sectionH('Recent meetings'); view.appendChild(sh);
        const list=document.createElement('div'); list.className='list';
        data.recentMeetings.forEach(m=>{
          const sub=fmtDate(m.start)+(m.hasSummary?' · ✓':'');
          list.appendChild(listRow(m.title, sub, ()=>go(()=>renderMeetingDetail(m.id), m.title)));
        });
        view.appendChild(list);
      }
      if(!any) view.innerHTML='<div class="empty">All clear — nothing needs your attention.</div>';
    }

    // ---- Meetings ----
    async function renderMeetings(){
      const data = await api('GET','/meetings?limit=300');
      view.innerHTML='';
      const list=document.createElement('div'); list.className='list';
      data.meetings.forEach(m=>{
        const sub=fmtDate(m.start)+' · '+m.attendees.length+' attendee(s)'+(m.hasSummary?' · ✓':'');
        list.appendChild(listRow(m.title, sub, ()=>go(()=>renderMeetingDetail(m.id), m.title)));
      });
      if(!data.meetings.length) list.innerHTML='<div class="empty">No meetings yet.</div>';
      view.appendChild(list);
    }
    async function renderMeetingDetail(id){
      const m = await api('GET','/meetings/'+id);
      view.innerHTML='';
      const c=document.createElement('div'); c.className='detail';
      let h='<label>Title</label><input id="m-title" value="'+esc(m.title)+'">';
      h+='<div class="meta"><span>'+esc(fmtDate(m.start))+'</span>'+(m.calendarName?'<span>'+esc(m.calendarName)+'</span>':'')+(m.isImpromptu?'<span>Ad-hoc</span>':'')+(m.isImported?'<span>Imported</span>':'')+'</div>';
      if(m.tags && m.tags.length) h+='<div>'+m.tags.map(t=>'<span class="pill">'+esc((t.symbol?t.symbol+' ':'')+t.name)+'</span>').join('')+'</div>';
      if(m.location) h+=kv('Location', m.location);
      if(m.conferenceURL) h+='<div class="kv"><div class="k">Conference</div><div class="v"><a href="'+esc(m.conferenceURL)+'" target="_blank" rel="noopener">'+esc(m.conferenceURL)+'</a></div></div>';
      if(m.attendees && m.attendees.length) h+='<div class="kv"><div class="k">Attendees</div><div class="v">'+pills(m.attendees)+'</div></div>';
      if(m.audio && m.audio.length){ h+=sectionH('Audio'); m.audio.forEach(tr=>{ h+='<div class="row-sub" style="margin-top:.3rem">'+(tr==='mic'?'Microphone':'System')+'</div><audio controls preload="none" src="/api/meetings/'+id+'/audio?track='+tr+'"></audio>'; }); }
      h+=sectionH('Summary');
      h+='<textarea id="m-summary" rows="6">'+esc(m.summary||'')+'</textarea>';
      if(m.decisions && m.decisions.length){ h+=sectionH('Decisions'); m.decisions.forEach(d=>{ h+='<div class="card2"><div class="t">'+esc(d.text)+'</div></div>'; }); }
      h+=sectionH('My notes');
      h+='<textarea id="m-notes" rows="5">'+esc(m.notes)+'</textarea>';
      h+='<button class="primary" id="m-save">Save</button>';
      c.innerHTML=h; view.appendChild(c);

      if(m.actionItems && m.actionItems.length){
        const sh=document.createElement('div'); sh.innerHTML=sectionH('Action items'); view.appendChild(sh);
        const list=document.createElement('div'); list.className='list';
        m.actionItems.forEach(t=> list.appendChild(taskRow(t, ()=>go(()=>renderTaskDetail(t.id),'Task'))));
        view.appendChild(list);
      }
      if(m.peopleMentioned && m.peopleMentioned.length){
        const sh=document.createElement('div'); sh.innerHTML=sectionH('People'); view.appendChild(sh);
        const list=document.createElement('div'); list.className='list';
        m.peopleMentioned.forEach(p=> list.appendChild(listRow(p.name, p.company||'', ()=>go(()=>renderPersonDetail(p.id), p.name))));
        view.appendChild(list);
      }
      if(m.transcript){ const d=document.createElement('details'); d.innerHTML='<summary>Transcript</summary><div class="prose">'+esc(m.transcript)+'</div>'; view.appendChild(d); }

      document.getElementById('m-save').onclick=async()=>{
        await api('PUT','/meetings/'+id,{
          userTitle:document.getElementById('m-title').value,
          notes:document.getElementById('m-notes').value,
          summary:document.getElementById('m-summary').value
        });
        toast('Saved');
      };
    }

    // ---- Tasks ----
    function taskRow(t, onClick){
      const done = t.status==='completed';
      const row=document.createElement('div'); row.className='row';
      const box=document.createElement('button'); box.className='checkbox'+(done?' on':''); box.textContent=done?'✓':'';
      box.onclick=async(e)=>{ e.stopPropagation(); await api('PUT','/tasks/'+t.id,{status:done?'open':'completed'}); paint(); };
      const main=document.createElement('button'); main.className='row-main';
      const bits=[]; if(t.projectName) bits.push(t.projectName); bits.push(t.priority);
      if(t.dueDate) bits.push('due '+fmtDay(t.dueDate));
      if(t.subtasks && t.subtasks.length){ const dn=t.subtasks.filter(s=>s.done).length; bits.push(dn+'/'+t.subtasks.length+' subtasks'); }
      main.innerHTML='<div class="row-title'+(done?' strike':'')+'">'+esc(t.title)+'</div><div class="row-sub">'+esc(bits.join(' · '))+'</div>'+(t.labels&&t.labels.length?'<div>'+labelDots(t.labels)+'</div>':'');
      main.onclick=onClick;
      row.appendChild(box); row.appendChild(main); return row;
    }
    let taskFilter='';
    async function renderTasks(){
      view.innerHTML='';
      const bar=document.createElement('div'); bar.className='chips';
      [['','All'],['open','Open'],['inProgress','In progress'],['completed','Done']].forEach(p=>{
        const b=document.createElement('button'); b.className='chip'+(taskFilter===p[0]?' active':''); b.textContent=p[1];
        b.onclick=()=>{ taskFilter=p[0]; paint(); }; bar.appendChild(b);
      });
      const add=document.createElement('button'); add.className='chip add'; add.textContent='+ New';
      add.onclick=async()=>{ const t=prompt('New task'); if(t&&t.trim()){ await api('POST','/tasks',{title:t.trim()}); paint(); } };
      bar.appendChild(add); view.appendChild(bar);

      const data = await api('GET','/tasks'+(taskFilter?'?status='+taskFilter:''));
      const list=document.createElement('div'); list.className='list';
      data.tasks.forEach(t=> list.appendChild(taskRow(t, ()=>go(()=>renderTaskDetail(t.id),'Task'))));
      if(!data.tasks.length) list.innerHTML='<div class="empty">No tasks.</div>';
      view.appendChild(list);
    }
    async function renderTaskDetail(id){
      const t = await api('GET','/tasks/'+id);
      const proj = await api('GET','/projects');
      view.innerHTML='';
      const c=document.createElement('div'); c.className='detail';
      const opt=(v,l,sel)=>'<option value="'+esc(v)+'"'+(sel?' selected':'')+'>'+esc(l)+'</option>';
      let projOpts=opt('','No project',!t.projectID);
      proj.projects.forEach(p=> projOpts+=opt(p.id,p.name,p.id===t.projectID));
      let h=
        '<label>Title</label><input id="t-title" value="'+esc(t.title)+'">'+
        '<label>Status</label><select id="t-status">'+opt('open','Open',t.status==='open')+opt('inProgress','In progress',t.status==='inProgress')+opt('completed','Completed',t.status==='completed')+'</select>'+
        '<label>Priority</label><select id="t-pri">'+['low','medium','high','urgent'].map(p=>opt(p,p,t.priority===p)).join('')+'</select>'+
        '<label>Start date</label><input id="t-start" type="date" value="'+dayValue(t.startDate)+'">'+
        '<label>Due date</label><input id="t-due" type="date" value="'+dayValue(t.dueDate)+'">'+
        '<label>Owner</label><input id="t-owner" value="'+esc(t.owner)+'">'+
        '<label>Project</label><select id="t-proj">'+projOpts+'</select>'+
        '<label>Notes</label><textarea id="t-notes" rows="4">'+esc(t.notes)+'</textarea>'+
        '<button class="primary" id="t-save">Save</button>';
      if(t.labels && t.labels.length) h+=sectionH('Labels')+'<div>'+labelDots(t.labels)+'</div>';
      c.innerHTML=h; view.appendChild(c);

      // Subtasks
      const sh=document.createElement('div'); sh.innerHTML=sectionH('Subtasks'); view.appendChild(sh);
      const subWrap=document.createElement('div');
      (t.subtasks||[]).forEach(s=>{
        const r=document.createElement('div'); r.className='subtask';
        const b=document.createElement('button'); b.className='sb'+(s.done?' on':''); b.textContent=s.done?'✓':'';
        b.onclick=async()=>{ await api('PUT','/tasks/'+id+'/subtasks/'+s.id); paint(); };
        const sp=document.createElement('div'); sp.className='st'+(s.done?' strike':''); sp.textContent=s.title;
        r.appendChild(b); r.appendChild(sp); subWrap.appendChild(r);
      });
      const addSub=document.createElement('button'); addSub.className='chip add'; addSub.textContent='+ Add subtask'; addSub.style.marginTop='.4rem';
      addSub.onclick=async()=>{ const v=prompt('Subtask'); if(v&&v.trim()){ await api('POST','/tasks/'+id+'/subtasks',{title:v.trim()}); paint(); } };
      subWrap.appendChild(addSub); view.appendChild(subWrap);

      const del=document.createElement('button'); del.className='danger'; del.textContent='Delete task';
      del.onclick=async()=>{ if(confirm('Delete this task?')){ await api('DELETE','/tasks/'+id); back(); } };
      view.appendChild(del);

      document.getElementById('t-save').onclick=async()=>{
        const dv=document.getElementById('t-due').value, sv=document.getElementById('t-start').value;
        await api('PUT','/tasks/'+id,{
          title:document.getElementById('t-title').value,
          status:document.getElementById('t-status').value,
          priority:document.getElementById('t-pri').value,
          owner:document.getElementById('t-owner').value,
          projectID:document.getElementById('t-proj').value||null,
          dueDate: dv? new Date(dv+'T12:00:00').toISOString() : null,
          startDate: sv? new Date(sv+'T12:00:00').toISOString() : null,
          notes:document.getElementById('t-notes').value
        });
        toast('Saved');
      };
    }

    // ---- Projects ----
    async function renderProjects(){
      view.innerHTML='';
      const bar=document.createElement('div'); bar.className='chips';
      const add=document.createElement('button'); add.className='chip add'; add.textContent='+ New project';
      add.onclick=async()=>{ const n=prompt('Project name'); if(n&&n.trim()){ await api('POST','/projects',{name:n.trim()}); paint(); } };
      bar.appendChild(add); view.appendChild(bar);
      const data = await api('GET','/projects');
      const list=document.createElement('div'); list.className='list';
      data.projects.forEach(p=>{
        const sub=(p.initiative?p.initiative+' · ':'')+p.openCount+' open'+(p.status!=='active'?' · '+p.status:'');
        list.appendChild(listRow((p.icon?'':'')+p.name, sub, ()=>go(()=>renderProjectDetail(p.id), p.name)));
      });
      if(!data.projects.length) list.innerHTML='<div class="empty">No projects yet.</div>';
      view.appendChild(list);
    }
    async function renderProjectDetail(id){
      const p = await api('GET','/projects/'+id);
      view.innerHTML='';
      const c=document.createElement('div'); c.className='detail';
      let h='<label>Name</label><input id="pr-name" value="'+esc(p.name)+'">';
      h+='<div class="meta">'+(p.initiative?'<span>'+esc(p.initiative)+'</span>':'')+'<span>'+esc(p.status)+'</span><span>'+p.openCount+' open</span></div>';
      h+='<label>Notes</label><textarea id="pr-body" rows="6">'+esc(p.body)+'</textarea>';
      h+='<button class="primary" id="pr-save">Save</button>';
      c.innerHTML=h; view.appendChild(c);

      if(p.children && p.children.length){
        const sh=document.createElement('div'); sh.innerHTML=sectionH('Sub-projects'); view.appendChild(sh);
        const list=document.createElement('div'); list.className='list';
        p.children.forEach(ch=> list.appendChild(listRow(ch.name, ch.openCount+' open', ()=>go(()=>renderProjectDetail(ch.id), ch.name))));
        view.appendChild(list);
      }

      // Tasks grouped by section
      const sh2=document.createElement('div'); sh2.innerHTML=sectionH('Tasks'); view.appendChild(sh2);
      const sections=(p.sections||[]).slice();
      const tasks=p.tasks||[];
      const groups=[];
      groups.push({name:null, items:tasks.filter(t=>!t.sectionID)});
      sections.forEach(s=> groups.push({name:s.name, items:tasks.filter(t=>t.sectionID===s.id)}));
      groups.forEach(g=>{
        if(!g.items.length) return;
        if(g.name){ const sn=document.createElement('div'); sn.className='row-sub'; sn.style.margin='.5rem 0 .2rem'; sn.textContent=g.name; view.appendChild(sn); }
        const list=document.createElement('div'); list.className='list';
        g.items.forEach(t=> list.appendChild(taskRow(t, ()=>go(()=>renderTaskDetail(t.id),'Task'))));
        view.appendChild(list);
      });
      if(!tasks.length){ const e=document.createElement('div'); e.className='empty'; e.textContent='No tasks.'; view.appendChild(e); }

      if(p.meetings && p.meetings.length){
        const sh=document.createElement('div'); sh.innerHTML=sectionH('Linked meetings'); view.appendChild(sh);
        const list=document.createElement('div'); list.className='list';
        p.meetings.forEach(m=> list.appendChild(listRow(m.title, fmtDate(m.start), ()=>go(()=>renderMeetingDetail(m.id), m.title))));
        view.appendChild(list);
      }

      document.getElementById('pr-save').onclick=async()=>{
        await api('PUT','/projects/'+id,{ name:document.getElementById('pr-name').value, body:document.getElementById('pr-body').value });
        toast('Saved');
      };
    }

    // ---- People ----
    async function renderPeople(){
      view.innerHTML='';
      const bar=document.createElement('div'); bar.className='chips';
      const add=document.createElement('button'); add.className='chip add'; add.textContent='+ New person';
      add.onclick=async()=>{ const n=prompt('Name'); if(n&&n.trim()){ await api('POST','/people',{name:n.trim()}); paint(); } };
      bar.appendChild(add); view.appendChild(bar);
      const data = await api('GET','/people');
      const list=document.createElement('div'); list.className='list';
      data.people.forEach(p=>{
        const sub=[p.relationshipLabel&&p.relationshipLabel!=='Unset'?p.relationshipLabel:null,p.role,p.company].filter(Boolean).join(' · ')||(p.email||'');
        list.appendChild(listRow(p.name, sub, ()=>go(()=>renderPersonDetail(p.id), p.name), healthPill(p.health)+'<span class="chev">&rsaquo;</span>'));
      });
      if(!data.people.length) list.innerHTML='<div class="empty">No people yet.</div>';
      view.appendChild(list);
    }
    async function renderPersonDetail(id){
      const p = await api('GET','/people/'+id);
      view.innerHTML='';
      const c=document.createElement('div'); c.className='detail';
      const ropt=(v,l,sel)=>'<option value="'+esc(v)+'"'+(sel?' selected':'')+'>'+esc(l)+'</option>';
      const relOptions=RELTYPES.map(rt=>ropt(rt[0],rt[1],p.relationshipType===rt[0])).join('');
      let h=
        '<label>Name</label><input id="p-name" value="'+esc(p.name)+'">'+
        '<label>Company</label><input id="p-co" value="'+esc(p.company)+'">'+
        '<label>Role</label><input id="p-role" value="'+esc(p.role)+'">'+
        '<label>Email</label><input id="p-email" value="'+esc(p.email)+'">'+
        '<label>Relationship</label><select id="p-rel">'+relOptions+'</select>'+
        '<label>Check in every (days · blank = default)</label><input id="p-cadence" type="number" min="1" value="'+(p.checkInCadenceDays||'')+'">'+
        '<label>Notes / bio</label><textarea id="p-bio" rows="4">'+esc(p.bio)+'</textarea>'+
        '<button class="primary" id="p-save">Save</button>';
      c.innerHTML=h; view.appendChild(c);

      const info=document.createElement('div');
      let ih='';
      if(p.health || (p.relationshipLabel && p.relationshipLabel!=='Unset')) ih+='<div style="margin:.4rem 0">'+healthPill(p.health)+(p.relationshipLabel&&p.relationshipLabel!=='Unset'?' <span class="pill">'+esc(p.relationshipLabel)+'</span>':'')+'</div>';
      if(p.emails && p.emails.length>1) ih+=kv('Emails', p.emails.join(', '));
      if(p.phones && p.phones.length) ih+=kv('Phone', p.phones.join(', '));
      if(p.addresses && p.addresses.length) ih+=kv('Address', p.addresses.join(' · '));
      if(p.birthday) ih+=kv('Birthday', fmtDay(p.birthday));
      if(p.tags && p.tags.length) ih+='<div class="section-h">Tags</div><div>'+pills(p.tags)+'</div>';
      if(p.favorites && p.favorites.length) ih+='<div class="section-h">Favorites</div><div>'+pills(p.favorites)+'</div>';
      info.innerHTML=ih; view.appendChild(info);

      // Quick-log an encounter — bumps recency + health.
      const logBtn=document.createElement('button'); logBtn.className='chip add'; logBtn.textContent='+ Log encounter'; logBtn.style.marginTop='.5rem';
      logBtn.onclick=async()=>{ const t=prompt('What happened? (e.g. Coffee, Call, Dinner)'); if(t&&t.trim()){ const n=prompt('Notes (optional)')||''; await api('POST','/people/'+id+'/encounters',{title:t.trim(),notes:n}); toast('Logged'); paint(); } };
      view.appendChild(logBtn);

      function cards(title, arr, render){ if(!arr||!arr.length) return; const sh=document.createElement('div'); sh.innerHTML=sectionH(title); view.appendChild(sh); const w=document.createElement('div'); arr.forEach(x=>{ const d=document.createElement('div'); d.className='card2'; d.innerHTML=render(x); w.appendChild(d); }); view.appendChild(w); }
      cards('Memories', p.memories, m=>'<div class="t">'+esc(m.text)+'</div>'+(m.occurredOn?'<div class="s">'+esc(fmtDay(m.occurredOn))+'</div>':''));
      cards('Notes & analyses', p.attachedNotes, n=>'<div class="t">'+esc(n.title)+' <span class="pill">'+esc(n.kind)+'</span></div><div class="s">'+esc(n.body)+'</div>');
      if(p.relationships && p.relationships.length){ const sh=document.createElement('div'); sh.innerHTML=sectionH('Relationships'); view.appendChild(sh); const list=document.createElement('div'); list.className='list'; p.relationships.forEach(r=> list.appendChild(listRow(r.toPersonName, r.label, ()=>go(()=>renderPersonDetail(r.toPersonID), r.toPersonName)))); view.appendChild(list); }
      if(p.tasks && p.tasks.length){ const sh=document.createElement('div'); sh.innerHTML=sectionH('Tasks'); view.appendChild(sh); const list=document.createElement('div'); list.className='list'; p.tasks.forEach(t=> list.appendChild(taskRow(t, ()=>go(()=>renderTaskDetail(t.id),'Task')))); view.appendChild(list); }
      if(p.mentionedIn && p.mentionedIn.length){ const sh=document.createElement('div'); sh.innerHTML=sectionH('Mentioned in'); view.appendChild(sh); const list=document.createElement('div'); list.className='list'; p.mentionedIn.forEach(m=> list.appendChild(listRow(m.title, fmtDate(m.start), ()=>go(()=>renderMeetingDetail(m.id), m.title)))); view.appendChild(list); }
      if(p.encounters && p.encounters.length){ const sh=document.createElement('div'); sh.innerHTML=sectionH('Encounters'); view.appendChild(sh); const w=document.createElement('div'); p.encounters.slice(0,20).forEach(e=>{ const d=document.createElement('div'); d.className='card2'; d.innerHTML='<div class="t">'+esc(e.title)+'</div><div class="s">'+esc(e.kind+' · '+fmtDay(e.date)+(e.location?' · '+e.location:''))+(e.summary?'\\n'+esc(e.summary):'')+'</div>'; w.appendChild(d); }); view.appendChild(w); }

      document.getElementById('p-save').onclick=async()=>{
        const cad=document.getElementById('p-cadence').value;
        await api('PUT','/people/'+id,{
          name:document.getElementById('p-name').value,
          company:document.getElementById('p-co').value,
          role:document.getElementById('p-role').value,
          email:document.getElementById('p-email').value,
          relationshipType:document.getElementById('p-rel').value,
          checkInCadenceDays: cad? parseInt(cad,10) : 0,
          bio:document.getElementById('p-bio').value
        });
        toast('Saved'); paint();
      };
    }

    // ---- Voice notes ----
    async function renderNotes(){
      const data = await api('GET','/voicenotes');
      view.innerHTML='';
      const list=document.createElement('div'); list.className='list';
      data.voicenotes.forEach(n=>{
        const sub=fmtDate(n.createdAt)+' · '+dur(n.durationSeconds)+(n.wasDictation?' · dictation':'');
        list.appendChild(listRow(n.title, sub, ()=>go(()=>renderNoteDetail(n.id), n.title)));
      });
      if(!data.voicenotes.length) list.innerHTML='<div class="empty">No voice notes.</div>';
      view.appendChild(list);
    }
    async function renderNoteDetail(id){
      const n = await api('GET','/voicenotes/'+id);
      view.innerHTML='';
      const c=document.createElement('div'); c.className='detail';
      let h='<div class="meta"><span>'+esc(fmtDate(n.createdAt))+'</span><span>'+esc(dur(n.durationSeconds))+'</span></div>';
      if(n.hasAudio) h+='<audio controls preload="none" src="/api/voicenotes/'+id+'/audio"></audio>';
      h+='<label>Transcript</label><textarea id="n-tx" rows="8">'+esc(n.transcript)+'</textarea>';
      h+='<button class="primary" id="n-save">Save transcript</button>';
      if(n.polished){ h+=sectionH('Polished'); h+='<div class="prose">'+esc(n.polished)+'</div>'; }
      h+='<button class="danger" id="n-del">Delete note</button>';
      c.innerHTML=h; view.appendChild(c);
      document.getElementById('n-save').onclick=async()=>{ await api('PUT','/voicenotes/'+id,{transcript:document.getElementById('n-tx').value}); toast('Saved'); };
      document.getElementById('n-del').onclick=async()=>{ if(confirm('Delete this note?')){ await api('DELETE','/voicenotes/'+id); back(); } };
    }

    // ---- Search ----
    async function renderSearch(){
      view.innerHTML='';
      const c=document.createElement('div'); c.className='detail';
      c.innerHTML='<input id="s-q" placeholder="Search everything" autocapitalize="off">';
      view.appendChild(c);
      const results=document.createElement('div'); results.className='list'; results.style.marginTop='.6rem';
      view.appendChild(results);
      const input=document.getElementById('s-q'); input.focus();
      let timer=null;
      input.oninput=()=>{ clearTimeout(timer); timer=setTimeout(run,250); };
      async function run(){
        const q=input.value.trim();
        if(!q){ results.innerHTML=''; return; }
        const data=await api('GET','/search?q='+encodeURIComponent(q));
        results.innerHTML='';
        if(!data.results.length){ results.innerHTML='<div class="empty">No matches.</div>'; return; }
        data.results.forEach(r=>{
          results.appendChild(listRow(r.title, r.kind+' · '+(r.subtitle||''), ()=>{
            if(r.kind==='meeting') go(()=>renderMeetingDetail(r.id), r.title);
            else if(r.kind==='person') go(()=>renderPersonDetail(r.id), r.title);
            else if(r.kind==='task') go(()=>renderTaskDetail(r.id), 'Task');
            else if(r.kind==='project') go(()=>renderProjectDetail(r.id), r.title);
            else if(r.kind==='voicenote') go(()=>renderNoteDetail(r.id), r.title);
          }));
        });
      }
    }

    // ---- Ask AI (local, vault-grounded) ----
    async function renderChat(){
      view.innerHTML='';
      const log=document.createElement('div'); log.className='list'; view.appendChild(log);
      function addMsg(role,text){
        const d=document.createElement('div'); d.className='card2';
        d.innerHTML='<div style="text-transform:uppercase;font-size:.68rem;color:var(--muted)">'+(role==='you'?'You':'Assistant')+'</div><div class="s" style="white-space:pre-wrap">'+esc(text)+'</div>';
        log.appendChild(d); d.scrollIntoView({block:'end'}); return d;
      }
      if(!chatLog.length){ const e=document.createElement('div'); e.className='empty'; e.textContent='Ask anything about your meetings, people, and tasks. Answered locally by the AI on your Mac — nothing leaves your machine.'; log.appendChild(e); }
      chatLog.forEach(m=>addMsg(m.role,m.text));
      const c=document.createElement('div'); c.className='detail';
      c.innerHTML='<textarea id="chat-q" rows="2" placeholder="e.g. What did I commit to in my last 1:1 with Priya?"></textarea><button class="primary" id="chat-send">Ask</button>';
      view.appendChild(c);
      const send=document.getElementById('chat-send'), q=document.getElementById('chat-q');
      async function run(){
        const text=q.value.trim(); if(!text) return;
        if(!chatLog.length) log.innerHTML='';
        chatLog.push({role:'you',text}); addMsg('you',text); q.value='';
        send.disabled=true; send.textContent='Thinking…';
        const bubble=addMsg('ai','…');
        try{ const r=await api('POST','/chat',{question:text}); bubble.querySelector('.s').textContent=r.answer; chatLog.push({role:'ai',text:r.answer}); }
        catch(e){ bubble.querySelector('.s').textContent='Error: '+e.message; }
        send.disabled=false; send.textContent='Ask';
      }
      send.onclick=run;
    }

    openTab('today');
    </script>
    </body>
    </html>
    """
}

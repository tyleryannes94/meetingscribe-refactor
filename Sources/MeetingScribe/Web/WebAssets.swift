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
      main { padding:.5rem .75rem 6rem; max-width:680px; margin:0 auto; }
      nav { position:fixed; bottom:0; left:0; right:0; display:flex; background:rgba(15,17,21,.95);
            backdrop-filter:blur(12px); border-top:1px solid var(--line); padding-bottom:env(safe-area-inset-bottom); }
      nav button { flex:1; background:none; border:0; color:var(--muted); font-size:.7rem; padding:.5rem 0 .55rem; }
      nav button .ic { display:block; font-size:1.25rem; margin-bottom:.1rem; }
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
               white-space:pre-wrap; word-wrap:break-word; font-size:.9rem; line-height:1.45; max-height:50vh; overflow:auto; }
      details { background:var(--panel); border:1px solid var(--line); border-radius:12px; padding:.6rem .7rem; margin-top:.5rem; }
      summary { color:var(--muted); }
      button.primary { margin-top:1rem; background:var(--accent); border:0; color:#fff; border-radius:12px;
                       padding:.8rem; font-size:1rem; font-weight:600; }
      button.danger { margin-top:.6rem; background:none; border:1px solid #5a2530; color:#ff8198; border-radius:12px; padding:.7rem; }
      .badge { display:inline-block; font-size:.7rem; padding:.1rem .45rem; border-radius:6px; background:#222834; color:var(--muted); }
      .toast { position:fixed; left:50%; bottom:5.5rem; transform:translateX(-50%); background:#22a06b; color:#fff;
               padding:.55rem 1rem; border-radius:999px; font-size:.85rem; opacity:0; transition:opacity .2s; z-index:20; }
      .toast.show { opacity:1; }
      .section-h { font-size:.78rem; color:var(--muted); text-transform:uppercase; letter-spacing:.04em; margin:1rem 0 .4rem; }
      a { color:var(--accent); }
    </style>
    </head>
    <body>
      <header><button id="back" hidden>&lsaquo;</button><h1 id="title">MeetingScribe</h1></header>
      <main id="view"></main>
      <nav id="tabs">
        <button data-tab="meetings"><span class="ic">&#128197;</span>Meetings</button>
        <button data-tab="tasks"><span class="ic">&#9989;</span>Tasks</button>
        <button data-tab="people"><span class="ic">&#128100;</span>People</button>
        <button data-tab="projects"><span class="ic">&#128193;</span>Projects</button>
        <button data-tab="search"><span class="ic">&#128269;</span>Search</button>
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
    function esc(s){ return (s==null?'':String(s)).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
    function fmtDate(iso){ if(!iso) return ''; const d=new Date(iso); return isNaN(d.getTime())?'':d.toLocaleString([],{month:'short',day:'numeric',hour:'2-digit',minute:'2-digit'}); }
    function dayValue(iso){ if(!iso) return ''; const d=new Date(iso); if(isNaN(d.getTime())) return ''; return d.toISOString().slice(0,10); }
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
      meetings:['Meetings', renderMeetings],
      tasks:['Tasks', renderTasks],
      people:['People', renderPeople],
      projects:['Projects', renderProjects],
      search:['Search', renderSearch]
    };
    function openTab(tab){
      document.querySelectorAll('#tabs button').forEach(b=>b.classList.toggle('active', b.dataset.tab===tab));
      const [title, fn] = TABS[tab];
      stack = [{render:fn, title}];
      paint();
    }
    document.querySelectorAll('#tabs button').forEach(b=> b.onclick=()=>openTab(b.dataset.tab));

    function listRow(title, sub, onClick){
      const row=document.createElement('button'); row.className='row';
      row.innerHTML='<div class="row-main"><div class="row-title">'+esc(title)+'</div><div class="row-sub">'+esc(sub)+'</div></div><span class="chev">&rsaquo;</span>';
      row.onclick=onClick; return row;
    }

    // ---- Meetings ----
    async function renderMeetings(){
      const data = await api('GET','/meetings?limit=200');
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
      let html='<label>Title</label><input id="m-title" value="'+esc(m.title)+'">';
      if(m.summary) html+='<label>Summary</label><div class="prose">'+esc(m.summary)+'</div>';
      html+='<label>My notes</label><textarea id="m-notes" rows="6">'+esc(m.notes)+'</textarea>';
      html+='<button class="primary" id="m-save">Save</button>';
      if(m.transcript) html+='<details><summary>Transcript</summary><div class="prose">'+esc(m.transcript)+'</div></details>';
      c.innerHTML=html; view.appendChild(c);
      document.getElementById('m-save').onclick=async()=>{
        await api('PUT','/meetings/'+id,{ userTitle:document.getElementById('m-title').value, notes:document.getElementById('m-notes').value });
        toast('Saved');
      };
    }

    // ---- Tasks ----
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
      data.tasks.forEach(t=>{
        const done = t.status==='completed';
        const row=document.createElement('div'); row.className='row';
        const box=document.createElement('button'); box.className='checkbox'+(done?' on':''); box.textContent=done?'✓':'';
        box.onclick=async(e)=>{ e.stopPropagation(); await api('PUT','/tasks/'+t.id,{status:done?'open':'completed'}); paint(); };
        const main=document.createElement('button'); main.className='row-main';
        const sub=(t.projectName?t.projectName+' · ':'')+t.priority+(t.dueDate?' · due '+fmtDate(t.dueDate):'');
        main.innerHTML='<div class="row-title'+(done?' strike':'')+'">'+esc(t.title)+'</div><div class="row-sub">'+esc(sub)+'</div>';
        main.onclick=()=>go(()=>renderTaskDetail(t.id), 'Task');
        row.appendChild(box); row.appendChild(main); list.appendChild(row);
      });
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
      c.innerHTML=
        '<label>Title</label><input id="t-title" value="'+esc(t.title)+'">'+
        '<label>Status</label><select id="t-status">'+opt('open','Open',t.status==='open')+opt('inProgress','In progress',t.status==='inProgress')+opt('completed','Completed',t.status==='completed')+'</select>'+
        '<label>Priority</label><select id="t-pri">'+['low','medium','high','urgent'].map(p=>opt(p,p,t.priority===p)).join('')+'</select>'+
        '<label>Due date</label><input id="t-due" type="date" value="'+dayValue(t.dueDate)+'">'+
        '<label>Project</label><select id="t-proj">'+projOpts+'</select>'+
        '<label>Notes</label><textarea id="t-notes" rows="4">'+esc(t.notes)+'</textarea>'+
        '<button class="primary" id="t-save">Save</button>'+
        '<button class="danger" id="t-del">Delete task</button>';
      view.appendChild(c);
      document.getElementById('t-save').onclick=async()=>{
        const dv=document.getElementById('t-due').value;
        await api('PUT','/tasks/'+id,{
          title:document.getElementById('t-title').value,
          status:document.getElementById('t-status').value,
          priority:document.getElementById('t-pri').value,
          projectID:document.getElementById('t-proj').value||null,
          dueDate: dv? new Date(dv+'T12:00:00').toISOString() : null,
          notes:document.getElementById('t-notes').value
        });
        toast('Saved'); back();
      };
      document.getElementById('t-del').onclick=async()=>{ if(confirm('Delete this task?')){ await api('DELETE','/tasks/'+id); back(); } };
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
        const sub=[p.role,p.company].filter(Boolean).join(' · ')||(p.email||'');
        list.appendChild(listRow(p.name, sub, ()=>go(()=>renderPersonDetail(p.id), p.name)));
      });
      if(!data.people.length) list.innerHTML='<div class="empty">No people yet.</div>';
      view.appendChild(list);
    }
    async function renderPersonDetail(id){
      const p = await api('GET','/people/'+id);
      view.innerHTML='';
      const c=document.createElement('div'); c.className='detail';
      let html=
        '<label>Name</label><input id="p-name" value="'+esc(p.name)+'">'+
        '<label>Company</label><input id="p-co" value="'+esc(p.company)+'">'+
        '<label>Role</label><input id="p-role" value="'+esc(p.role)+'">'+
        '<label>Email</label><input id="p-email" value="'+esc(p.email)+'">'+
        '<label>Notes</label><textarea id="p-bio" rows="4">'+esc(p.bio)+'</textarea>'+
        '<button class="primary" id="p-save">Save</button>';
      if(p.tags && p.tags.length) html+='<div class="section-h">Tags</div><div>'+p.tags.map(t=>'<span class="badge">'+esc(t)+'</span>').join(' ')+'</div>';
      if(p.tasks && p.tasks.length){ html+='<div class="section-h">Tasks</div>'; p.tasks.forEach(t=>{ html+='<div class="row"><div class="row-main"><div class="row-title">'+esc(t.title)+'</div><div class="row-sub">'+esc(t.status)+'</div></div></div>'; }); }
      if(p.encounters && p.encounters.length){ html+='<div class="section-h">Recent encounters</div>'; p.encounters.slice(0,15).forEach(e=>{ html+='<div class="row"><div class="row-main"><div class="row-title">'+esc(e.title)+'</div><div class="row-sub">'+esc(e.kind)+' · '+fmtDate(e.date)+'</div></div></div>'; }); }
      c.innerHTML=html; view.appendChild(c);
      document.getElementById('p-save').onclick=async()=>{
        await api('PUT','/people/'+id,{
          name:document.getElementById('p-name').value,
          company:document.getElementById('p-co').value,
          role:document.getElementById('p-role').value,
          email:document.getElementById('p-email').value,
          bio:document.getElementById('p-bio').value
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
        const sub=p.openCount+' open'+(p.status!=='active'?' · '+p.status:'');
        list.appendChild(listRow(p.name, sub, ()=>go(()=>renderProjectDetail(p.id), p.name)));
      });
      if(!data.projects.length) list.innerHTML='<div class="empty">No projects yet.</div>';
      view.appendChild(list);
    }
    async function renderProjectDetail(id){
      const p = await api('GET','/projects/'+id);
      view.innerHTML='';
      const c=document.createElement('div'); c.className='detail';
      let html=
        '<label>Name</label><input id="pr-name" value="'+esc(p.name)+'">'+
        '<label>Notes</label><textarea id="pr-body" rows="6">'+esc(p.body)+'</textarea>'+
        '<button class="primary" id="pr-save">Save</button>';
      if(p.tasks && p.tasks.length){ html+='<div class="section-h">Tasks</div>'; p.tasks.forEach(t=>{ const done=t.status==='completed'; html+='<div class="row"><div class="row-main"><div class="row-title'+(done?' strike':'')+'">'+esc(t.title)+'</div><div class="row-sub">'+esc(t.priority)+'</div></div></div>'; }); }
      c.innerHTML=html; view.appendChild(c);
      document.getElementById('pr-save').onclick=async()=>{
        await api('PUT','/projects/'+id,{ name:document.getElementById('pr-name').value, body:document.getElementById('pr-body').value });
        toast('Saved');
      };
    }

    // ---- Search ----
    async function renderSearch(){
      view.innerHTML='';
      const c=document.createElement('div'); c.className='detail';
      c.innerHTML='<input id="s-q" placeholder="Search meetings, people, tasks, projects" autocapitalize="off">';
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
          const sub=r.kind+' · '+(r.subtitle||'');
          results.appendChild(listRow(r.title, sub, ()=>{
            if(r.kind==='meeting') go(()=>renderMeetingDetail(r.id), r.title);
            else if(r.kind==='person') go(()=>renderPersonDetail(r.id), r.title);
            else if(r.kind==='task') go(()=>renderTaskDetail(r.id), 'Task');
            else if(r.kind==='project') go(()=>renderProjectDetail(r.id), r.title);
          }));
        });
      }
    }

    openTab('meetings');
    </script>
    </body>
    </html>
    """
}

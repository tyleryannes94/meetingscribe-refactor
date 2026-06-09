// data.jsx — shared icons, avatar, and the linked mock dataset.
// Exposes everything on window for the other Babel scripts.

/* ----------------------------- ICONS ----------------------------- */
// Feather-style stand-ins for SF Symbols. Single source so every screen
// uses the same glyph for the same concept.
const PATHS = {
  today:    '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M5 5l1.4 1.4M17.6 17.6L19 19M19 5l-1.4 1.4M6.4 17.6L5 19"/>',
  meetings: '<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/>',
  people:   '<path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>',
  tasks:    '<path d="M9 11l3 3L22 4M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/>',
  voice:    '<path d="M3 12h2M7 8v8M11 5v14M15 9v6M19 11v2"/>',
  search:   '<circle cx="11" cy="11" r="7"/><path d="M21 21l-4-4"/>',
  plus:     '<path d="M12 5v14M5 12h14"/>',
  chevR:    '<path d="M9 18l6-6-6-6"/>',
  chevD:    '<path d="M6 9l6 6 6-6"/>',
  chevL:    '<path d="M15 18l-6-6 6-6"/>',
  mic:      '<path d="M12 2a3 3 0 0 0-3 3v6a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3z"/><path d="M19 10v1a7 7 0 0 1-14 0v-1M12 18v3"/>',
  record:   '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="4" fill="currentColor" stroke="none"/>',
  stop:     '<rect x="6" y="6" width="12" height="12" rx="2" fill="currentColor" stroke="none"/>',
  play:     '<path d="M8 5v14l11-7z" fill="currentColor" stroke="none"/>',
  pause:    '<rect x="6" y="5" width="4" height="14" rx="1" fill="currentColor" stroke="none"/><rect x="14" y="5" width="4" height="14" rx="1" fill="currentColor" stroke="none"/>',
  video:    '<path d="M23 7l-7 5 7 5V7z"/><rect x="1" y="5" width="15" height="14" rx="2"/>',
  download: '<path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8M16 6l-4-4-4 4M12 2v13"/>',
  upload:   '<path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8M8 6l4-4 4 4M12 2v13"/>',
  chat:     '<path d="M21 11.5a8.38 8.38 0 0 1-9 8.32 8.5 8.5 0 0 1-3.9-.9L3 20l1.08-3.1A8.5 8.5 0 0 1 12 3.5a8.38 8.38 0 0 1 9 8z"/>',
  refresh:  '<path d="M23 4v6h-6M1 20v-6h6"/><path d="M3.5 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.5 15"/>',
  settings: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.6 1.6 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.6 1.6 0 0 0-2.7 1.1V21a2 2 0 0 1-4 0v-.1A1.6 1.6 0 0 0 9 19.4a1.6 1.6 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.6 1.6 0 0 0-1.1-2.7H3a2 2 0 0 1 0-4h.1A1.6 1.6 0 0 0 4.6 9a1.6 1.6 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.6 1.6 0 0 0 1.8.3H9a1.6 1.6 0 0 0 1-1.5V3a2 2 0 0 1 4 0v.1a1.6 1.6 0 0 0 2.7 1.1l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.6 1.6 0 0 0-.3 1.8V9a1.6 1.6 0 0 0 1.5 1H21a2 2 0 0 1 0 4h-.1a1.6 1.6 0 0 0-1.5 1z"/>',
  sidebar:  '<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M9 3v18"/>',
  mail:     '<rect x="2" y="4" width="20" height="16" rx="2"/><path d="M22 6l-10 7L2 6"/>',
  phone:    '<path d="M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3 19.5 19.5 0 0 1-6-6 19.8 19.8 0 0 1-3-8.6A2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1.9.4 1.8.7 2.7a2 2 0 0 1-.5 2.1L8.1 9.9a16 16 0 0 0 6 6l1.4-1.2a2 2 0 0 1 2.1-.5c.9.3 1.8.6 2.7.7a2 2 0 0 1 1.7 2z"/>',
  map:      '<path d="M21 10c0 7-9 12-9 12s-9-5-9-12a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/>',
  gift:     '<rect x="3" y="8" width="18" height="4" rx="1"/><path d="M12 8v13M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7M12 8a3 3 0 1 0-3-3c0 1.5 1.5 3 3 3zm0 0a3 3 0 1 1 3-3c0 1.5-1.5 3-3 3z"/>',
  clock:    '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  check:    '<path d="M20 6L9 17l-5-5"/>',
  checkCircle: '<path d="M9 11l3 3L20 5"/><path d="M21 12a9 9 0 1 1-6.2-8.5"/>',
  circle:   '<circle cx="12" cy="12" r="9"/>',
  alert:    '<path d="M10.3 3.9L1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/><path d="M12 9v4M12 17h0"/>',
  flag:     '<path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z"/><path d="M4 22v-7"/>',
  arrowUp:  '<path d="M18 15l-6-6-6 6"/>',
  minus:    '<path d="M5 12h14"/>',
  sparkles: '<path d="M12 3l1.9 4.6L18.5 9.5 13.9 11.4 12 16l-1.9-4.6L5.5 9.5 10.1 7.6z"/><path d="M5 16l.8 2 2 .8-2 .8-.8 2-.8-2-2-.8 2-.8z"/>',
  link:     '<path d="M10 13a5 5 0 0 0 7 0l3-3a5 5 0 0 0-7-7l-1.5 1.5"/><path d="M14 11a5 5 0 0 0-7 0l-3 3a5 5 0 0 0 7 7l1.5-1.5"/>',
  send:     '<path d="M22 2L11 13M22 2l-7 20-4-9-9-4 20-7z"/>',
  doc:      '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/>',
  edit:     '<path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.1 2.1 0 0 1 3 3L12 15l-4 1 1-4z"/>',
  trash:    '<path d="M3 6h18M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>',
  more:     '<circle cx="12" cy="12" r="1.5" fill="currentColor" stroke="none"/><circle cx="19" cy="12" r="1.5" fill="currentColor" stroke="none"/><circle cx="5" cy="12" r="1.5" fill="currentColor" stroke="none"/>',
  filter:   '<path d="M22 3H2l8 9.5V19l4 2v-8.5z"/>',
  calendar: '<rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/>',
  list:     '<path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/>',
  board:    '<rect x="3" y="3" width="6" height="18" rx="1"/><rect x="10" y="3" width="6" height="12" rx="1"/><rect x="17" y="3" width="4" height="8" rx="1"/>',
  table:    '<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M3 9h18M3 15h18M9 3v18"/>',
  inbox:    '<path d="M22 12h-6l-2 3h-4l-2-3H2"/><path d="M5.4 5.1L2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.4-6.9A2 2 0 0 0 16.8 4H7.2a2 2 0 0 0-1.8 1.1z"/>',
  layers:   '<path d="M12 2L2 7l10 5 10-5z"/><path d="M2 17l10 5 10-5M2 12l10 5 10-5"/>',
  bold:     '<path d="M6 4h8a4 4 0 0 1 0 8H6zM6 12h9a4 4 0 0 1 0 8H6z"/>',
  italic:   '<path d="M19 4h-9M14 20H5M15 4L9 20"/>',
  code:     '<path d="M16 18l6-6-6-6M8 6l-6 6 6 6"/>',
  quote:    '<path d="M3 21c3 0 7-1 7-8V5a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2v6a2 2 0 0 0 2 2h2M14 21c3 0 7-1 7-8V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v6a2 2 0 0 0 2 2h2"/>',
  at:       '<circle cx="12" cy="12" r="4"/><path d="M16 8v5a3 3 0 0 0 6 0v-1a10 10 0 1 0-3.9 7.9"/>',
  heart:    '<path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1-1.1a5.5 5.5 0 0 0-7.8 7.8l1 1L12 21l7.8-7.6 1-1a5.5 5.5 0 0 0 0-7.8z"/>',
  grip:     '<circle cx="9" cy="6" r="1.4" fill="currentColor" stroke="none"/><circle cx="15" cy="6" r="1.4" fill="currentColor" stroke="none"/><circle cx="9" cy="12" r="1.4" fill="currentColor" stroke="none"/><circle cx="15" cy="12" r="1.4" fill="currentColor" stroke="none"/><circle cx="9" cy="18" r="1.4" fill="currentColor" stroke="none"/><circle cx="15" cy="18" r="1.4" fill="currentColor" stroke="none"/>',
  external: '<path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6M15 3h6v6M10 14L21 3"/>',
  star:     '<path d="M12 2l3 6.5 7 .9-5 4.8 1.3 7L12 18l-6.3 3.2L7 14.2 2 9.4l7-.9z"/>',
  bell:     '<path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9M13.7 21a2 2 0 0 1-3.4 0"/>',
  pin:      '<path d="M12 17v5M9 10.8V3h6v7.8l2 3.2H7z"/>',
  trend:    '<path d="M23 6l-9.5 9.5-5-5L1 18"/><path d="M17 6h6v6"/>',
  tag:      '<path d="M20.6 13.4L12 22l-9-9V3h10z"/><circle cx="7.5" cy="7.5" r="1.5"/>',
  contact:  '<rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="9" cy="10" r="2.5"/><path d="M5 18a4 4 0 0 1 8 0M16 9h3M16 13h3"/>',
  briefcase:'<rect x="2" y="7" width="20" height="14" rx="2"/><path d="M16 21V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v16"/>',
  globe:    '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a15 15 0 0 1 0 18 15 15 0 0 1 0-18z"/>',
  expand:   '<path d="M15 3h6v6M9 21H3v-6M21 3l-7 7M3 21l7-7"/>',
};
function Icon({ name, size, color, style, className }) {
  const d = PATHS[name] || PATHS.circle;
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke={color || 'currentColor'}
      width={size || 18} height={size || 18} style={style} className={className}
      dangerouslySetInnerHTML={{ __html: d }} />
  );
}

/* ----------------------------- AVATAR ----------------------------- */
const AV_GRADS = {
  coral: 'linear-gradient(150deg,#ff9173,#f06a4c)',
  mint:  'linear-gradient(150deg,#74e0bc,#46c79f)',
  lilac: 'linear-gradient(150deg,#b79cff,#9a7af0)',
  sky:   'linear-gradient(150deg,#8ab4ff,#6b96ec)',
  gold:  'linear-gradient(150deg,#ffce6b,#f0b43f)',
};
const AV_ORDER = ['coral','mint','lilac','sky','gold'];
function gradFor(name){
  let h=0; for(let i=0;i<(name||'').length;i++) h=(h*31+name.charCodeAt(i))>>>0;
  return AV_GRADS[AV_ORDER[h % AV_ORDER.length]];
}
function initials(name){
  const p=(name||'').trim().split(/\s+/);
  return ((p[0]?.[0]||'')+(p[1]?.[0]||'')).toUpperCase() || (name?.[0]||'?').toUpperCase();
}
function Avatar({ name, size=32, grad, radius, style, fontSize }){
  return (
    <div className="av" style={{ width:size, height:size, fontSize: fontSize || size*0.38,
      borderRadius: radius || '34%', background: grad || gradFor(name), ...style }}>
      {initials(name)}
    </div>
  );
}

/* ----------------------------- DATA ----------------------------- */
// People — the relationship graph. Tasks & meetings reference these by id.
const PEOPLE = [
  { id:'maya', name:'Maya Kerr', grad:AV_GRADS.lilac, role:'VP Product', company:'Skio',
    emails:['maya@skio.com','maya.kerr@gmail.com'], phone:'+1 415 555 0142', location:'San Francisco, CA',
    relationship:'Colleague', tags:['Colleague','Skio','Decision-maker'], firstMet:'Mar 2024 · Skio',
    cadence:'Healthy', cadenceDays:14, lastSpokeDays:6, birthday:'Aug 14',
    favorites:['Oat flat white','Trail running','Daughter at Berkeley'],
    memories:['Prefers async updates over standing meetings.','Owns the Skio relationship end-to-end.','Daughter just started college — mentioned in March.'],
    msg:{ total:312, replyMedian:'~4h', youInitiate:68, last30:41, last90:120, sent:130, received:182,
          bars:[40,70,55,90,65,45,80] } },
  { id:'devon', name:'Devon Vale', grad:AV_GRADS.mint, role:'Counsel', company:'Skio',
    emails:['devon@skio.com'], phone:'+1 415 555 0198', location:'Oakland, CA',
    relationship:'Colleague', tags:['Colleague','Skio','Legal'], firstMet:'Apr 2024 · Contract review',
    cadence:'Slipping', cadenceDays:10, lastSpokeDays:18, birthday:'Feb 2',
    favorites:['Espresso','Cycling'],
    memories:['Owns contract redlines. Fast on email, slow on Slack.'],
    msg:{ total:88, replyMedian:'~1d', youInitiate:55, last30:9, last90:24, sent:48, received:40,
          bars:[30,45,20,60,35,50,25] } },
  { id:'jules', name:'Jules Lin', grad:AV_GRADS.sky, role:'Finance Lead', company:'Skio',
    emails:['jules@skio.com'], phone:'+1 628 555 0110', location:'Remote · NYC',
    relationship:'Colleague', tags:['Colleague','Finance'], firstMet:'Jan 2025 · Pricing workshop',
    cadence:'Healthy', cadenceDays:7, lastSpokeDays:2, birthday:'Nov 30',
    favorites:['Matcha','Spreadsheets that tie out'],
    memories:['Building the usage-based pricing model. Loves a clean number.'],
    msg:{ total:201, replyMedian:'~2h', youInitiate:60, last30:33, last90:78, sent:120, received:81,
          bars:[55,60,70,50,85,40,65] } },
  { id:'rae', name:'Rae Adler', grad:AV_GRADS.gold, role:'Designer', company:'Recharge',
    emails:['rae@recharge.com'], phone:'', location:'Austin, TX',
    relationship:'Client', tags:['Client','Recharge','Design'], firstMet:'Sep 2025 · Intro call',
    cadence:'At risk', cadenceDays:21, lastSpokeDays:34, birthday:'Jun 21',
    favorites:['Risograph prints'],
    memories:['Leads the Recharge brand refresh. Visual thinker — send mocks, not docs.'],
    msg:{ total:54, replyMedian:'~6h', youInitiate:72, last30:3, last90:12, sent:38, received:16,
          bars:[20,35,15,25,40,18,22] } },
  { id:'theo', name:'Theo Nash', grad:AV_GRADS.coral, role:'Founder', company:'Northwind',
    emails:['theo@northwind.io'], phone:'+1 917 555 0167', location:'Brooklyn, NY',
    relationship:'Prospect', tags:['Prospect','Northwind'], firstMet:'May 2026 · Conference',
    cadence:'New', cadenceDays:30, lastSpokeDays:5, birthday:'Dec 29',
    favorites:['Natural wine','Early mornings'],
    memories:['Met at SaaStr. Evaluating us vs. an in-house build.'],
    msg:{ total:12, replyMedian:'~1d', youInitiate:90, last30:12, last90:12, sent:11, received:1,
          bars:[10,15,8,20,12,18,14] } },
  { id:'sam', name:'Sam Owens', grad:AV_GRADS.lilac, role:'Engineer', company:'Skio',
    emails:['sam@skio.com'], phone:'', location:'Seattle, WA',
    relationship:'Colleague', tags:['Colleague','Skio','Eng'], firstMet:'Feb 2025 · Standup',
    cadence:'Healthy', cadenceDays:7, lastSpokeDays:3, birthday:'Mar 9',
    favorites:['Cold brew','Mechanical keyboards'],
    memories:['Building the MCP write-back tools. Ping in #infra.'],
    msg:{ total:140, replyMedian:'~3h', youInitiate:50, last30:22, last90:60, sent:70, received:70,
          bars:[45,50,55,48,62,52,58] } },
];
const personById = (id)=> PEOPLE.find(p=>p.id===id);

// Meetings — reference attendees by person id. "live" is the in-progress one.
const MEETINGS = [
  { id:'m-now', title:'Product × Design — Do not book over', when:'today', time:'11:15 AM', dur:'45m',
    range:'11:15 AM – 12:00 PM', date:'Tue, Jun 9', source:'System + Mic', live:true,
    attendees:['maya','sam','jules'], extra:['phelipe@skio.com'], link:'meet.google.com/gqo-dyhn-mkh',
    tags:['Skio','Product'], status:'recording' },
  { id:'m-sync', title:'Product Sync — Skio', when:'today', time:'10:30 AM', dur:'30m',
    range:'10:30–11:00 AM', date:'Tue, Jun 9', source:'System + Mic',
    attendees:['maya','devon','jules'], link:'meet.google.com/abc-defg-hij',
    tags:['Skio','Planning'], status:'summary' },
  { id:'m-analytics', title:'Skio Analytics Team Sync', when:'today', time:'10:00 AM', dur:'30m',
    range:'10:00–10:30 AM', date:'Tue, Jun 9', source:'System + Mic',
    attendees:['sam','jules'], tags:['Skio'], status:'transcribed' },
  { id:'m-roadmap', title:'Planning Call — Q3 Roadmap', when:'upcoming', time:'2:00 PM', dur:'60m',
    range:'2:00–3:00 PM', date:'Tue, Jun 9', source:'Google Meet',
    attendees:['maya','jules','sam'], link:'meet.google.com/q3r-plan-xyz', tags:['Planning'], status:'scheduled' },
  { id:'m-recharge', title:'Recharge — Weekly Standup', when:'upcoming', time:'4:00 PM', dur:'30m',
    range:'4:00–4:30 PM', date:'Tue, Jun 9', source:'Zoom',
    attendees:['rae'], tags:['Recharge'], status:'scheduled' },
  { id:'m-contract', title:'Contract review', when:'past', time:'3:00 PM', dur:'45m',
    range:'Jun 2 · 3:00 PM', date:'Mon, Jun 2', source:'System + Mic',
    attendees:['maya','devon'], tags:['Skio','Legal'], status:'summary' },
  { id:'m-devon', title:'1:1 — Devon', when:'past', time:'4:00 PM', dur:'30m',
    range:'Jun 8 · 4:00 PM', date:'Mon, Jun 8', source:'System + Mic',
    attendees:['devon'], tags:['1:1'], status:'summary' },
  { id:'m-intro', title:'Theo / intro — Northwind', when:'past', time:'1:00 PM', dur:'30m',
    range:'Jun 5 · 1:00 PM', date:'Thu, Jun 5', source:'Phone',
    attendees:['theo'], tags:['Northwind','Prospect'], status:'transcribed' },
];
const meetingById = (id)=> MEETINGS.find(m=>m.id===id);

// Tasks — every task can link a meeting (source) and an owner (person).
// "fromMeeting && !confirmed" = lives in the Inbox/Triage until accepted.
const TASKS = [
  { id:'t1', title:'Circulate revised contract terms to legal', status:'open', priority:'high',
    due:'Wed', project:'Skio Integration', owner:'devon', meeting:'m-sync', fromMeeting:true, confirmed:true },
  { id:'t2', title:'Build usage-based pricing model', status:'doing', priority:'high',
    due:'Fri', project:'Q3 Roadmap', owner:'jules', meeting:'m-sync', fromMeeting:true, confirmed:true },
  { id:'t3', title:'Draft the integration spec doc', status:'open', priority:'med',
    due:'Fri', project:'Skio Integration', owner:'me', meeting:'m-analytics', fromMeeting:false, confirmed:true },
  { id:'t4', title:'Wire up MCP write-back tools', status:'doing', priority:'med',
    due:'Mon', project:'Skio Integration', owner:'sam', meeting:null, fromMeeting:false, confirmed:true },
  { id:'t5', title:'Schedule design review with Rae', status:'open', priority:'low',
    due:'', project:'Onboarding revamp', owner:'me', meeting:'m-recharge', fromMeeting:false, confirmed:true },
  { id:'t6', title:'Share recording link with Devon', status:'done', priority:'low',
    due:'', project:'Skio Integration', owner:'me', meeting:'m-contract', fromMeeting:true, confirmed:true },
  { id:'t7', title:'Send onboarding deck to Recharge', status:'done', priority:'med',
    due:'', project:'Onboarding revamp', owner:'me', meeting:'m-recharge', fromMeeting:false, confirmed:true },
  // --- Inbox: extracted from meetings, awaiting triage ---
  { id:'i1', title:'Follow up with Maya on enterprise pricing bands', status:'open', priority:'med',
    due:'Thu', project:null, owner:'maya', meeting:'m-sync', fromMeeting:true, confirmed:false },
  { id:'i2', title:'Send Theo the security one-pager', status:'open', priority:'high',
    due:'Wed', project:null, owner:'theo', meeting:'m-intro', fromMeeting:true, confirmed:false },
  { id:'i3', title:'Book Q3 roadmap readout with leadership', status:'open', priority:'med',
    due:'', project:null, owner:'me', meeting:'m-analytics', fromMeeting:true, confirmed:false },
];

const PROJECTS = [
  { id:'skio', name:'Skio Integration', color:'var(--accent)' },
  { id:'q3', name:'Q3 Roadmap', color:'var(--ok)' },
  { id:'onb', name:'Onboarding revamp', color:'var(--warn)' },
];
const INITIATIVES = [ { id:'growth', name:'Growth FY26' } ];

const PRIORITY = {
  high: { label:'High', cls:'t-danger', bar:'var(--danger)', icon:'arrowUp' },
  med:  { label:'Med',  cls:'t-warn',   bar:'var(--warn)',   icon:'minus' },
  low:  { label:'Low',  cls:'t-gray',   bar:'transparent',   icon:null },
};
const STATUS = {
  open: { label:'Open', dot:'var(--info)', cls:'t-info' },
  doing:{ label:'In progress', dot:'var(--warn)', cls:'t-warn' },
  done: { label:'Completed', dot:'var(--ok)', cls:'t-ok' },
};

Object.assign(window, {
  Icon, Avatar, AV_GRADS, gradFor, initials,
  PEOPLE, personById, MEETINGS, meetingById, TASKS, PROJECTS, INITIATIVES, PRIORITY, STATUS,
});

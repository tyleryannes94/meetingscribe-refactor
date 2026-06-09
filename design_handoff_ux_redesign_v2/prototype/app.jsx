// app.jsx — Root app: routing, cross-section navigation, Tweaks panel.

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "meetingsVariant": "A",
  "peopleVariant": "A",
  "tasksVariant": "A",
  "recordingVariant": "A",
  "accentColor": "#ff9173"
}/*EDITMODE-END*/;

function App(){
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const [route, setRoute] = React.useState('today');
  const [chatOpen, setChatOpen] = React.useState(false);
  const [meetingRecording, setMeetingRecording] = React.useState(true);
  const [voiceActive, setVoiceActive] = React.useState(false);
  // Cross-section nav state
  const [pendingPerson, setPendingPerson] = React.useState(null);
  const [pendingMeeting, setPendingMeeting] = React.useState(null);

  const liveMeeting = MEETINGS.find(m=>m.id==='m-now');

  // Open a person from anywhere (e.g. meeting attendee click)
  const openPerson = (id)=>{ setPendingPerson(id); setRoute('people'); };
  // Open a meeting from anywhere (e.g. person's meetings tab)
  const openMeeting = (id)=>{ setPendingMeeting(id); setRoute('meetings'); };

  // Toolbar actions
  const handleAction = (id)=>{
    if(id==='record'||id==='stop-meeting') setMeetingRecording(r=>!r);
    else if(id==='voice') setVoiceActive(true);
    else if(id==='new-meeting') setRoute('meetings');
    else if(id==='add-person') setRoute('people');
    else if(id==='new-task') setRoute('tasks');
  };

  // Chat context varies by route
  const chatCtx = {
    today:    { title:'Ask AI',                   prompts:['Summarize what needs my attention today.','What are my open commitments?','Who should I reconnect with?'], scopeLabel:'workspace' },
    meetings: { title:'Ask AI about this meeting', prompts:['Summarize this meeting.','What did attendees commit to?','Draft a follow-up email.'], scopeLabel:'meeting' },
    people:   { title:'Ask AI about this person',  prompts:['Give me a briefing on this person.','What are my open tasks with them?','When did we last meet and about what?'], scopeLabel:'person' },
    tasks:    { title:'Ask AI about Tasks',        prompts:['What should I work on today?','What tasks are overdue?','Draft a status update.'], scopeLabel:'tasks' },
    voice:    { title:'Ask AI',                    prompts:['Summarize my voice notes.','Extract action items from this note.'], scopeLabel:'voice notes' },
  }[route];

  const mainContent = ()=>{
    switch(route){
      case 'today':
        return <TodayView onRoute={setRoute} liveMeeting={meetingRecording?liveMeeting:null} onStartVoice={()=>setVoiceActive(true)}/>;
      case 'meetings':
        return <MeetingsView variant={t.meetingsVariant} onOpenPerson={openPerson}
          liveMeetingId={meetingRecording?'m-now':null} onPushToTasks={()=>setRoute('tasks')}
          initialMeetingId={pendingMeeting}/>;
      case 'people':
        return <PeopleView variant={t.peopleVariant} onOpenMeeting={openMeeting}
          initialPersonId={pendingPerson}/>;
      case 'tasks':
        return <TasksView variant={t.tasksVariant} route={route}
          onOpenMeeting={openMeeting} onOpenPerson={openPerson}/>;
      case 'voice':
        return <VoiceNotesView/>;
      default:
        return <TodayView onRoute={setRoute}/>;
    }
  };

  // Clear pending state after navigation
  React.useEffect(()=>{
    if(route==='people') setPendingPerson(null);
    if(route==='meetings') setPendingMeeting(null);
  },[route]);

  return (
    <div className="stage">
      <div className="win">
        <TopBar route={route} recording={meetingRecording} onSidebar={()=>{}}
          onAction={handleAction} chatOpen={chatOpen} onToggleChat={()=>setChatOpen(o=>!o)}/>
        <div className="body">
          <NavRail route={route} onRoute={setRoute}/>
          <div style={{ flex:1, minWidth:0, display:'flex', minHeight:0 }}>
            {mainContent()}
          </div>
          <ChatRail open={chatOpen} context={chatCtx}/>
        </div>

        {/* Meeting recording docked bar — request #1 (in-app, never hover) */}
        {meetingRecording && route!=='meetings' && (
          <MeetingRecordBar meeting={liveMeeting} style={t.recordingVariant}
            onOpen={()=>setRoute('meetings')}
            onStop={()=>setMeetingRecording(false)}/>
        )}

        {/* Voice note hover pill — request #1 (floats, draggable, gold, distinct) */}
        {voiceActive && (
          <VoiceHoverPill active={true} style={t.recordingVariant}
            onStop={()=>setVoiceActive(false)}
            onCancel={()=>setVoiceActive(false)}/>
        )}
      </div>

      {/* Tweaks panel — A/B controls for all 4 redesign areas */}
      <TweaksPanel>
        <TweakSection label="Meetings"/>
        <TweakRadio label="Layout variant"
          value={t.meetingsVariant}
          options={['A','B']}
          onChange={v=>setTweak('meetingsVariant',v)}/>

        <TweakSection label="People detail"/>
        <TweakRadio label="Layout variant"
          value={t.peopleVariant}
          options={['A','B']}
          onChange={v=>setTweak('peopleVariant',v)}/>

        <TweakSection label="Tasks"/>
        <TweakRadio label="Layout variant"
          value={t.tasksVariant}
          options={['A','B']}
          onChange={v=>setTweak('tasksVariant',v)}/>

        <TweakSection label="Recording indicators"/>
        <TweakRadio label="Style"
          value={t.recordingVariant}
          options={['A','B']}
          onChange={v=>setTweak('recordingVariant',v)}/>

        <TweakSection label="Demo"/>
        <TweakToggle label="Meeting recording active"
          value={meetingRecording}
          onChange={v=>setMeetingRecording(v)}/>
        <TweakToggle label="Voice note active"
          value={voiceActive}
          onChange={v=>setVoiceActive(v)}/>
      </TweaksPanel>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App/>);

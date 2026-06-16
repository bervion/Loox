/* App — orchestrates lock, tabs, navigation, and LIVE theme/accent state.
   Theme & accent live on the IPhone wrapper, so every surface re-tints
   instantly with no restart and no light/dark desync. */

const ITEMS = [
  { id:'github', name:'GitHub', icon:'login', tint:'#1c1c1e', sub:'octocat@github.com', url:'github.com',
    username:'octocat@github.com', password:'k7$Rm2!qZ4xL', score:4, scoreLabel:'Mạnh', fav:true },
  { id:'google', name:'Google', icon:'login', tint:'#4285f4', sub:'cat@gmail.com', url:'accounts.google.com',
    username:'cat@gmail.com', password:'P9!vQ2s@Lm7z', score:4, scoreLabel:'Mạnh', fav:true },
  { id:'figma', name:'Figma', icon:'login', tint:'#a259ff', sub:'cat@gmail.com', url:'figma.com',
    username:'cat@gmail.com', password:'fG3#tyU8wQ', score:3, scoreLabel:'Tốt' },
  { id:'visa', name:'Visa', icon:'card', tint:'#1a1f71', sub:'•••• 4242', url:'',
    username:'Nguyen Van A', password:'4242 4242 4242 4242', score:4, scoreLabel:'Mạnh' },
  { id:'apple', name:'Apple ID', icon:'identity', tint:'#1c1c1e', sub:'cat@icloud.com', url:'appleid.apple.com',
    username:'cat@icloud.com', password:'Zx9#Kq2!Pm4v', score:4, scoreLabel:'Mạnh' },
  { id:'netflix', name:'Netflix', icon:'login', tint:'#e50914', sub:'cat@gmail.com', url:'netflix.com',
    username:'cat@gmail.com', password:'netflix123', score:1, scoreLabel:'Yếu · dùng lại', alert:true },
  { id:'fastmail', name:'Fastmail', icon:'email', tint:'#0e8a7d', sub:'cat@fastmail.com', url:'fastmail.com',
    username:'cat@fastmail.com', password:'mB7$wK2zQ9', score:3, scoreLabel:'Tốt' },
  { id:'coinbase', name:'Coinbase', icon:'bank', tint:'#0052ff', sub:'cat@gmail.com', url:'coinbase.com',
    username:'cat@gmail.com', password:'Summer2024', score:2, scoreLabel:'Trung bình', alert:true },
  { id:'notion', name:'Notion', icon:'note', tint:'#1c1c1e', sub:'cat@gmail.com', url:'notion.so',
    username:'cat@gmail.com', password:'nT8#vRq2Lp', score:3, scoreLabel:'Tốt' },
];

const CATS = [
  { id:'logins', icon:'login', tint:'var(--accent)', label:'Tên đăng nhập', n: ITEMS.filter(i=>i.icon==='login').length },
  { id:'cards', icon:'card', tint:'var(--success)', label:'Thẻ', n: ITEMS.filter(i=>i.icon==='card').length },
  { id:'notes', icon:'note', tint:'var(--warning)', label:'Ghi chú bảo mật', n: ITEMS.filter(i=>i.icon==='note').length },
  { id:'identity', icon:'identity', tint:'#7c3aed', label:'Danh tính', n: ITEMS.filter(i=>i.icon==='identity').length },
  { id:'bank', icon:'bank', tint:'#0052ff', label:'Tài chính', n: ITEMS.filter(i=>i.icon==='bank').length },
];

function Categories({ onOpen }) {
  return (
    <div style={{ flex:1, minHeight:0, overflowY:'auto', background:'var(--background-grouped)' }}>
      <div style={{ padding:'4px var(--screen-gutter) 0' }}>
        <h1 style={{ margin:'0 0 16px', fontFamily:'var(--font-display)', fontSize:28, fontWeight:700, letterSpacing:'-0.4px', color:'var(--text-primary)' }}>Mục</h1>
      </div>
      <div style={{ padding:'0 var(--screen-gutter) var(--tabbar-bottom-pad)' }}>
        <Card variant="grouped">
          {CATS.map((c,i)=> <Row key={c.id} leading={<IconTile name={c.icon} tint={c.tint} />} title={c.label}
            value={String(c.n)} chevron divider={i<CATS.length-1} onClick={()=>{}} />)}
        </Card>
      </div>
    </div>
  );
}

function Search({ onOpen }) {
  const [q, setQ] = React.useState('');
  const res = q ? ITEMS.filter(i=>i.name.toLowerCase().includes(q.toLowerCase()) || i.sub.toLowerCase().includes(q.toLowerCase())) : ITEMS;
  return (
    <div style={{ flex:1, minHeight:0, overflowY:'auto', background:'var(--background-grouped)' }}>
      <div style={{ padding:'4px var(--screen-gutter) 0' }}>
        <h1 style={{ margin:'0 0 14px', fontFamily:'var(--font-display)', fontSize:28, fontWeight:700, letterSpacing:'-0.4px', color:'var(--text-primary)' }}>Tìm kiếm</h1>
        <span style={{ display:'flex', alignItems:'center', gap:8, minHeight:40, padding:'0 12px', marginBottom:18,
          borderRadius:'var(--radius-sm)', background:'color-mix(in srgb, var(--text-primary) 7%, transparent)' }}>
          <Icon name="search" size={18} color="var(--icon-secondary)" />
          <input value={q} onChange={(e)=>setQ(e.target.value)} placeholder="Tìm trong kho" autoFocus
            style={{ flex:1, border:'none', outline:'none', background:'transparent', fontFamily:'var(--font-text)', fontSize:16, color:'var(--text-primary)' }} />
        </span>
      </div>
      <div style={{ padding:'0 var(--screen-gutter) var(--tabbar-bottom-pad)' }}>
        <Card variant="grouped">
          {res.map((it,i)=> <Row key={it.id} leading={<IconTile name={it.icon} tint={it.tint} />} title={it.name} subtitle={it.sub}
            chevron divider={i<res.length-1} onClick={()=>onOpen(it)} />)}
          {res.length===0 && <div style={{ padding:'28px', textAlign:'center', fontFamily:'var(--font-text)', fontSize:15, color:'var(--text-tertiary)' }}>Không có kết quả</div>}
        </Card>
      </div>
    </div>
  );
}

const TABS = [
  { id:'home', icon:'home', iconFill:'home.fill', label:'Trang chủ' },
  { id:'items', icon:'items', iconFill:'items.fill', label:'Mục' },
  { id:'watchtower', icon:'watchtower', label:'Giám sát', badge:6 },
  { id:'search', icon:'search', label:'Tìm kiếm' },
];

function App() {
  const [locked, setLocked] = React.useState(true);
  const [tab, setTab] = React.useState('home');
  const [detail, setDetail] = React.useState(null);
  const [showAppearance, setShowAppearance] = React.useState(false);
  const [theme, setTheme] = React.useState('light');
  const [accent, setAccent] = React.useState('blue');

  const overlay = detail || showAppearance;

  function screen() {
    if (tab==='home') return <VaultHome items={ITEMS} onOpen={setDetail} />;
    if (tab==='items') return <Categories onOpen={setDetail} />;
    if (tab==='watchtower') return <Watchtower />;
    if (tab==='search') return <Search onOpen={setDetail} />;
    return null;
  }

  return (
    <div style={{ display:'flex', gap:40, alignItems:'flex-start', flexWrap:'wrap', justifyContent:'center' }}>
      <IPhone theme={theme} accent={accent}>
        <StatusBar />
        {locked ? (
          <UnlockScreen onUnlock={()=>setLocked(false)} />
        ) : (
          <div style={{ position:'relative', flex:1, minHeight:0, display:'flex', flexDirection:'column' }}>
            {/* home gets a profile entry to Appearance */}
            <div style={{ flex:1, minHeight:0, display:'flex', flexDirection:'column' }}>
              {tab==='home'
                ? <VaultHomeWithSettings onOpen={setDetail} onSettings={()=>setShowAppearance(true)} />
                : screen()}
            </div>

            {!overlay && (
              <div style={{ position:'absolute', left:'var(--tabbar-inset)', right:'var(--tabbar-inset)', bottom:'calc(var(--tabbar-offset) + 8px)' }}>
                <TabBar tabs={TABS} value={tab} onChange={setTab} glass />
              </div>
            )}

            {detail && (
              <div style={{ position:'absolute', inset:0, background:'var(--background-grouped)', display:'flex', flexDirection:'column', animation:'slideIn var(--dur-medium) var(--ease-standard)' }}>
                <ItemDetail item={detail} onBack={()=>setDetail(null)} />
              </div>
            )}
            {showAppearance && (
              <div style={{ position:'absolute', inset:0, background:'var(--background-grouped)', display:'flex', flexDirection:'column', animation:'sheetUp var(--dur-medium) var(--ease-standard)' }}>
                <Appearance theme={theme} setTheme={setTheme} accent={accent} setAccent={setAccent} onClose={()=>setShowAppearance(false)} />
              </div>
            )}
          </div>
        )}
        {/* home indicator */}
        <div style={{ position:'absolute', bottom:8, left:'50%', transform:'translateX(-50%)', width:140, height:5, borderRadius:3, background:'var(--text-primary)', opacity:0.32, zIndex:60 }} />
      </IPhone>

      {/* External quick controls — demo live theming */}
      <DemoControls locked={locked} theme={theme} setTheme={setTheme} accent={accent} setAccent={setAccent} onLock={()=>setLocked(true)} />
    </div>
  );
}

/* Home variant wired to open Appearance from the profile button */
function VaultHomeWithSettings({ onOpen, onSettings }) {
  const favs = ITEMS.filter(i=>i.fav);
  return (
    <div style={{ flex:1, minHeight:0, overflowY:'auto', background:'var(--background-grouped)' }}>
      <div style={{ padding:'4px var(--screen-gutter) 0' }}>
        <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', minHeight:44 }}>
          <h1 style={{ margin:0, fontFamily:'var(--font-display)', fontSize:28, fontWeight:700, letterSpacing:'-0.4px', color:'var(--text-primary)' }}>Kho</h1>
          <div style={{ display:'flex', gap:2 }}>
            <IconButton name="add" label="Thêm mục" color="var(--accent)" />
            <IconButton name="settings" label="Cài đặt" color="var(--accent)" onClick={onSettings} />
          </div>
        </div>
        <button onClick={()=>{}} style={{ display:'flex', alignItems:'center', gap:8, width:'100%', margin:'8px 0 18px',
          minHeight:40, padding:'0 12px', border:'none', borderRadius:'var(--radius-sm)',
          background:'color-mix(in srgb, var(--text-primary) 7%, transparent)', cursor:'pointer' }}>
          <Icon name="search" size={18} color="var(--icon-secondary)" />
          <span style={{ fontFamily:'var(--font-text)', fontSize:16, color:'var(--text-tertiary)' }}>Tìm trong kho</span>
        </button>
      </div>
      <div style={{ padding:'0 var(--screen-gutter)', display:'flex', flexDirection:'column', gap:22, paddingBottom:'var(--tabbar-bottom-pad)' }}>
        <section>
          <SectionHeader title="Yêu thích" />
          <Card variant="grouped">
            {favs.map((it,i)=> <Row key={it.id} leading={<IconTile name={it.icon} tint={it.tint} />} title={it.name} subtitle={it.sub}
              chevron divider={i<favs.length-1} onClick={()=>onOpen(it)} />)}
          </Card>
        </section>
        <section>
          <SectionHeader title={`Tất cả · ${ITEMS.length}`} action="Sắp xếp" />
          <Card variant="grouped">
            {ITEMS.map((it,i)=> <Row key={it.id} leading={<IconTile name={it.icon} tint={it.tint} />} title={it.name} subtitle={it.sub}
              trailing={it.alert ? <Badge dot tone="warning" /> : null}
              chevron divider={i<ITEMS.length-1} onClick={()=>onOpen(it)} />)}
          </Card>
        </section>
      </div>
    </div>
  );
}

function DemoControls({ locked, theme, setTheme, accent, setAccent, onLock }) {
  return (
    <div style={{ width:230, display:'flex', flexDirection:'column', gap:18, paddingTop:8 }}>
      <div>
        <p style={{ margin:'0 0 8px', font:'600 12px var(--font-text)', letterSpacing:'0.4px', textTransform:'uppercase', color:'#8a8a8e' }}>Chế độ</p>
        <SegmentedControl value={theme} onChange={setTheme} options={[{value:'light',label:'Sáng'},{value:'dark',label:'Tối'}]} />
      </div>
      <div>
        <p style={{ margin:'0 0 10px', font:'600 12px var(--font-text)', letterSpacing:'0.4px', textTransform:'uppercase', color:'#8a8a8e' }}>Màu nhấn</p>
        <div style={{ display:'flex', gap:12, flexWrap:'wrap' }}>
          {window.ACCENTS.map(a => {
            const sel=a.id===accent, col = theme==='dark'?a.dark:a.light;
            return <button key={a.id} onClick={()=>setAccent(a.id)} aria-label={a.id} style={{ width:34, height:34, borderRadius:'50%',
              border:'none', cursor:'pointer', background:col, position:'relative',
              boxShadow: sel?`0 0 0 2px #fff, 0 0 0 4px ${col}`:'none' }}>
              {sel && <Icon name="success" size={16} color="#fff" style={{ position:'absolute', inset:0, margin:'auto' }} />}
            </button>;
          })}
        </div>
      </div>
      {!locked && <Button variant="secondary" leadingIcon="lock" onClick={onLock}>Khoá kho</Button>}
      <p style={{ margin:0, font:'400 12px var(--font-text)', lineHeight:'17px', color:'#8a8a8e', textWrap:'pretty' }}>
        Đổi chế độ &amp; màu nhấn để thấy toàn bộ giao diện đổi tức thì — đúng yêu cầu “không desync sau khi đổi theme”.</p>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App />);

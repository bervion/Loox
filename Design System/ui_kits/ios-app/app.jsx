/* App — Vaultify iPhone recreation.
   Multi-space vault · quick TOTP · password-rotation reminders ·
   live theme/accent. State lives on the IPhone wrapper so every
   surface re-tints instantly (no restart, no light/dark desync). */

/* ---- Spaces (personal / company / shared) ---- */
const SPACES = [
  { id:'personal', name:'Cá nhân',  tint:'#2563eb', icon:'profile' },
  { id:'acme',     name:'Acme Corp', tint:'#7c3aed', icon:'bank' },
  { id:'family',   name:'Gia đình',  tint:'#0e8a7d', icon:'favorite' },
];
const spaceById = (id) => SPACES.find(s=>s.id===id);

/* ---- Items. totp = a 2FA secret seed · rotateDays = đổi mật khẩu định kỳ
   · changed = số ngày kể từ lần đổi gần nhất ---- */
const ITEMS = [
  { id:'vcb', name:'Vietcombank', icon:'bank', tint:'#0a8f3c', space:'personal', username:'0901234567',
    url:'vietcombank.com.vn', password:'Vcb#2026xKq', score:4, rotateDays:30, changed:33, totp:'VCB2FAKEY' },
  { id:'acb', name:'ACB Online', icon:'bank', tint:'#0052a5', space:'personal', username:'cat@gmail.com',
    url:'acb.com.vn', password:'Acb!9wQ2mLz', score:4, rotateDays:15, changed:12 },
  { id:'github', name:'GitHub', icon:'login', tint:'#1c1c1e', space:'acme', username:'octocat@acme.com',
    url:'github.com', password:'k7$Rm2!qZ4xL', score:4, changed:20, totp:'GH7KQ2', fav:true },
  { id:'google', name:'Google', icon:'login', tint:'#4285f4', space:'personal', username:'cat@gmail.com',
    url:'accounts.google.com', password:'P9!vQ2s@Lm7z', score:4, changed:90, totp:'GOOGLE9', fav:true },
  { id:'figma', name:'Figma', icon:'login', tint:'#a259ff', space:'acme', username:'cat@acme.com',
    url:'figma.com', password:'fG3#tyU8wQ', score:3, changed:210 },
  { id:'aws', name:'AWS Console', icon:'website', tint:'#ff9900', space:'acme', username:'ops@acme.com',
    url:'aws.amazon.com', password:'Aws#2025kPq', score:4, rotateDays:90, changed:96, totp:'AWSKEY1' },
  { id:'apple', name:'Apple ID', icon:'identity', tint:'#1c1c1e', space:'personal', username:'cat@icloud.com',
    url:'appleid.apple.com', password:'Zx9#Kq2!Pm4v', score:4, changed:60 },
  { id:'visa', name:'Visa', icon:'card', tint:'#1a1f71', space:'personal', username:'•••• 4242',
    url:'', password:'4242 4242 4242 4242', score:4, changed:30 },
  { id:'netflix', name:'Netflix', icon:'login', tint:'#e50914', space:'family', username:'cat@gmail.com',
    url:'netflix.com', password:'netflix123', score:1, changed:400, alert:true },
  { id:'fastmail', name:'Fastmail', icon:'email', tint:'#0e8a7d', space:'acme', username:'cat@fastmail.com',
    url:'fastmail.com', password:'mB7$wK2zQ9', score:3, changed:10, totp:'FMAIL3' },
  { id:'notion', name:'Notion', icon:'note', tint:'#1c1c1e', space:'acme', username:'cat@acme.com',
    url:'notion.so', password:'nT8#vRq2Lp', score:3, changed:35 },
];

/* ---- Rotation / staleness status ---- */
function rotationStatus(it){
  if (it.rotateDays>0){
    const due = it.rotateDays - it.changed;
    if (due<=0)  return { state:'overdue', tone:'destructive', icon:'refresh', label:`Quá hạn đổi ${-due} ngày`, short:'Quá hạn' };
    if (due<=5)  return { state:'soon', tone:'warning', icon:'clock', label:`Đổi sau ${due} ngày`, short:`${due} ngày` };
    return { state:'ok', tone:'neutral', label:`Đổi sau ${due} ngày` };
  }
  if (it.changed>=180) return { state:'stale', tone:'warning', icon:'clock', label:`${Math.round(it.changed/30)} tháng chưa đổi`, short:'Đã lâu' };
  return { state:'ok' };
}
function attentionReason(it){
  const r = rotationStatus(it);
  if (r.state!=='ok') return r;
  if (it.score<=1) return { state:'weak', tone:'destructive', icon:'warning', label:'Mật khẩu yếu · dùng lại', short:'Yếu' };
  return null;
}

/* ============================================================ Cells */
function ItemCell({ item, onOpen, showSpace, divider }){
  const [pressed,setPressed] = React.useState(false);
  const sp = spaceById(item.space);
  const att = attentionReason(item);
  return (
    <div role="button" onClick={()=>onOpen(item)}
      onPointerDown={()=>setPressed(true)} onPointerUp={()=>setPressed(false)} onPointerLeave={()=>setPressed(false)}
      style={{ position:'relative', display:'flex', alignItems:'center', gap:'var(--space-3)', minHeight:62,
        padding:'10px var(--space-4)', background: pressed?'var(--surface-pressed)':'transparent', cursor:'pointer',
        transition:'background var(--dur-fast)', WebkitTapHighlightColor:'transparent' }}>
      <IconTile name={item.icon} tint={item.tint} size={38} radius="var(--radius-sm)" />
      <div style={{ flex:1, minWidth:0, display:'flex', flexDirection:'column', gap:3 }}>
        <span style={{ fontFamily:'var(--font-text)', fontSize:17, fontWeight:600, color:'var(--text-primary)', lineHeight:'20px',
          whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis' }}>{item.name}</span>
        <span style={{ display:'flex', alignItems:'center', gap:7, minWidth:0 }}>
          {showSpace && <SpaceTag space={sp} />}
          <span style={{ fontFamily:'var(--font-text)', fontSize:13, color:'var(--text-secondary)', whiteSpace:'nowrap',
            overflow:'hidden', textOverflow:'ellipsis' }}>{item.username}</span>
        </span>
      </div>
      {item.totp && <Icon name="clock" size={16} color="var(--icon-disabled)" />}
      {att && <span style={{ width:8, height:8, borderRadius:'50%', flex:'0 0 auto',
        background: att.tone==='destructive'?'var(--destructive)':'var(--warning)' }} />}
      <Icon name="chevron.right" size={16} color="var(--icon-disabled)" />
      {divider && <span style={{ position:'absolute', left:'calc(var(--space-4) + 38px + var(--space-3))', right:0, bottom:0, height:0.5, background:'var(--separator)' }} />}
    </div>
  );
}

function AttentionCell({ item, onUpdate, divider }){
  const att = attentionReason(item);
  const sp = spaceById(item.space);
  return (
    <div style={{ position:'relative', display:'flex', alignItems:'center', gap:'var(--space-3)', minHeight:64, padding:'10px var(--space-4)' }}>
      <IconTile name={item.icon} tint={item.tint} size={38} radius="var(--radius-sm)" />
      <div style={{ flex:1, minWidth:0, display:'flex', flexDirection:'column', gap:3 }}>
        <span style={{ fontFamily:'var(--font-text)', fontSize:16, fontWeight:600, color:'var(--text-primary)',
          whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis' }}>{item.name}</span>
        <span style={{ display:'flex', alignItems:'center', gap:6 }}>
          <Icon name={att.icon} size={13} color={att.tone==='destructive'?'var(--destructive)':'var(--warning)'} />
          <span style={{ fontFamily:'var(--font-text)', fontSize:13, fontWeight:500,
            color: att.tone==='destructive'?'var(--destructive)':'var(--warning)' }}>{att.label}</span>
        </span>
      </div>
      <Button size="sm" variant={att.tone==='destructive'?'primary':'secondary'} onClick={()=>onUpdate(item)}>Đổi</Button>
      {divider && <span style={{ position:'absolute', left:'calc(var(--space-4) + 38px + var(--space-3))', right:0, bottom:0, height:0.5, background:'var(--separator)' }} />}
    </div>
  );
}

/* ============================================================ Home */
function Home({ space, onOpenSpace, onOpenItem, onAdd, onGenerate, onTotpAll, onSettings }){
  const inSpace = (it) => space==='all' || it.space===space;
  const items = ITEMS.filter(inSpace);
  const totps = items.filter(i=>i.totp);
  const attention = items.filter(attentionReason).sort((a,b)=>{
    const t={overdue:0,weak:1,soon:2,stale:3}; return (t[attentionReason(a).state]??9)-(t[attentionReason(b).state]??9); });
  const favs = items.filter(i=>i.fav);
  const cur = space==='all' ? { name:'Tất cả space', tint:'var(--icon-secondary)' } : spaceById(space);

  return (
    <div style={{ flex:1, minHeight:0, overflowY:'auto', background:'var(--background-grouped)' }}>
      <div style={{ padding:'2px var(--screen-gutter) 0' }}>
        {/* space switcher header */}
        <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', minHeight:44 }}>
          <button onClick={onOpenSpace} style={{ display:'flex', alignItems:'center', gap:8, border:'none', background:'none',
            cursor:'pointer', padding:'4px 0', WebkitTapHighlightColor:'transparent' }}>
            <span style={{ width:10, height:10, borderRadius:'50%', background:cur.tint }} />
            <span style={{ fontFamily:'var(--font-display)', fontSize:24, fontWeight:700, letterSpacing:'-0.4px', color:'var(--text-primary)' }}>{cur.name}</span>
            <Icon name="chevron.down" size={17} color="var(--icon-secondary)" />
          </button>
          <div style={{ display:'flex', gap:2 }}>
            <IconButton name="add" label="Thêm mục" color="var(--accent)" onClick={onAdd} />
            <IconButton name="settings" label="Cài đặt" color="var(--accent)" onClick={onSettings} />
          </div>
        </div>
        {/* search */}
        <button onClick={()=>{}} style={{ display:'flex', alignItems:'center', gap:8, width:'100%', margin:'8px 0 16px',
          minHeight:40, padding:'0 12px', border:'none', borderRadius:'var(--radius-sm)',
          background:'color-mix(in srgb, var(--text-primary) 7%, transparent)', cursor:'pointer' }}>
          <Icon name="search" size={18} color="var(--icon-secondary)" />
          <span style={{ fontFamily:'var(--font-text)', fontSize:16, color:'var(--text-tertiary)' }}>Tìm trong kho</span>
        </button>
      </div>

      <div style={{ padding:'0 var(--screen-gutter)', display:'flex', flexDirection:'column', gap:24, paddingBottom:'var(--tabbar-bottom-pad)' }}>
        {/* quick actions */}
        <div style={{ display:'flex', gap:6 }}>
          <QuickAction icon="add" label="Thêm mục" tint="var(--accent)" onClick={onAdd} />
          <QuickAction icon="refresh" label="Tạo mật khẩu" tint="#0e8a7d" onClick={onGenerate} />
          <QuickAction icon="clock" label="Mã 2FA" tint="#7c3aed" onClick={onTotpAll} />
          <QuickAction icon="watchtower" label="Giám sát" tint="#0a8f3c" onClick={()=>{}} />
        </div>

        {/* TOTP quick view */}
        {totps.length>0 && (
          <section>
            <SectionHeader title="Mã xác thực" action="Xem tất cả" onAction={onTotpAll} />
            <div style={{ display:'flex', gap:10, overflowX:'auto', padding:'2px 2px 4px', margin:'0 -2px',
              scrollbarWidth:'none' }}>
              {totps.map(it=> <TotpCard key={it.id} item={it} />)}
            </div>
          </section>
        )}

        {/* needs attention — rotation / stale / weak */}
        {attention.length>0 && (
          <section>
            <SectionHeader title={`Cần chú ý · ${attention.length}`} />
            <Card variant="grouped">
              {attention.slice(0,4).map((it,i)=> <AttentionCell key={it.id} item={it} onUpdate={onOpenItem} divider={i<Math.min(4,attention.length)-1} />)}
            </Card>
          </section>
        )}

        {/* favorites */}
        {favs.length>0 && (
          <section>
            <SectionHeader title="Yêu thích" />
            <Card variant="grouped">
              {favs.map((it,i)=> <ItemCell key={it.id} item={it} onOpen={onOpenItem} showSpace={space==='all'} divider={i<favs.length-1} />)}
            </Card>
          </section>
        )}

        {/* all items */}
        <section>
          <SectionHeader title={`Tất cả · ${items.length}`} action="Sắp xếp" />
          <Card variant="grouped">
            {items.map((it,i)=> <ItemCell key={it.id} item={it} onOpen={onOpenItem} showSpace={space==='all'} divider={i<items.length-1} />)}
          </Card>
        </section>
      </div>
    </div>
  );
}

/* ============================================================ Space switcher */
function SpaceSwitcher({ space, setSpace, onClose }){
  const pick = (id) => { setSpace(id); onClose(); };
  const countOf = (id) => id==='all' ? ITEMS.length : ITEMS.filter(i=>i.space===id).length;
  return (
    <Sheet title="Spaces" onClose={onClose}>
      <Card variant="grouped" style={{ marginBottom:18 }}>
        <Row leading={<IconTile name="items" tint="var(--icon-secondary)" soft />} title="Tất cả space"
          value={String(countOf('all'))} trailing={space==='all'?<Icon name="success" size={20} color="var(--accent)" />:null}
          divider={true} onClick={()=>pick('all')} />
        {SPACES.map((s,i)=> <Row key={s.id} leading={<IconTile name={s.icon} tint={s.tint} />} title={s.name}
          value={String(countOf(s.id))} trailing={space===s.id?<Icon name="success" size={20} color="var(--accent)" />:null}
          divider={i<SPACES.length-1} onClick={()=>pick(s.id)} />)}
      </Card>
      <Card variant="grouped">
        <Row leading={<IconTile name="add" tint="var(--accent)" soft />} title="Tạo space mới" tone="accent" divider={true} onClick={onClose} />
        <Row leading={<IconTile name="settings" tint="var(--icon-secondary)" soft />} title="Quản lý spaces & thành viên" chevron divider={false} onClick={onClose} />
      </Card>
    </Sheet>
  );
}

/* ============================================================ Create item (shows rotation + TOTP options) */
function CreateItem({ space, onClose }){
  const [rotate,setRotate] = React.useState('off');
  const [totp,setTotp] = React.useState(false);
  const [sp,setSp] = React.useState(space==='all'?'personal':space);
  const [pw,setPw] = React.useState('Vcb#2026xKq');
  return (
    <Sheet title="Mục mới" onClose={onClose}>
      <div style={{ display:'flex', flexDirection:'column', gap:22, paddingTop:4 }}>
        <Card variant="grouped">
          <Row leading={<IconTile name="login" tint="var(--accent)" />} title="Loại" value="Đăng nhập" chevron onClick={()=>{}} />
          <Row leading={<IconTile name={spaceById(sp).icon} tint={spaceById(sp).tint} />} title="Space"
            value={spaceById(sp).name} chevron divider={false} onClick={()=>{
              const i=SPACES.findIndex(s=>s.id===sp); setSp(SPACES[(i+1)%SPACES.length].id); }} />
        </Card>

        <div style={{ display:'flex', flexDirection:'column', gap:14 }}>
          <Field label="Tên" leadingIcon="login" defaultValue="Vietcombank" />
          <Field label="Email / Tên đăng nhập" leadingIcon="email" defaultValue="0901234567" />
          <Field label="Mật khẩu" leadingIcon="lock" mono secure revealable value={pw} onChange={(e)=>setPw(e.target.value)}
            trailing={<IconButton name="refresh" label="Tạo mật khẩu" size="sm" color="var(--accent)" onClick={()=>setPw('K'+Math.random().toString(36).slice(2,11)+'#9')} />} />
          <div style={{ padding:'0 2px' }}><StrengthMeter score={4} /></div>
        </div>

        {/* rotation reminder — the bank painpoint */}
        <section>
          <SectionHeader title="Nhắc đổi mật khẩu" />
          <SegmentedControl value={rotate} onChange={setRotate}
            options={[{value:'off',label:'Tắt'},{value:'15',label:'15 ngày'},{value:'30',label:'30 ngày'},{value:'90',label:'90 ngày'}]} />
          <p style={{ margin:'8px 4px 0', fontFamily:'var(--font-text)', fontSize:13, color:'var(--text-tertiary)', textWrap:'pretty' }}>
            {rotate==='off' ? 'Vaultify sẽ không nhắc đổi mật khẩu cho mục này.'
              : `Vaultify sẽ nhắc bạn đổi mật khẩu mỗi ${rotate} ngày — phù hợp cho ngân hàng yêu cầu đổi định kỳ.`}
          </p>
        </section>

        <Card variant="grouped">
          <Row leading={<IconTile name="clock" tint="#7c3aed" soft />} title="Thêm mã xác thực (2FA)" subtitle={totp?'Quét QR hoặc dán khoá':undefined}
            trailing={<Switch checked={totp} onChange={setTotp} label="2FA" />} divider={false} />
        </Card>

        <Button fullWidth size="lg" onClick={onClose}>Lưu vào kho</Button>
      </div>
    </Sheet>
  );
}

/* ============================================================ Password generator */
function genPw(len=18){ const a='ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%^&*'; let s=''; for(let i=0;i<len;i++) s+=a[Math.floor(Math.random()*a.length)]; return s; }
function Generator({ onClose }){
  const [pw,setPw] = React.useState(()=>genPw());
  const [copied,setCopied] = React.useState(false);
  function copy(){ setCopied(true); setTimeout(()=>setCopied(false),1200); }
  return (
    <Sheet title="Tạo mật khẩu" onClose={onClose}>
      <div style={{ display:'flex', flexDirection:'column', gap:18, paddingTop:4 }}>
        <Card padding="18px">
          <div style={{ fontFamily:'var(--font-mono)', fontSize:22, fontWeight:600, color:'var(--text-primary)',
            wordBreak:'break-all', lineHeight:'30px', letterSpacing:'0.02em' }}>{pw}</div>
          <div style={{ marginTop:14 }}><StrengthMeter score={4} /></div>
        </Card>
        <div style={{ display:'flex', gap:10 }}>
          <Button variant="secondary" fullWidth leadingIcon="refresh" onClick={()=>setPw(genPw())}>Tạo lại</Button>
          <Button fullWidth leadingIcon={copied?'success':'copy'} onClick={copy}>{copied?'Đã sao chép':'Sao chép'}</Button>
        </div>
        <Card variant="grouped">
          <Row title="Độ dài" value="18 ký tự" chevron onClick={()=>{}} />
          <Row title="Ký tự đặc biệt" trailing={<Switch checked={true} onChange={()=>{}} label="Ký tự đặc biệt" />} divider={false} />
        </Card>
      </div>
    </Sheet>
  );
}

/* ============================================================ Full TOTP list */
function TotpList({ space, onClose }){
  const [q,setQ] = React.useState('');
  const all = ITEMS.filter(i=>i.totp && (space==='all'||i.space===space));
  const norm = (s)=> (s||'').toLowerCase();
  const ql = norm(q.trim());
  const items = ql ? all.filter(it =>
    norm(it.name).includes(ql) || norm(it.username).includes(ql) || norm(spaceById(it.space)?.name).includes(ql)
  ) : all;
  return (
    <Sheet title="Mã xác thực" onClose={onClose}>
      <label style={{ display:'flex', alignItems:'center', gap:8, minHeight:40, padding:'0 12px', marginBottom:14,
        borderRadius:'var(--radius-sm)', background:'color-mix(in srgb, var(--text-primary) 7%, transparent)' }}>
        <Icon name="search" size={18} color="var(--icon-secondary)" />
        <input value={q} onChange={(e)=>setQ(e.target.value)} placeholder="Tìm tên, email, space…"
          style={{ flex:1, border:'none', outline:'none', background:'transparent', fontFamily:'var(--font-text)', fontSize:16, color:'var(--text-primary)', minWidth:0 }} />
        {q && <button onClick={()=>setQ('')} aria-label="Xoá tìm kiếm" style={{ display:'inline-flex', border:'none', background:'none', padding:4, cursor:'pointer' }}>
          <Icon name="add" size={16} color="var(--icon-secondary)" style={{ transform:'rotate(45deg)' }} />
        </button>}
      </label>
      {items.length>0 ? (
        <Card variant="grouped">
          {items.map((it,i)=> <TotpRow key={it.id} item={it} divider={i<items.length-1} />)}
        </Card>
      ) : (
        <div style={{ padding:'40px 16px', textAlign:'center', fontFamily:'var(--font-text)', fontSize:15, color:'var(--text-tertiary)' }}>
          Không có mã nào khớp “{q}”.
        </div>
      )}
    </Sheet>
  );
}
function TotpRow({ item, divider }){
  const { code, remaining, progress } = useTotp(item.totp);
  const [copied,setCopied] = React.useState(false);
  const sp = spaceById(item.space);
  return (
    <div onClick={()=>{setCopied(true);setTimeout(()=>setCopied(false),1100);}} role="button"
      style={{ position:'relative', display:'flex', alignItems:'center', gap:'var(--space-3)', minHeight:64, padding:'10px var(--space-4)', cursor:'pointer' }}>
      <IconTile name={item.icon} tint={item.tint} size={38} />
      <div style={{ flex:1, minWidth:0 }}>
        <div style={{ fontFamily:'var(--font-text)', fontSize:15, color:'var(--text-secondary)', display:'flex', gap:7, alignItems:'center', marginBottom:2 }}>
          <SpaceTag space={sp} /> <span style={{ whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis' }}>{item.name}</span>
        </div>
        <div style={{ fontFamily:'var(--font-mono)', fontSize:26, fontWeight:600, letterSpacing:'0.08em',
          color: copied?'var(--success)':'var(--accent)', fontVariantNumeric:'tabular-nums' }}>{copied?'Đã sao chép':fmtCode(code)}</div>
      </div>
      <TotpRing progress={progress} remaining={remaining} size={32} />
      {divider && <span style={{ position:'absolute', left:'calc(var(--space-4) + 38px + var(--space-3))', right:0, bottom:0, height:0.5, background:'var(--separator)' }} />}
    </div>
  );
}

/* ============================================================ Categories & Search */
function Categories({ space, onOpen }){
  const items = ITEMS.filter(i=>space==='all'||i.space===space);
  const cats = [
    { id:'logins', icon:'login', tint:'var(--accent)', label:'Tên đăng nhập', n: items.filter(i=>i.icon==='login').length },
    { id:'bank', icon:'bank', tint:'#0a8f3c', label:'Ngân hàng & tài chính', n: items.filter(i=>i.icon==='bank').length },
    { id:'cards', icon:'card', tint:'#1a1f71', label:'Thẻ', n: items.filter(i=>i.icon==='card').length },
    { id:'identity', icon:'identity', tint:'#7c3aed', label:'Danh tính', n: items.filter(i=>i.icon==='identity').length },
    { id:'note', icon:'note', tint:'var(--warning)', label:'Ghi chú bảo mật', n: items.filter(i=>i.icon==='note').length },
  ];
  return (
    <div style={{ flex:1, minHeight:0, overflowY:'auto', background:'var(--background-grouped)' }}>
      <div style={{ padding:'4px var(--screen-gutter) 16px' }}>
        <h1 style={{ margin:0, fontFamily:'var(--font-display)', fontSize:28, fontWeight:700, letterSpacing:'-0.4px', color:'var(--text-primary)' }}>Mục</h1>
      </div>
      <div style={{ padding:'0 var(--screen-gutter) var(--tabbar-bottom-pad)' }}>
        <Card variant="grouped">
          {cats.map((c,i)=> <Row key={c.id} leading={<IconTile name={c.icon} tint={c.tint} />} title={c.label} value={String(c.n)} chevron divider={i<cats.length-1} onClick={()=>{}} />)}
        </Card>
      </div>
    </div>
  );
}

function Search({ onOpen }){
  const [q,setQ] = React.useState('');
  const [sp,setSp] = React.useState('all');
  let res = ITEMS.filter(i=> sp==='all'||i.space===sp);
  if (q) res = res.filter(i=> (i.name+' '+i.username).toLowerCase().includes(q.toLowerCase()));
  return (
    <div style={{ flex:1, minHeight:0, overflowY:'auto', background:'var(--background-grouped)' }}>
      <div style={{ padding:'4px var(--screen-gutter) 0' }}>
        <h1 style={{ margin:'0 0 12px', fontFamily:'var(--font-display)', fontSize:28, fontWeight:700, letterSpacing:'-0.4px', color:'var(--text-primary)' }}>Tìm kiếm</h1>
        <span style={{ display:'flex', alignItems:'center', gap:8, minHeight:40, padding:'0 12px',
          borderRadius:'var(--radius-sm)', background:'color-mix(in srgb, var(--text-primary) 7%, transparent)' }}>
          <Icon name="search" size={18} color="var(--icon-secondary)" />
          <input value={q} onChange={(e)=>setQ(e.target.value)} placeholder="Tên, email, space…" autoFocus
            style={{ flex:1, border:'none', outline:'none', background:'transparent', fontFamily:'var(--font-text)', fontSize:16, color:'var(--text-primary)' }} />
        </span>
        {/* space filter chips */}
        <div style={{ display:'flex', gap:8, overflowX:'auto', padding:'12px 0 16px', scrollbarWidth:'none' }}>
          {[{id:'all',name:'Tất cả',tint:'var(--icon-secondary)'},...SPACES].map(s=>{
            const on = sp===s.id;
            return <button key={s.id} onClick={()=>setSp(s.id)} style={{ flex:'0 0 auto', display:'inline-flex', alignItems:'center', gap:6,
              padding:'7px 13px', borderRadius:'var(--radius-pill)', border:'none', cursor:'pointer',
              background: on?'var(--accent)':'color-mix(in srgb, var(--text-primary) 7%, transparent)',
              WebkitTapHighlightColor:'transparent' }}>
              {s.id!=='all' && <span style={{ width:7, height:7, borderRadius:'50%', background: on?'var(--on-accent)':s.tint }} />}
              <span style={{ fontFamily:'var(--font-text)', fontSize:14, fontWeight:600, color: on?'var(--on-accent)':'var(--text-secondary)' }}>{s.name}</span>
            </button>;
          })}
        </div>
      </div>
      <div style={{ padding:'0 var(--screen-gutter) var(--tabbar-bottom-pad)' }}>
        <Card variant="grouped">
          {res.map((it,i)=> <ItemCell key={it.id} item={it} onOpen={onOpen} showSpace={true} divider={i<res.length-1} />)}
          {res.length===0 && <div style={{ padding:'28px', textAlign:'center', fontFamily:'var(--font-text)', fontSize:15, color:'var(--text-tertiary)' }}>Không có kết quả</div>}
        </Card>
      </div>
    </div>
  );
}

/* ============================================================ App shell */
const TABS = [
  { id:'home', icon:'home', iconFill:'home.fill', label:'Trang chủ' },
  { id:'items', icon:'items', iconFill:'items.fill', label:'Mục' },
  { id:'watchtower', icon:'watchtower', label:'Giám sát', badge:5 },
  { id:'search', icon:'search', label:'Tìm kiếm' },
];

function App(){
  const [locked,setLocked] = React.useState(true);
  const [tab,setTab] = React.useState('home');
  const [space,setSpace] = React.useState('all');
  const [detail,setDetail] = React.useState(null);
  const [sheet,setSheet] = React.useState(null); // 'space' | 'create' | 'gen' | 'totp' | 'settings'
  const [theme,setTheme] = React.useState('light');
  const [accent,setAccent] = React.useState('blue');
  const overlay = !!detail || (sheet==='settings');

  function screen(){
    if (tab==='home') return <Home space={space}
      onOpenSpace={()=>setSheet('space')} onOpenItem={setDetail} onAdd={()=>setSheet('create')}
      onGenerate={()=>setSheet('gen')} onTotpAll={()=>setSheet('totp')} onSettings={()=>setSheet('settings')} />;
    if (tab==='items') return <Categories space={space} onOpen={setDetail} />;
    if (tab==='watchtower') return <Watchtower />;
    if (tab==='search') return <Search onOpen={setDetail} />;
    return null;
  }

  return (
    <div style={{ display:'flex', gap:40, alignItems:'flex-start', flexWrap:'wrap', justifyContent:'center' }}>
      <IPhone theme={theme} accent={accent}>
        <StatusBar />
        {locked ? <UnlockScreen onUnlock={()=>setLocked(false)} /> : (
          <div style={{ position:'relative', flex:1, minHeight:0, display:'flex', flexDirection:'column' }}>
            <div style={{ flex:1, minHeight:0, display:'flex', flexDirection:'column' }}>{screen()}</div>

            {!overlay && (
              <div style={{ position:'absolute', left:'var(--tabbar-inset)', right:'var(--tabbar-inset)', bottom:'calc(var(--tabbar-offset) + 8px)' }}>
                <TabBar tabs={TABS} value={tab} onChange={setTab} glass />
              </div>
            )}

            {/* sheets */}
            {sheet==='space'  && <SpaceSwitcher space={space} setSpace={setSpace} onClose={()=>setSheet(null)} />}
            {sheet==='create' && <CreateItem space={space} onClose={()=>setSheet(null)} />}
            {sheet==='gen'    && <Generator onClose={()=>setSheet(null)} />}
            {sheet==='totp'   && <TotpList space={space} onClose={()=>setSheet(null)} />}

            {detail && (
              <div style={{ position:'absolute', inset:0, background:'var(--background-grouped)', display:'flex', flexDirection:'column', animation:'slideIn var(--dur-medium) var(--ease-standard)' }}>
                <ItemDetail item={detail} onBack={()=>setDetail(null)} />
              </div>
            )}
            {sheet==='settings' && (
              <div style={{ position:'absolute', inset:0, background:'var(--background-grouped)', display:'flex', flexDirection:'column', animation:'slideIn var(--dur-medium) var(--ease-standard)' }}>
                <Appearance theme={theme} setTheme={setTheme} accent={accent} setAccent={setAccent} onClose={()=>setSheet(null)} />
              </div>
            )}
          </div>
        )}
        <div style={{ position:'absolute', bottom:8, left:'50%', transform:'translateX(-50%)', width:140, height:5, borderRadius:3, background:'var(--text-primary)', opacity:0.32, zIndex:60 }} />
      </IPhone>

      <DemoControls locked={locked} theme={theme} setTheme={setTheme} accent={accent} setAccent={setAccent} onLock={()=>setLocked(true)} />
    </div>
  );
}

function DemoControls({ locked, theme, setTheme, accent, setAccent, onLock }){
  return (
    <div style={{ width:230, display:'flex', flexDirection:'column', gap:18, paddingTop:8 }}>
      <div>
        <p style={{ margin:'0 0 8px', font:'600 12px var(--font-text)', letterSpacing:'0.4px', textTransform:'uppercase', color:'#8a8a8e' }}>Chế độ</p>
        <SegmentedControl value={theme} onChange={setTheme} options={[{value:'light',label:'Sáng'},{value:'dark',label:'Tối'}]} />
      </div>
      <div>
        <p style={{ margin:'0 0 10px', font:'600 12px var(--font-text)', letterSpacing:'0.4px', textTransform:'uppercase', color:'#8a8a8e' }}>Màu nhấn</p>
        <div style={{ display:'flex', gap:12, flexWrap:'wrap' }}>
          {window.ACCENTS.map(a=>{ const sel=a.id===accent, col=theme==='dark'?a.dark:a.light;
            return <button key={a.id} onClick={()=>setAccent(a.id)} aria-label={a.id} style={{ width:34, height:34, borderRadius:'50%',
              border:'none', cursor:'pointer', background:col, position:'relative', boxShadow: sel?`0 0 0 2px #fff, 0 0 0 4px ${col}`:'none' }}>
              {sel && <Icon name="success" size={16} color="#fff" style={{ position:'absolute', inset:0, margin:'auto' }} />}
            </button>; })}
        </div>
      </div>
      {!locked && <Button variant="secondary" leadingIcon="lock" onClick={onLock}>Khoá kho</Button>}
      <p style={{ margin:0, font:'400 12px var(--font-text)', lineHeight:'17px', color:'#8a8a8e', textWrap:'pretty' }}>
        Đổi chế độ &amp; màu nhấn để thấy toàn bộ giao diện đổi tức thì — không cần khởi động lại, không desync.</p>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App />);

/* expose helpers for sibling screen files (ItemDetail) */
Object.assign(window, { SPACES, spaceById, rotationStatus, attentionReason, ITEMS });

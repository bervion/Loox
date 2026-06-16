/* Watchtower — vault health & monitoring report. */
function ScoreRing({ value=82 }) {
  const r = 52, c = 2*Math.PI*r, off = c*(1-value/100);
  const color = value>=80?'var(--success)':value>=50?'var(--warning)':'var(--destructive)';
  return (
    <div style={{ position:'relative', width:140, height:140 }}>
      <svg width="140" height="140" viewBox="0 0 140 140" style={{ transform:'rotate(-90deg)' }} aria-hidden="true">
        <circle cx="70" cy="70" r={r} fill="none" stroke="color-mix(in srgb, var(--text-primary) 10%, transparent)" strokeWidth="11" />
        <circle cx="70" cy="70" r={r} fill="none" stroke={color} strokeWidth="11" strokeLinecap="round"
          strokeDasharray={c} strokeDashoffset={off} style={{ transition:'stroke-dashoffset var(--dur-slow) var(--ease-standard)' }} />
      </svg>
      <div style={{ position:'absolute', inset:0, display:'flex', flexDirection:'column', alignItems:'center', justifyContent:'center' }}>
        <span style={{ fontFamily:'var(--font-display)', fontSize:40, fontWeight:700, color:'var(--text-primary)', lineHeight:1, fontVariantNumeric:'tabular-nums' }}>{value}</span>
        <span style={{ fontFamily:'var(--font-text)', fontSize:13, color:'var(--text-secondary)', marginTop:2 }}>trên 100</span>
      </div>
    </div>
  );
}

function Watchtower() {
  const issues = [
    { id:'comp', icon:'warning', tint:'var(--destructive)', title:'Mật khẩu bị lộ', sub:'1 mục trong rò rỉ dữ liệu', count:1, tone:'destructive' },
    { id:'reuse', icon:'copy', tint:'var(--warning)', title:'Dùng lại mật khẩu', sub:'3 mục dùng chung mật khẩu', count:3, tone:'warning' },
    { id:'weak', icon:'lock', tint:'var(--warning)', title:'Mật khẩu yếu', sub:'2 mục dễ đoán', count:2, tone:'warning' },
    { id:'2fa', icon:'success', tint:'var(--accent)', title:'Bật xác thực 2 lớp', sub:'4 mục hỗ trợ 2FA', count:4, tone:'accent' },
  ];
  return (
    <div style={{ flex:1, minHeight:0, overflowY:'auto', background:'var(--background-grouped)' }}>
      <div style={{ padding:'4px var(--screen-gutter) 0' }}>
        <h1 style={{ margin:'0 0 16px', fontFamily:'var(--font-display)', fontSize:28, fontWeight:700, letterSpacing:'-0.4px', color:'var(--text-primary)' }}>Giám sát</h1>
      </div>
      <div style={{ display:'flex', flexDirection:'column', alignItems:'center', padding:'4px 0 8px' }}>
        <ScoreRing value={82} />
        <p style={{ margin:'12px 24px 0', textAlign:'center', fontFamily:'var(--font-text)', fontSize:15, color:'var(--text-secondary)', textWrap:'pretty' }}>
          Kho của bạn khá an toàn. Khắc phục 6 vấn đề bên dưới để đạt điểm cao hơn.</p>
      </div>

      <div style={{ padding:'18px var(--screen-gutter) var(--tabbar-bottom-pad)', display:'flex', flexDirection:'column', gap:22 }}>
        <section>
          <SectionHeader title="Cần xử lý" />
          <Card variant="grouped">
            {issues.map((it,i)=> <Row key={it.id} leading={<IconTile name={it.icon} tint={it.tint} soft />}
              title={it.title} subtitle={it.sub}
              trailing={<span style={{ display:'inline-flex', alignItems:'center', gap:8 }}>
                <Badge count={it.count} tone={it.tone==='accent'?'success':it.tone} />
              </span>}
              chevron divider={i<issues.length-1} onClick={()=>{}} />)}
          </Card>
        </section>
      </div>
    </div>
  );
}
window.Watchtower = Watchtower;

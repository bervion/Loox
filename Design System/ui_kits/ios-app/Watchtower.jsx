/* Watchtower — vault health & monitoring report. */
function ScoreRing({ value=82 }) {
  // ---- speedometer geometry: 270° arc, open at the bottom ----
  const W=232, H=196, CX=W/2, CY=104, R=86, BAND=18;
  const START=135, SWEEP=270;
  const f = Math.max(0, Math.min(1, value/100));
  const polar = (rad, deg) => {
    const a = deg*Math.PI/180;
    return [CX + rad*Math.cos(a), CY + rad*Math.sin(a)];
  };
  const arc = (rad, d0, d1) => {
    const [x0,y0]=polar(rad,d0), [x1,y1]=polar(rad,d1);
    const large = (d1-d0) > 180 ? 1 : 0;
    return `M ${x0.toFixed(2)} ${y0.toFixed(2)} A ${rad} ${rad} 0 ${large} 1 ${x1.toFixed(2)} ${y1.toFixed(2)}`;
  };
  const endDeg = START + SWEEP*f;
  // gradient-position colour at the fill tip (green → blue)
  const lerp = (a,b,t)=>Math.round(a+(b-a)*t);
  const hex = (t)=>`rgb(${lerp(0x16,0x38,t)},${lerp(0xA3,0xBD,t)},${lerp(0x4A,0xF8,t)})`;
  const tip = hex(f);
  // ticks
  const NT = 44;
  const ticks = [];
  for (let i=0;i<=NT;i++){
    const deg = START + SWEEP*(i/NT);
    const major = i%4===0;
    const L = major?11:8;
    const [ax,ay]=polar(R-L/2, deg), [bx,by]=polar(R+L/2, deg);
    ticks.push({ ax,ay,bx,by, w: major?2.4:1.5 });
  }
  // marker triangle at the fill tip, pointing outward into the band
  const baseR = R - BAND/2 - 6;
  const half = (16/baseR)*(180/Math.PI);
  const [mx,my]=polar(baseR + 13, endDeg);
  const [m1x,m1y]=polar(baseR, endDeg-half);
  const [m2x,m2y]=polar(baseR, endDeg+half);
  const band = ScoreRing.band(value);
  const uid = 'sg'+Math.round(value);
  return (
    <div style={{ position:'relative', width:W, height:H }}>
      <svg width={W} height={H} viewBox={`0 0 ${W} ${H}`} aria-hidden="true">
        <defs>
          <linearGradient id={uid+'g'} gradientUnits="userSpaceOnUse" x1={CX-R} y1={CY} x2={CX+R} y2={CY}>
            <stop offset="0%"  stopColor="#16A34A" />
            <stop offset="50%" stopColor="#10B981" />
            <stop offset="100%" stopColor="#38BDF8" />
          </linearGradient>
          <filter id={uid+'f'} x="-30%" y="-30%" width="160%" height="160%">
            <feDropShadow dx="0" dy="3" stdDeviation="5" floodColor="#10B981" floodOpacity="0.28" />
          </filter>
        </defs>
        {/* track */}
        <path d={arc(R, START, START+SWEEP)} fill="none" strokeWidth={BAND} strokeLinecap="round"
          stroke="color-mix(in srgb, var(--text-primary) 7%, transparent)" />
        {/* filled gradient */}
        <path d={arc(R, START, endDeg)} fill="none" strokeWidth={BAND} strokeLinecap="round"
          stroke={`url(#${uid}g)`} filter={`url(#${uid}f)`}
          style={{ transition:'all var(--dur-slow) var(--ease-standard)' }} />
        {/* tick notches */}
        <g stroke="color-mix(in srgb, var(--text-primary) 16%, transparent)" strokeLinecap="round">
          {ticks.map((t,i)=> <line key={i} x1={t.ax} y1={t.ay} x2={t.bx} y2={t.by} strokeWidth={t.w} />)}
        </g>
        {/* marker triangle */}
        <path d={`M ${mx.toFixed(2)} ${my.toFixed(2)} L ${m1x.toFixed(2)} ${m1y.toFixed(2)} L ${m2x.toFixed(2)} ${m2y.toFixed(2)} Z`}
          fill={tip} style={{ transition:'all var(--dur-slow) var(--ease-standard)' }} />
        {/* center readout */}
        <text x={CX} y={CY+6} textAnchor="middle"
          style={{ fontFamily:'var(--font-display)', fontSize:'52px', fontWeight:700, letterSpacing:'-2px', fill:'var(--text-primary)', fontVariantNumeric:'tabular-nums' }}>{value}</text>
        <text x={CX} y={CY+30} textAnchor="middle"
          style={{ fontFamily:'var(--font-text)', fontSize:'12px', fontWeight:700, letterSpacing:'1.4px', fill:band.a }}>{band.label.toUpperCase()}</text>
      </svg>
    </div>
  );
}
ScoreRing.band = (value)=> value>=80
  ? { a:'var(--success)',     glow:'var(--success)',     label:'Khá an toàn' }
  : value>=50
  ? { a:'var(--warning)',     glow:'var(--warning)',     label:'Cần chú ý'   }
  : { a:'var(--destructive)', glow:'var(--destructive)', label:'Rủi ro cao'  };

/* Overall password-strength meter — 1Password style. */
function StrengthBar({ value=72 }) {
  const spectrum = ['#22C55E','#65D43A','#A3E635','#FACC15','#FBBF24','#F59E0B','#F97316','#EF4444'];
  return (
    <div style={{ display:'flex', alignItems:'stretch', gap:5, height:14 }}>
      <div style={{ width:`${value}%`, minWidth:14, background:'var(--success)', borderRadius:999,
        transition:'width var(--dur-slow) var(--ease-standard)' }} />
      <div style={{ flex:1, display:'flex', gap:5 }}>
        {spectrum.map((c,i)=> <div key={i} style={{ flex:1, background:c, borderRadius:4, opacity:0.9 }} />)}
      </div>
    </div>
  );
}

function StrengthCard({ value=72, onClick }) {
  const [pressed,setPressed] = React.useState(false);
  return (
    <Card variant="base" padding="0" style={{ overflow:'hidden' }}>
      <div role="button" onClick={onClick}
        onPointerDown={()=>setPressed(true)} onPointerUp={()=>setPressed(false)} onPointerLeave={()=>setPressed(false)}
        style={{ display:'flex', flexDirection:'column', gap:14, padding:'16px var(--space-4)',
          cursor:'pointer', background: pressed?'var(--surface-pressed)':'transparent',
          transition:'background var(--dur-fast)', WebkitTapHighlightColor:'transparent' }}>
        <div style={{ display:'flex', alignItems:'center', gap:8 }}>
          <span style={{ flex:1, fontFamily:'var(--font-text)', fontSize:17, fontWeight:600, color:'var(--text-primary)' }}>
            Độ mạnh mật khẩu tổng thể</span>
          <Icon name="chevron.right" size={16} color="var(--icon-disabled)" />
        </div>
        <StrengthBar value={value} />
      </div>
    </Card>
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
        <p style={{ margin:'6px 28px 0', textAlign:'center', fontFamily:'var(--font-text)', fontSize:15, color:'var(--text-secondary)', textWrap:'pretty' }}>
          Khắc phục 6 vấn đề bên dưới để nâng điểm bảo mật của kho.</p>
      </div>

      <div style={{ padding:'18px var(--screen-gutter) var(--tabbar-bottom-pad)', display:'flex', flexDirection:'column', gap:22 }}>
        <StrengthCard value={72} onClick={()=>{}} />
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

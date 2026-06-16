/* ============================================================
   Vaultify UI kit — local primitives
   Self-contained, cosmetic mirrors of the design-system core
   components (so the kit renders without the compiled bundle).
   Same tokens, same look. Attached to window for screen files.
   ============================================================ */

const POLARIS_BASE = 'https://unpkg.com/@shopify/polaris-icons@7.13.0/dist/svg/';
const ICON_MAP = {
  home:'HomeMajor','home.fill':'HomeFilledMinor',
  items:'CollectionsMajor','items.fill':'CollectionsFilledMajor',
  watchtower:'FraudProtectMajor', search:'SearchMinor', categories:'CategoriesMajor',
  login:'KeyMajor', password:'KeyMajor', card:'CreditCardMajor', identity:'IdentityCardMajor',
  note:'ContentMinor', email:'EmailMajor', website:'GlobeMajor', bank:'BankMajor', wifi:'GlobeMajor',
  copy:'DuplicateMinor', view:'ViewMinor', hide:'HideMinor', edit:'EditMinor', delete:'DeleteMinor',
  add:'AddMajor','add.circle':'CirclePlusMinor', refresh:'RefreshMajor', filter:'FilterMajor',
  settings:'SettingsMajor', profile:'CustomersMajor', exit:'ExitMajor', more:'HorizontalDotsMinor',
  share:'ExportMinor', external:'ExternalMinor',
  'chevron.right':'ChevronRightMinor','chevron.left':'ChevronLeftMinor',
  'chevron.down':'ChevronDownMinor','chevron.up':'ChevronUpMinor',
  lock:'LockMajor', unlock:'KeyMajor', success:'CircleTickMajor', alert:'AlertMinor',
  warning:'DiamondAlertMajor', info:'InfoMinor', favorite:'FavoriteMajor', clock:'ClockMajor',
};
const iconUrl = (n) => `${POLARIS_BASE}${ICON_MAP[n] || n}.svg`;
const _svgCache = {};
function fetchIconSvg(url){ if(!_svgCache[url]) _svgCache[url]=fetch(url).then(r=>r.ok?r.text():'').catch(()=>''); return _svgCache[url]; }

function Icon({ name, size = 20, color = 'currentColor', style }) {
  const ref = React.useRef(null);
  const dim = typeof size === 'number' ? size + 'px' : size;
  const url = iconUrl(name);
  React.useEffect(() => {
    let alive = true;
    fetchIconSvg(url).then(txt => {
      if (!alive || !ref.current || !txt) return;
      ref.current.innerHTML = txt;
      const svg = ref.current.querySelector('svg');
      if (svg) { svg.setAttribute('width','100%'); svg.setAttribute('height','100%'); svg.style.display='block'; svg.style.fill=color; }
    });
    return () => { alive = false; };
  }, [url, color]);
  return <span ref={ref} aria-hidden="true" style={{
    display:'inline-flex', alignItems:'center', justifyContent:'center', flex:'0 0 auto',
    width:dim, height:dim, color, ...style }} />;
}

function IconTile({ name, tint='var(--accent)', onTint='var(--on-accent)', size=32, soft=false, radius='var(--radius-sm)', iconSize, style }) {
  const bg = soft ? `color-mix(in srgb, ${tint} 16%, transparent)` : tint;
  const fg = soft ? tint : onTint;
  return <span style={{ display:'inline-flex', alignItems:'center', justifyContent:'center',
    width:size, height:size, flex:'0 0 auto', borderRadius:radius, background:bg, ...style }}>
    <Icon name={name} size={iconSize || Math.round(size*0.6)} color={fg} />
  </span>;
}

function usePress(){ const [p,set]=React.useState(false);
  return [p, { onPointerDown:()=>set(true), onPointerUp:()=>set(false), onPointerLeave:()=>set(false) }]; }

function Button({ children, variant='primary', size='md', fullWidth=false, leadingIcon, trailingIcon, disabled, onClick, style }) {
  const [pressed, bind] = usePress();
  const S = { sm:{h:34,px:14,f:15,r:'var(--radius-sm)'}, md:{h:44,px:18,f:17,r:'var(--radius-sm)'}, lg:{h:52,px:22,f:17,r:'var(--radius-md)'} }[size];
  const V = {
    primary:{ background: pressed&&!disabled?'var(--accent-press)':'var(--accent)', color:'var(--on-accent)' },
    secondary:{ background: pressed?'var(--surface-pressed)':'var(--surface-base)', color:'var(--text-primary)', boxShadow:'inset 0 0 0 1px var(--separator)' },
    ghost:{ background: pressed?'var(--surface-pressed)':'transparent', color:'var(--accent)' },
    destructive:{ background:'var(--destructive-soft)', color:'var(--destructive)' },
  }[variant];
  return <button onClick={onClick} disabled={disabled} {...bind} style={{
    display:'inline-flex', alignItems:'center', justifyContent:'center', gap:8,
    width:fullWidth?'100%':'auto', minHeight:S.h, padding:`0 ${S.px}px`, border:'none', borderRadius:S.r,
    fontFamily:'var(--font-text)', fontSize:S.f, fontWeight:600, letterSpacing:'-0.2px', lineHeight:1,
    cursor:disabled?'default':'pointer', opacity:disabled?0.4:1,
    transform: pressed&&!disabled?'scale(0.97)':'scale(1)',
    transition:'transform var(--dur-fast) var(--ease-standard), background var(--dur-fast) var(--ease-standard)',
    WebkitTapHighlightColor:'transparent', ...V, ...style }}>
    {leadingIcon && <Icon name={leadingIcon} size={18} />}{children}{trailingIcon && <Icon name={trailingIcon} size={18} />}
  </button>;
}

function IconButton({ name, label, size='md', variant='plain', color='var(--icon-primary)', onClick, style }) {
  const [pressed, bind] = usePress();
  const box = { sm:32, md:44, lg:48 }[size], ic = { sm:18, md:22, lg:24 }[size];
  const bg = variant==='filled'?'var(--accent)':variant==='tinted'?'var(--surface-pressed)':(pressed?'var(--surface-pressed)':'transparent');
  return <button aria-label={label} onClick={onClick} {...bind} style={{
    display:'inline-flex', alignItems:'center', justifyContent:'center', width:box, height:box,
    border:'none', borderRadius: variant==='plain'?'var(--radius-sm)':'var(--radius-pill)', background:bg,
    cursor:'pointer', transform:pressed?'scale(0.97)':'scale(1)',
    transition:'transform var(--dur-fast) var(--ease-standard), background var(--dur-fast)',
    WebkitTapHighlightColor:'transparent', padding:0, ...style }}>
    <Icon name={name} size={ic} color={variant==='filled'?'var(--on-accent)':color} />
  </button>;
}

function Card({ children, variant='base', radius='var(--radius-lg)', padding='var(--space-4)', style }) {
  const V = {
    base:{ background:'var(--surface-base)', boxShadow:'0 0 0 0.5px var(--separator)' },
    elevated:{ background:'var(--surface-elevated)', boxShadow:'var(--elevation-2)' },
    grouped:{ background:'var(--surface-base)', boxShadow:'0 0 0 0.5px var(--separator)', padding:0 },
  }[variant];
  return <div style={{ borderRadius:radius, padding: variant==='grouped'?0:padding,
    overflow: variant==='grouped'?'hidden':'visible', ...V, ...style }}>{children}</div>;
}

function Row({ leading, title, subtitle, value, trailing, chevron, tone='default', divider=true, onClick, style }) {
  const [pressed, bind] = usePress();
  const interactive = !!onClick;
  const tc = tone==='destructive'?'var(--destructive)':tone==='accent'?'var(--accent)':'var(--text-primary)';
  return <div role={interactive?'button':undefined} onClick={onClick} {...(interactive?bind:{})} style={{
    position:'relative', display:'flex', alignItems:'center', gap:'var(--space-3)', minHeight:'var(--row-h)',
    padding:'10px var(--space-4)', background: pressed?'var(--surface-pressed)':'transparent',
    cursor:interactive?'pointer':'default', transition:'background var(--dur-fast)', WebkitTapHighlightColor:'transparent', ...style }}>
    {leading}
    <div style={{ flex:1, minWidth:0, display:'flex', flexDirection:'column', gap:1 }}>
      <span style={{ fontFamily:'var(--font-text)', fontSize:17, fontWeight:500, color:tc, lineHeight:'22px',
        whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis' }}>{title}</span>
      {subtitle && <span style={{ fontFamily:'var(--font-text)', fontSize:15, color:'var(--text-secondary)', lineHeight:'20px',
        whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis' }}>{subtitle}</span>}
    </div>
    {value!=null && <span style={{ fontFamily:'var(--font-text)', fontSize:16, color:'var(--text-secondary)', flex:'0 0 auto',
      maxWidth:'45%', whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis' }}>{value}</span>}
    {trailing}
    {chevron && <Icon name="chevron.right" size={16} color="var(--icon-disabled)" />}
    {divider && <span style={{ position:'absolute', left: leading?'calc(var(--space-4) + 32px + var(--space-3))':'var(--space-4)',
      right:0, bottom:0, height:0.5, background:'var(--separator)' }} />}
  </div>;
}

function SectionHeader({ title, action, onAction }) {
  return <div style={{ display:'flex', alignItems:'flex-end', justifyContent:'space-between',
    padding:'0 2px 8px' }}>
    <span style={{ fontFamily:'var(--font-text)', fontSize:13, fontWeight:600, letterSpacing:'0.4px',
      textTransform:'uppercase', color:'var(--text-tertiary)' }}>{title}</span>
    {action && <button onClick={onAction} style={{ border:'none', background:'none', padding:0, cursor:'pointer',
      fontFamily:'var(--font-text)', fontSize:13, fontWeight:600, color:'var(--accent)' }}>{action}</button>}
  </div>;
}

function Switch({ checked, onChange, label }) {
  return <button role="switch" aria-checked={checked} aria-label={label} onClick={()=>onChange&&onChange(!checked)} style={{
    position:'relative', width:51, height:31, flex:'0 0 auto', padding:0, border:'none', borderRadius:'var(--radius-pill)',
    background: checked?'var(--accent)':'color-mix(in srgb, var(--text-primary) 18%, transparent)',
    cursor:'pointer', transition:'background var(--dur-base) var(--ease-standard)', WebkitTapHighlightColor:'transparent' }}>
    <span style={{ position:'absolute', top:2, left:checked?22:2, width:27, height:27, borderRadius:'50%',
      background:'#fff', boxShadow:'0 1px 3px rgba(0,0,0,0.28)', transition:'left var(--dur-base) var(--ease-standard)' }} />
  </button>;
}

function SegmentedControl({ options=[], value, onChange, style }) {
  const opts = options.map(o => typeof o==='string'?{value:o,label:o}:o);
  const idx = Math.max(0, opts.findIndex(o=>o.value===value));
  return <div style={{ position:'relative', display:'grid', gridTemplateColumns:`repeat(${opts.length},1fr)`, gap:2, padding:2,
    background:'color-mix(in srgb, var(--text-primary) 8%, transparent)', borderRadius:'var(--radius-sm)', ...style }}>
    <span style={{ position:'absolute', top:2, bottom:2, left:`calc(${idx} * (100% - 4px) / ${opts.length} + 2px)`,
      width:`calc((100% - 4px) / ${opts.length})`, background:'var(--surface-base)', borderRadius:'calc(var(--radius-sm) - 2px)',
      boxShadow:'0 1px 3px var(--shadow-ambient)', transition:'left var(--dur-base) var(--ease-standard)' }} />
    {opts.map(o => { const a = o.value===value; return <button key={o.value} onClick={()=>onChange&&onChange(o.value)} style={{
      position:'relative', zIndex:1, minHeight:32, border:'none', background:'transparent', cursor:'pointer',
      fontFamily:'var(--font-text)', fontSize:15, fontWeight:a?600:500,
      color:a?'var(--text-primary)':'var(--text-secondary)', WebkitTapHighlightColor:'transparent',
      transition:'color var(--dur-fast)' }}>{o.label}</button>; })}
  </div>;
}

function Badge({ count, dot=false, tone='destructive', max=99 }) {
  const bg = { destructive:'var(--destructive)', accent:'var(--accent)', neutral:'var(--icon-secondary)', success:'var(--success)', warning:'var(--warning)' }[tone];
  if (dot) return <span style={{ display:'inline-block', width:8, height:8, borderRadius:'50%', background:bg, boxShadow:'0 0 0 2px var(--surface-base)' }} />;
  return <span style={{ display:'inline-flex', alignItems:'center', justifyContent:'center', minWidth:18, height:18,
    padding:'0 5px', borderRadius:'var(--radius-pill)', background:bg, color:'#fff', fontFamily:'var(--font-text)',
    fontSize:11, fontWeight:700, lineHeight:1, fontVariantNumeric:'tabular-nums' }}>{count>max?`${max}+`:count}</span>;
}

const STR = [
  {label:'Too weak', color:'var(--destructive)'},{label:'Weak', color:'var(--destructive)'},
  {label:'Fair', color:'var(--warning)'},{label:'Good', color:'var(--accent)'},{label:'Strong', color:'var(--success)'},
];
function StrengthMeter({ score=0, showLabel=true, label, style }) {
  const s = Math.max(0,Math.min(4,score)), lvl = STR[s];
  return <div style={{ display:'flex', flexDirection:'column', gap:6, ...style }}>
    <div style={{ display:'flex', gap:5 }}>{[1,2,3,4].map(seg => <span key={seg} style={{ flex:1, height:4,
      borderRadius:'var(--radius-pill)', background: seg<=s?lvl.color:'color-mix(in srgb, var(--text-primary) 12%, transparent)',
      transition:'background var(--dur-base)' }} />)}</div>
    {showLabel && <span style={{ fontFamily:'var(--font-text)', fontSize:13, fontWeight:500, color:lvl.color }}>{label||lvl.label}</span>}
  </div>;
}

function TabBar({ tabs=[], value, onChange, glass=false, style }) {
  const idx = Math.max(0, tabs.findIndex(t=>t.id===value)), n = tabs.length||1;
  return <nav aria-label="Primary" style={{ position:'relative', display:'grid', gridTemplateColumns:`repeat(${n},1fr)`,
    alignItems:'center', height:'var(--tabbar-height)', padding:'0 6px', borderRadius:'var(--tabbar-radius)',
    background: glass?'var(--surface-floating)':'var(--surface-floating-solid)',
    backdropFilter: glass?'blur(24px) saturate(1.8)':'none', WebkitBackdropFilter: glass?'blur(24px) saturate(1.8)':'none',
    boxShadow:'var(--elevation-3), 0 0 0 0.5px var(--separator)', ...style }}>
    <span style={{ position:'absolute', top:'50%', height:44, width:46, transform:'translateY(-50%)',
      left:`calc(${idx} * (100% - 12px) / ${n} + (100% - 12px) / ${n} / 2 - 23px + 6px)`,
      background:'var(--accent-soft)', borderRadius:'var(--radius-pill)', transition:'left var(--dur-medium) var(--ease-spring)' }} />
    {tabs.map(t => { const a = t.id===value, nm = a&&t.iconFill?t.iconFill:t.icon;
      return <button key={t.id} role="tab" aria-selected={a} aria-label={t.label} onClick={()=>onChange&&onChange(t.id)} style={{
        position:'relative', zIndex:1, display:'inline-flex', alignItems:'center', justifyContent:'center',
        minWidth:56, minHeight:48, height:'100%', border:'none', background:'transparent', cursor:'pointer', padding:0,
        WebkitTapHighlightColor:'transparent' }}>
        <span style={{ position:'relative', display:'inline-flex' }}>
          <Icon name={nm} size={a?27:24} color={a?'var(--accent)':'var(--icon-secondary)'} />
          {(t.badge!=null||t.badgeDot) && <span style={{ position:'absolute', top:-3, right:-8 }}><Badge dot={t.badgeDot} count={t.badge} /></span>}
        </span>
      </button>; })}
  </nav>;
}

/* ---- iPhone frame + status bar (device chrome, drawn) ---- */
function StatusBar() {
  const c = 'var(--text-primary)';
  return <div style={{ height:54, display:'flex', alignItems:'center', justifyContent:'space-between',
    padding:'0 30px 0 34px', flex:'0 0 auto' }}>
    <span style={{ fontFamily:'var(--font-text)', fontSize:16, fontWeight:600, color:c, letterSpacing:'-0.2px' }}>9:41</span>
    <div style={{ display:'flex', alignItems:'center', gap:7 }}>
      {/* cellular */}
      <svg width="18" height="12" viewBox="0 0 18 12" aria-hidden="true">
        {[0,1,2,3].map(i=> <rect key={i} x={i*4.6} y={9-i*2.6} width="3" height={3+i*2.6} rx="1" fill={c} />)}
      </svg>
      {/* wifi */}
      <svg width="17" height="12" viewBox="0 0 17 12" fill="none" stroke={c} strokeWidth="1.6" strokeLinecap="round" aria-hidden="true">
        <path d="M2 4.3C6 1 11 1 15 4.3" /><path d="M4.3 7C6.6 5 10.4 5 12.7 7" /><circle cx="8.5" cy="9.6" r="0.9" fill={c} stroke="none" />
      </svg>
      {/* battery */}
      <span style={{ width:25, height:13, borderRadius:3, boxShadow:`inset 0 0 0 1.2px ${c}`, position:'relative', opacity:0.95 }}>
        <span style={{ position:'absolute', top:2, bottom:2, left:2, width:'72%', background:c, borderRadius:1.5 }} />
      </span>
    </div>
  </div>;
}

function IPhone({ children, theme='light', accent='blue' }) {
  return <div data-theme={theme} data-accent={accent} style={{
    width:390, height:844, borderRadius:54, background:'var(--background-base)', position:'relative',
    overflow:'hidden', boxShadow:'0 1px 0 1px rgba(0,0,0,0.04), 0 30px 70px rgba(0,0,0,0.28), inset 0 0 0 1px var(--separator)',
    display:'flex', flexDirection:'column' }}>
    {/* dynamic island */}
    <div style={{ position:'absolute', top:11, left:'50%', transform:'translateX(-50%)', width:124, height:36,
      background:'#000', borderRadius:20, zIndex:50 }} />
    {children}
  </div>;
}

Object.assign(window, { Icon, IconTile, Button, IconButton, Card, Row, SectionHeader, Switch,
  SegmentedControl, Badge, StrengthMeter, TabBar, StatusBar, IPhone, iconUrl, ICON_MAP });

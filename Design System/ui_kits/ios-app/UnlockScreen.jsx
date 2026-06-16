/* Unlock screen — master password + biometric, the app's front door. */
function UnlockScreen({ onUnlock }) {
  const [pw, setPw] = React.useState('');
  return (
    <div style={{ flex:1, display:'flex', flexDirection:'column', alignItems:'center',
      padding:'0 28px', background:'var(--background-base)' }}>
      <div style={{ flex:'0 0 auto', height:96 }} />
      {/* brand mark */}
      <div style={{ width:84, height:84, borderRadius:22, background:'var(--accent)',
        display:'flex', alignItems:'center', justifyContent:'center',
        boxShadow:'0 12px 30px color-mix(in srgb, var(--accent) 40%, transparent)' }}>
        <Icon name="lock" size={42} color="var(--on-accent)" />
      </div>
      <h1 style={{ margin:'22px 0 4px', fontFamily:'var(--font-display)', fontSize:28, fontWeight:700,
        letterSpacing:'-0.4px', color:'var(--text-primary)' }}>Vaultify</h1>
      <p style={{ margin:0, fontFamily:'var(--font-text)', fontSize:15, color:'var(--text-secondary)' }}>
        Mở khoá kho của bạn</p>

      <div style={{ width:'100%', marginTop:40, display:'flex', flexDirection:'column', gap:14 }}>
        <span style={{ display:'flex', alignItems:'center', gap:10, minHeight:52, padding:'0 16px',
          background:'var(--surface-base)', borderRadius:'var(--radius-sm)', boxShadow:'inset 0 0 0 1px var(--separator)' }}>
          <Icon name="unlock" size={20} color="var(--icon-secondary)" />
          <input type="password" value={pw} onChange={(e)=>setPw(e.target.value)}
            placeholder="Mật khẩu chính" autoFocus
            style={{ flex:1, minWidth:0, border:'none', outline:'none', background:'transparent',
              color:'var(--text-primary)', fontFamily:'var(--font-mono)', fontSize:17, letterSpacing:'0.12em' }} />
        </span>
        <Button fullWidth size="lg" onClick={onUnlock} disabled={pw.length<1}>Mở khoá</Button>
      </div>

      <button onClick={onUnlock} style={{ marginTop:'auto', marginBottom:44, display:'flex', flexDirection:'column',
        alignItems:'center', gap:10, border:'none', background:'none', cursor:'pointer' }}>
        <span style={{ width:58, height:58, borderRadius:16, display:'flex', alignItems:'center', justifyContent:'center',
          background:'var(--surface-pressed)' }}>
          {/* Face ID glyph — custom (Polaris has no biometric icon; see README) */}
          <svg width="32" height="32" viewBox="0 0 32 32" fill="none" stroke="var(--accent)" strokeWidth="2.2"
            strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <path d="M5 10V7a2 2 0 0 1 2-2h3M22 5h3a2 2 0 0 1 2 2v3M27 22v3a2 2 0 0 1-2 2h-3M10 27H7a2 2 0 0 1-2-2v-3"/>
            <path d="M12 13v2M20 13v2M16 13v4l-1.5 1.5"/>
            <path d="M12 21c1.2 1 2.5 1.4 4 1.4s2.8-.4 4-1.4"/>
          </svg>
        </span>
        <span style={{ fontFamily:'var(--font-text)', fontSize:14, fontWeight:600, color:'var(--accent)' }}>Mở bằng Face ID</span>
      </button>
    </div>
  );
}
window.UnlockScreen = UnlockScreen;

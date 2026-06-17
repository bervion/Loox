/* Appearance & security settings — live theming (Telegram-style). */
const ACCENTS = [
  { id:'blue', light:'#2563eb', dark:'#4c8dff' },
  { id:'indigo', light:'#5145cd', dark:'#8b80ff' },
  { id:'teal', light:'#0e8a7d', dark:'#2fd0bf' },
  { id:'purple', light:'#7c3aed', dark:'#b388ff' },
  { id:'pink', light:'#d6256e', dark:'#ff77ab' },
  { id:'graphite', light:'#4b4b50', dark:'#aeaeb2' },
  { id:'mono', light:'#1c1c1e', dark:'#ffffff' },
];

function Appearance({ theme, setTheme, accent, setAccent, onClose }) {
  const [faceId, setFaceId] = React.useState(true);
  const [lockSwitch, setLockSwitch] = React.useState(true);
  const isDark = theme === 'dark';
  return (
    <div style={{ flex:1, minHeight:0, overflowY:'auto', background:'var(--background-grouped)' }}>
      <div style={{ position:'sticky', top:0, zIndex:10, display:'flex', alignItems:'center', justifyContent:'space-between',
        padding:'4px var(--space-3)', minHeight:44, background:'color-mix(in srgb, var(--background-grouped) 82%, transparent)', backdropFilter:'blur(12px)', WebkitBackdropFilter:'blur(12px)' }}>
        <span style={{ fontFamily:'var(--font-text)', fontSize:17, fontWeight:600, color:'var(--text-primary)' }}>Giao diện</span>
        <button onClick={onClose} style={{ border:'none', background:'none', cursor:'pointer', color:'var(--accent)', fontFamily:'var(--font-text)', fontSize:17, fontWeight:600, padding:'8px 10px' }}>Xong</button>
      </div>

      <div style={{ padding:'8px var(--screen-gutter) var(--tabbar-bottom-pad)', display:'flex', flexDirection:'column', gap:24 }}>
        <section>
          <SectionHeader title="Chế độ" />
          <SegmentedControl value={theme} onChange={setTheme}
            options={[{value:'light',label:'Sáng'},{value:'dark',label:'Tối'}]} />
        </section>

        <section>
          <SectionHeader title="Màu nhấn" />
          <Card padding="18px">
            <div style={{ display:'flex', justifyContent:'space-between' }}>
              {ACCENTS.map(a => {
                const sel = a.id===accent;
                const sw = isDark?a.dark:a.light;
                const lightSwatch = (parseInt(sw.slice(1,3),16)*0.299 + parseInt(sw.slice(3,5),16)*0.587 + parseInt(sw.slice(5,7),16)*0.114) > 150;
                return <button key={a.id} onClick={()=>setAccent(a.id)} aria-label={a.id} style={{
                  width:42, height:42, borderRadius:'50%', cursor:'pointer', padding:0,
                  border: lightSwatch?'1px solid var(--separator)':'none',
                  background: sw, position:'relative', WebkitTapHighlightColor:'transparent',
                  boxShadow: sel?`0 0 0 3px var(--surface-base), 0 0 0 5px ${sw}`:'none',
                  transition:'box-shadow var(--dur-fast)' }}>
                  {sel && <Icon name="success" size={20} color={lightSwatch?'#1c1c1e':'#fff'} style={{ position:'absolute', inset:0, margin:'auto' }} />}
                </button>;
              })}
            </div>
          </Card>
          <p style={{ margin:'8px 4px 0', fontFamily:'var(--font-text)', fontSize:13, color:'var(--text-tertiary)', textWrap:'pretty' }}>
            Màu nhấn áp dụng tức thì cho toàn bộ ứng dụng — không cần khởi động lại.</p>
        </section>

        <section>
          <SectionHeader title="Bảo mật" />
          <Card variant="grouped">
            <Row leading={<IconTile name="unlock" tint="var(--accent)" />} title="Mở khoá bằng Face ID"
              trailing={<Switch checked={faceId} onChange={setFaceId} label="Face ID" />} />
            <Row leading={<IconTile name="lock" tint="var(--icon-secondary)" soft />} title="Khoá khi chuyển ứng dụng"
              trailing={<Switch checked={lockSwitch} onChange={setLockSwitch} label="Khoá khi chuyển" />} />
            <Row leading={<IconTile name="clock" tint="var(--icon-secondary)" soft />} title="Tự động khoá" value="Sau 1 phút" chevron divider={false} onClick={()=>{}} />
          </Card>
        </section>

        <section>
          <Card variant="grouped">
            <Row leading={<IconTile name="exit" tint="var(--destructive)" soft />} title="Khoá kho ngay" tone="destructive" divider={false} onClick={onClose} />
          </Card>
        </section>
      </div>
    </div>
  );
}
window.Appearance = Appearance;
window.ACCENTS = ACCENTS;

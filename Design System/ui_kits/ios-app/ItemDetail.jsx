/* Item detail — credential view: space, copyable fields, password reveal +
   strength, live TOTP, and password-rotation status. */
function CopyField({ label, value, mono, secure }) {
  const [revealed, setRevealed] = React.useState(!secure);
  const [copied, setCopied] = React.useState(false);
  const display = secure && !revealed ? '••••••••••••' : value;
  function copy(){ setCopied(true); setTimeout(()=>setCopied(false), 1100); }
  return (
    <div style={{ position:'relative', display:'flex', alignItems:'center', gap:10, minHeight:58, padding:'8px var(--space-4)' }}>
      <div style={{ flex:1, minWidth:0, display:'flex', flexDirection:'column', gap:2 }}>
        <span style={{ fontFamily:'var(--font-text)', fontSize:13, fontWeight:500, color:'var(--text-secondary)' }}>{label}</span>
        <span style={{ fontFamily: mono?'var(--font-mono)':'var(--font-text)', fontSize:17, color:'var(--text-primary)',
          letterSpacing: mono?(secure&&!revealed?'0.16em':'0.04em'):'normal', whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis' }}>{display}</span>
      </div>
      {secure && <IconButton name={revealed?'hide':'view'} label={revealed?'Ẩn':'Hiện'} size="sm" color="var(--icon-secondary)" onClick={()=>setRevealed(r=>!r)} />}
      <IconButton name={copied?'success':'copy'} label="Sao chép" size="sm" color={copied?'var(--success)':'var(--accent)'} onClick={copy} />
      <span style={{ position:'absolute', left:'var(--space-4)', right:0, bottom:0, height:0.5, background:'var(--separator)' }} />
    </div>
  );
}

/* Live TOTP row inside the detail */
function TotpField({ seed }){
  const { code, remaining, progress } = useTotp(seed);
  const [copied,setCopied] = React.useState(false);
  return (
    <div onClick={()=>{setCopied(true);setTimeout(()=>setCopied(false),1100);}} role="button"
      style={{ display:'flex', alignItems:'center', gap:12, minHeight:62, padding:'8px var(--space-4)', cursor:'pointer' }}>
      <div style={{ flex:1, minWidth:0 }}>
        <div style={{ fontFamily:'var(--font-text)', fontSize:13, fontWeight:500, color:'var(--text-secondary)' }}>Mã xác thực (2FA)</div>
        <div style={{ fontFamily:'var(--font-mono)', fontSize:24, fontWeight:600, letterSpacing:'0.1em',
          color: copied?'var(--success)':'var(--accent)', fontVariantNumeric:'tabular-nums' }}>{copied?'Đã sao chép':fmtCode(code)}</div>
      </div>
      <TotpRing progress={progress} remaining={remaining} size={34} />
    </div>
  );
}

function ItemDetail({ item, onBack }) {
  const sp = (window.spaceById||(()=>null))(item.space);
  const rot = (window.rotationStatus||(()=>({state:'ok'})))(item);
  const rotColor = rot.tone==='destructive'?'var(--destructive)':rot.tone==='warning'?'var(--warning)':'var(--text-secondary)';
  return (
    <div style={{ flex:1, minHeight:0, overflowY:'auto', background:'var(--background-grouped)' }}>
      <div style={{ position:'sticky', top:0, zIndex:10, display:'flex', alignItems:'center', justifyContent:'space-between',
        padding:'4px var(--space-2)', minHeight:44, background:'color-mix(in srgb, var(--background-grouped) 82%, transparent)', backdropFilter:'blur(12px)', WebkitBackdropFilter:'blur(12px)' }}>
        <button onClick={onBack} style={{ display:'inline-flex', alignItems:'center', gap:2, border:'none', background:'none',
          cursor:'pointer', color:'var(--accent)', fontFamily:'var(--font-text)', fontSize:17, padding:'8px' }}>
          <Icon name="chevron.left" size={20} color="var(--accent)" /> Kho
        </button>
        <button style={{ border:'none', background:'none', cursor:'pointer', color:'var(--accent)', fontFamily:'var(--font-text)', fontSize:17, padding:'8px 12px' }}>Sửa</button>
      </div>

      <div style={{ display:'flex', flexDirection:'column', alignItems:'center', padding:'8px 0 20px' }}>
        <IconTile name={item.icon} tint={item.tint} size={72} radius="var(--radius-lg)" iconSize={38} />
        <h1 style={{ margin:'14px 0 6px', fontFamily:'var(--font-display)', fontSize:24, fontWeight:700, letterSpacing:'-0.4px', color:'var(--text-primary)' }}>{item.name}</h1>
        <div style={{ display:'flex', alignItems:'center', gap:8 }}>
          {sp && <SpaceTag space={sp} size="md" />}
          <span style={{ fontFamily:'var(--font-text)', fontSize:15, color:'var(--text-secondary)' }}>{item.url||item.username}</span>
        </div>
      </div>

      <div style={{ padding:'0 var(--screen-gutter)', display:'flex', flexDirection:'column', gap:22, paddingBottom:'calc(var(--tabbar-bottom-pad) + 8px)' }}>
        {/* rotation banner */}
        {rot.state!=='ok' && (
          <div style={{ display:'flex', alignItems:'center', gap:12, padding:'14px var(--space-4)', borderRadius:'var(--radius-lg)',
            background: rot.tone==='destructive'?'var(--destructive-soft)':'var(--warning-soft)' }}>
            <Icon name={rot.icon} size={22} color={rotColor} />
            <div style={{ flex:1, minWidth:0 }}>
              <div style={{ fontFamily:'var(--font-text)', fontSize:15, fontWeight:600, color:rotColor }}>{rot.label}</div>
              <div style={{ fontFamily:'var(--font-text)', fontSize:13, color:'var(--text-secondary)' }}>
                {item.rotateDays>0 ? `Nhắc đổi mỗi ${item.rotateDays} ngày` : 'Nên cập nhật mật khẩu mới'}</div>
            </div>
            <Button size="sm" variant={rot.tone==='destructive'?'primary':'secondary'} onClick={()=>{}}>Đổi</Button>
          </div>
        )}

        <Card variant="grouped">
          <CopyField label="Tên đăng nhập" value={item.username} />
          <CopyField label="Mật khẩu" value={item.password} mono secure />
          {item.totp && <TotpField seed={item.totp} />}
          <div style={{ padding:'12px var(--space-4) 14px' }}>
            <StrengthMeter score={item.score} label={item.scoreLabel} />
          </div>
        </Card>

        <Card variant="grouped">
          {item.url && <Row leading={<IconTile name="website" tint="var(--icon-secondary)" soft />} title="Mở trang web" value={item.url} tone="accent" chevron onClick={()=>{}} />}
          <Row leading={<IconTile name="clock" tint="var(--icon-secondary)" soft />} title="Đổi gần nhất"
            value={item.changed>=30?`${Math.round(item.changed/30)} tháng trước`:`${item.changed} ngày trước`} divider={item.rotateDays>0} />
          {item.rotateDays>0 && <Row leading={<IconTile name="refresh" tint="var(--accent)" soft />} title="Nhắc đổi mật khẩu" value={`Mỗi ${item.rotateDays} ngày`} chevron divider={false} onClick={()=>{}} />}
        </Card>

        <Card variant="grouped">
          <Row leading={<IconTile name="favorite" tint="#d6256e" soft />} title="Yêu thích" trailing={<Switch checked={!!item.fav} onChange={()=>{}} label="Yêu thích" />} />
          <Row leading={<IconTile name="delete" tint="var(--destructive)" soft />} title="Xoá mục" tone="destructive" divider={false} onClick={()=>{}} />
        </Card>
      </div>
    </div>
  );
}
window.ItemDetail = ItemDetail;

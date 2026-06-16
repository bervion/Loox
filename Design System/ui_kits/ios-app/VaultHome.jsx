/* Vault home — "Kho". Screen title, search, grouped item lists. */
function Favicon({ item, size=32 }) {
  return <IconTile name={item.icon} tint={item.tint} size={size} radius="var(--radius-sm)" />;
}

function SearchPill({ onClick }) {
  return <button onClick={onClick} style={{ display:'flex', alignItems:'center', gap:8, width:'100%',
    minHeight:40, padding:'0 12px', border:'none', borderRadius:'var(--radius-sm)',
    background:'color-mix(in srgb, var(--text-primary) 7%, transparent)', cursor:'pointer', WebkitTapHighlightColor:'transparent' }}>
    <Icon name="search" size={18} color="var(--icon-secondary)" />
    <span style={{ fontFamily:'var(--font-text)', fontSize:16, color:'var(--text-tertiary)' }}>Tìm trong kho</span>
  </button>;
}

function VaultHome({ items, onOpen }) {
  const favs = items.filter(i=>i.fav);
  return (
    <div style={{ flex:1, minHeight:0, overflowY:'auto', background:'var(--background-grouped)' }}>
      <div style={{ padding:'4px var(--screen-gutter) 0' }}>
        <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', minHeight:44 }}>
          <h1 style={{ margin:0, fontFamily:'var(--font-display)', fontSize:28, fontWeight:700, letterSpacing:'-0.4px', color:'var(--text-primary)' }}>Kho</h1>
          <div style={{ display:'flex', gap:2 }}>
            <IconButton name="add" label="Thêm mục" color="var(--accent)" />
            <IconButton name="profile" label="Tài khoản" color="var(--accent)" />
          </div>
        </div>
        <div style={{ margin:'8px 0 18px' }}><SearchPill /></div>
      </div>

      <div style={{ padding:'0 var(--screen-gutter)', display:'flex', flexDirection:'column', gap:22, paddingBottom:'var(--tabbar-bottom-pad)' }}>
        <section>
          <SectionHeader title="Yêu thích" />
          <Card variant="grouped">
            {favs.map((it,i)=> <Row key={it.id} leading={<Favicon item={it} />} title={it.name} subtitle={it.sub}
              chevron divider={i<favs.length-1} onClick={()=>onOpen(it)} />)}
          </Card>
        </section>
        <section>
          <SectionHeader title={`Tất cả · ${items.length}`} action="Sắp xếp" />
          <Card variant="grouped">
            {items.map((it,i)=> <Row key={it.id} leading={<Favicon item={it} />} title={it.name} subtitle={it.sub}
              trailing={it.alert ? <Badge dot tone="warning" /> : null}
              chevron divider={i<items.length-1} onClick={()=>onOpen(it)} />)}
          </Card>
        </section>
      </div>
    </div>
  );
}
window.VaultHome = VaultHome;

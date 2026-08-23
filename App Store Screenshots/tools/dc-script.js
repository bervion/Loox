class Component extends DCLogic {
  state = { lang: "en" };

  strings() {
    const S = window.LOOX_STRINGS;
    if (!S) return {};
    const loc = S[this.state.lang] || S[S.order[0]] || {};
    const k = loc.titleScale || 1;
    return Object.assign({}, loc, {
      tPhone: Math.round(124 * k) + "px",
      tPad: Math.round(146 * k) + "px",
      lh: loc.lh || 1.08
    });
  }

  buildLangBar() {
    const bar = document.querySelector("[data-langbar]");
    const S = window.LOOX_STRINGS;
    if (!bar || !S) return;
    bar.innerHTML = "";
    S.order.forEach((code) => {
      const b = document.createElement("button");
      b.dataset.lang = code;
      b.textContent = S[code].name || code.toUpperCase();
      b.title = S[code].label || code;
      b.style.cssText = "padding:7px 16px;border-radius:8px;font-size:12.5px;font-weight:600;letter-spacing:0.02em";
      bar.appendChild(b);
    });
    this.paintLangBar();
  }

  paintLangBar() {
    document.querySelectorAll("[data-langbar] [data-lang]").forEach((b) => {
      const on = b.dataset.lang === this.state.lang;
      b.style.background = on ? "#FFFFFF" : "transparent";
      b.style.color = on ? "#0F0F0F" : "#6B6F76";
      b.style.boxShadow = on ? "0 1px 2px rgba(15,15,15,0.14)" : "none";
    });
  }

  componentDidMount() {
    this.buildLangBar();
    this.forceUpdate();
    this.onClick = async (e) => {
      const langBtn = e.target.closest("[data-lang]");
      if (langBtn) {
        this.setState({ lang: langBtn.dataset.lang }, () => this.paintLangBar());
        return;
      }
      const one = e.target.closest("[data-export]");
      if (one) { await this.exportOne(one.dataset.export, one.dataset.name, one); return; }
      const all = e.target.closest("[data-exportall]");
      if (all) { await this.exportAll(all.dataset.exportall, all); }
    };
    document.addEventListener("click", this.onClick);
  }

  componentWillUnmount() { document.removeEventListener("click", this.onClick); }

  // The deck is set in SF Pro — a system font, already present wherever this
  // file is opened — so the export embeds no webfont and makes no network call.
  async render(id) {
    const node = document.querySelector('[data-frame="' + id + '"]');
    if (!node || !window.htmlToImage) return null;
    const w = +node.dataset.w, h = +node.dataset.h;
    return window.htmlToImage.toPng(node, {
      width: w, height: h, pixelRatio: 1, cacheBust: true,
      style: { transform: "none", top: "0", left: "0", position: "relative", margin: "0" }
    });
  }

  download(url, name) {
    const a = document.createElement("a");
    a.href = url; a.download = name + ".png";
    document.body.appendChild(a); a.click(); a.remove();
  }

  async exportOne(id, name, btn) {
    const label = btn ? btn.textContent : null;
    if (btn) { btn.textContent = "…"; btn.disabled = true; }
    try {
      const url = await this.render(id);
      if (url) this.download(url, name + "-" + this.state.lang);
    } catch (err) { console.error(err); }
    if (btn) { btn.textContent = label; btn.disabled = false; }
  }

  async exportAll(kind, btn) {
    const nodes = Array.from(document.querySelectorAll('[data-frame^="' + kind + '-"]'));
    const label = btn ? btn.textContent : null;
    if (btn) btn.disabled = true;
    for (let i = 0; i < nodes.length; i++) {
      if (btn) btn.textContent = "Exporting " + (i + 1) + "/" + nodes.length;
      const id = nodes[i].dataset.frame;
      const b = document.querySelector('[data-export="' + id + '"]');
      try {
        const url = await this.render(id);
        if (url) this.download(url, (b ? b.dataset.name : id) + "-" + this.state.lang);
      } catch (err) { console.error(err); }
      await new Promise((r) => setTimeout(r, 320));
    }
    if (btn) { btn.textContent = label; btn.disabled = false; }
  }

  renderVals() {
    return { t: this.strings(), a: window.LOOX_ASSETS || {} };
  }
}

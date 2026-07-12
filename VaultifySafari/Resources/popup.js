// Popup skeleton: localized static UI, a locked placeholder status, and one
// button that round-trips an echo through background.js to the native handler.
// Vault state wiring replaces the placeholder in a later change.

const t = (key, substitutions) => browser.i18n.getMessage(key, substitutions);

function localizeStaticText() {
  document.querySelectorAll("[data-i18n]").forEach((el) => {
    el.textContent = t(el.dataset.i18n);
  });
  document.title = t("popup_title");
}

function showLockedPlaceholder() {
  // Skeleton always reports locked; real vault status arrives with the
  // unlock bridge.
  document.getElementById("status-label").textContent = t("popup_status_locked");
  document.getElementById("status-dot").classList.add("locked");
}

function wirePingButton() {
  const button = document.getElementById("ping-button");
  const result = document.getElementById("ping-result");

  button.addEventListener("click", async () => {
    button.disabled = true;
    result.textContent = t("popup_ping_waiting");
    try {
      const reply = await browser.runtime.sendMessage({ cmd: "echo", payload: "hello" });
      if (reply && reply.ok === true) {
        result.textContent = t("popup_ping_success", [String(reply.echo ?? "")]);
      } else {
        result.textContent = t("popup_ping_error");
      }
    } catch {
      result.textContent = t("popup_ping_error");
    } finally {
      button.disabled = false;
    }
  });
}

localizeStaticText();
showLockedPlaceholder();
wirePingButton();

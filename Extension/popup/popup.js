// Popup: connection status and quick actions.
const t = (key, subs) => chrome.i18n.getMessage(key, subs) || key;
document.documentElement.lang = chrome.i18n.getUILanguage();
document.documentElement.dir = chrome.i18n.getMessage("@@bidi_dir");
document.querySelectorAll("[data-i18n]").forEach((el) => { el.textContent = t(el.dataset.i18n); });
document.querySelectorAll("[data-i18n-title]").forEach((el) => { el.title = t(el.dataset.i18nTitle); });
const statusEl = document.getElementById("status");
const dot = document.getElementById("dot");
const messageEl = document.getElementById("message");
const portInput = document.getElementById("port");

function send(message) {
  return new Promise((resolve) => {
    chrome.runtime.sendMessage(message, (response) => {
      resolve(chrome.runtime.lastError ? { ok: false, error: chrome.runtime.lastError.message } : response || { ok: false });
    });
  });
}

function show(text, kind = "") {
  messageEl.hidden = !text;
  messageEl.textContent = text || "";
  messageEl.className = `message ${kind}`;
}

async function refresh() {
  const status = await send({ type: "status" });
  if (status.ok) {
    dot.className = "dot on";
    document.getElementById("get").hidden = true;
    const count = Number(status.snips || 0).toLocaleString();
    statusEl.textContent = t("statusConnected", [count, status.semantic ? status.search : t("keywordSearch")]);
  } else {
    dot.className = "dot off";
    statusEl.textContent = status.offline ? t("appNotRunning") : status.error || t("notConnected");
    show(t("openAppHint"), "");
    document.getElementById("get").hidden = false;
  }
}

document.querySelectorAll("[data-action]").forEach((button) => {
  button.addEventListener("click", async () => {
    const action = button.dataset.action;
    button.disabled = true;
    show("");
    const result = await send({ type: action });
    button.disabled = false;
    if (action === "import-bookmarks") {
      window.close();
      return;
    }
    if (result.ok) {
      show(result.updated || result.unchanged ? t("alreadyUpdated") : t("savedToStash"), "ok");
      setTimeout(() => window.close(), 700);
    } else if (result.queued) {
      show(t("savedForLater"), "");
      document.getElementById("get").hidden = false;
    } else {
      show(result.error || t("somethingWrong"), "error");
    }
  });
});

document.getElementById("open").addEventListener("click", async () => {
  await send({ type: "open" });
  window.close();
});

chrome.storage.local.get({ port: 47615 }).then(({ port }) => {
  portInput.value = port;
});
portInput.addEventListener("change", async () => {
  const port = Number(portInput.value);
  if (port >= 1024 && port <= 65535) {
    await chrome.storage.local.set({ port });
    refresh();
  }
});

refresh();

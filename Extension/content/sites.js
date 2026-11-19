// Shared helpers for the Reddit and Pinterest content scripts: messaging, toasts (styled by x.css)
// and a batched sender for imports.
(function () {
  "use strict";
  if (window.__stashUI) return;

  const t = (key, subs) => chrome.i18n.getMessage(key, subs) || key;
  const ICON = `<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="6" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><path d="M20 4 8.12 15.88"/><path d="M14.47 14.48 20 20"/><path d="M8.12 8.12 12 12"/></svg>`;
  const DOWNLOAD_URL = "https://stash.grasco.dev/";
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  function send(message) {
    return new Promise((resolve) => {
      try {
        chrome.runtime.sendMessage(message, (response) => {
          if (chrome.runtime.lastError) resolve({ ok: false, error: chrome.runtime.lastError.message });
          else resolve(response || { ok: false, error: t("noResponse") });
        });
      } catch {
        resolve({ ok: false, error: t("reloadToReconnect") });
      }
    });
  }

  let toastHost = null;
  let toastTimer = null;
  function toast(text, kind = "ok", { sticky = false } = {}) {
    if (!toastHost) {
      toastHost = document.createElement("div");
      toastHost.className = "stash-toast-host";
      document.documentElement.appendChild(toastHost);
    }
    toastHost.innerHTML = "";
    const el = document.createElement("div");
    el.className = `stash-toast stash-toast-${kind} stash-toast-in`;
    const icon = document.createElement("span");
    icon.className = "stash-toast-icon";
    icon.innerHTML = ICON;
    const label = document.createElement("span");
    label.textContent = text;
    el.append(icon, label);
    if (["savedForLater", "cannotReach", "importOffline", "appOffline"].some((k) => t(k) === text)) {
      const b = document.createElement("button");
      b.textContent = t("downloadStash");
      b.addEventListener("click", () => window.open(DOWNLOAD_URL, "_blank", "noopener"));
      el.appendChild(b);
    }
    toastHost.appendChild(el);
    clearTimeout(toastTimer);
    if (sticky) return;
    toastTimer = setTimeout(() => {
      el.classList.remove("stash-toast-in");
      setTimeout(() => el.remove(), 300);
    }, kind === "error" ? 4200 : 2600);
  }

  /** Saves one item and shows the result. */
  async function saveOne(item, source) {
    const result = await send({ type: "save", source, items: [item], queueIfOffline: true });
    if (!result.ok && !result.queued) {
      toast(result.error || t("cannotReach"), "error");
      return false;
    }
    if (result.queued) toast(t("savedForLater"), "warn");
    else if (result.added === 0 && (result.updated || result.unchanged)) toast(t("alreadyUpdated"));
    else toast(t("savedToStash"));
    return true;
  }

  /** Sends items in batches of 40, reports progress to the app and shows a running count. */
  function importer(source) {
    const sent = new Set();
    let added = 0;
    let lastReport = 0;
    return {
      get count() {
        return sent.size;
      },
      get added() {
        return added;
      },
      async push(items) {
        const fresh = items.filter((i) => i && i.url && !sent.has(i.url));
        for (let i = 0; i < fresh.length; i += 40) {
          const batch = fresh.slice(i, i + 40);
          const result = await send({ type: "save", source, items: batch });
          if (!result.ok) throw new Error(result.error || t("cannotReach"));
          batch.forEach((item) => sent.add(item.url));
          added += result.added || 0;
        }
        toast(t("importingCount", [sent.size.toLocaleString()]), "ok", { sticky: true });
        if (Date.now() - lastReport > 2500) {
          lastReport = Date.now();
          send({ type: "progress", source, count: sent.size });
        }
      },
      finish(error) {
        send({ type: "progress", source, done: true, count: sent.size });
        if (error) toast(t("importStopped", [String(error.message || error), sent.size.toLocaleString()]), "error");
        else toast(t("importSavedDone", [sent.size.toLocaleString(), added.toLocaleString()]));
      },
    };
  }

  /** Checks the app is running before an import starts. */
  async function appReady() {
    const status = await send({ type: "status" });
    if (!status.ok) toast(t("importOffline"), "error");
    return status.ok;
  }

  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (message?.type === "toast") {
      toast(message.text, message.kind);
      sendResponse({ ok: true });
    }
  });

  window.__stashUI = { t, ICON, sleep, send, toast, saveOne, importer, appReady };
})();

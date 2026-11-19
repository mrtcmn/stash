// Stash on Reddit: a "Save to Stash" button on posts, and the import of the user's saved items.
// Post data comes from Reddit's own JSON (`<permalink>.json`), fetched same-origin with the user's session.
(function () {
  "use strict";
  if (window.__stashReddit) return;
  window.__stashReddit = true;

  const UI = window.__stashUI;
  const P = globalThis.__stashRedditParse;
  if (!UI || !P) return;
  const { t } = UI;
  const saved = new Set();

  async function getJSON(url) {
    const response = await fetch(url, { credentials: "include", headers: { Accept: "application/json" } });
    if (!response.ok) throw new Error(`Reddit HTTP ${response.status}`);
    return response.json();
  }

  async function itemFor(permalink, fallbackTitle) {
    try {
      const post = P.permalinkPost(await getJSON(P.jsonUrl(permalink, location.origin)));
      const item = P.postItem(post);
      if (item) return item;
    } catch {
      // Fall back to what the page shows.
    }
    const url = new URL(permalink, "https://www.reddit.com").href;
    return fallbackTitle ? { type: "page", url, title: fallbackTitle, text: "", siteName: "Reddit" } : null;
  }

  function makeButton(permalink, title) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "stash-site-btn";
    button.title = t("saveToStash");
    button.setAttribute("aria-label", t("saveToStash"));
    button.innerHTML = `${UI.ICON}<span></span>`;
    button.querySelector("span").textContent = t("saveToStash");
    if (saved.has(permalink)) button.dataset.saved = "true";
    button.addEventListener("click", async (event) => {
      event.preventDefault();
      event.stopPropagation();
      if (button.dataset.busy) return;
      button.dataset.busy = "true";
      try {
        const item = await itemFor(permalink, title);
        if (!item) UI.toast(t("cannotReadPost"), "error");
        else if (await UI.saveOne(item, "extension:reddit")) {
          saved.add(permalink);
          button.dataset.saved = "true";
        }
      } finally {
        delete button.dataset.busy;
      }
    });
    return button;
  }

  // New Reddit: <shreddit-post permalink="/r/…/comments/…/"> with a shadow root; the button goes in a row after it.
  function decorateNew(post) {
    post.dataset.stash = "1";
    const permalink = post.getAttribute("permalink");
    if (!permalink) return;
    const row = document.createElement("div");
    row.className = "stash-reddit-row";
    row.appendChild(makeButton(permalink, post.getAttribute("post-title")));
    post.after(row);
  }

  // Old Reddit: <div class="thing link" data-permalink="…"> with a <ul class="flat-list buttons">.
  function decorateOld(thing) {
    thing.dataset.stash = "1";
    const permalink = thing.getAttribute("data-permalink");
    const list = thing.querySelector(":scope > .entry .flat-list.buttons");
    if (!permalink || !list) return;
    const li = document.createElement("li");
    li.className = "stash-old-reddit";
    li.appendChild(makeButton(permalink, thing.querySelector("a.title")?.textContent?.trim()));
    list.appendChild(li);
  }

  function scan() {
    document.querySelectorAll("shreddit-post:not([data-stash])").forEach(decorateNew);
    document.querySelectorAll(".thing.link[data-permalink]:not([data-stash])").forEach(decorateOld);
  }

  let scheduled = false;
  new MutationObserver(() => {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(() => {
      scheduled = false;
      scan();
    });
  }).observe(document.documentElement, { childList: true, subtree: true });
  scan();

  // ---------------------------------------------------------------------------
  // Import of saved posts and comments

  let importing = false;
  async function importSaved() {
    if (importing) return;
    importing = true;
    try {
      if (!(await UI.appReady())) return;
      const me = await getJSON(`${location.origin}/api/me.json`).catch(() => null);
      const name = me?.data?.name || me?.name;
      if (!name) {
        UI.toast(t("redditLoginFirst"), "error");
        return;
      }
      const run = UI.importer("import:reddit-saved");
      try {
        let after = null;
        do {
          const query = `limit=100&raw_json=1${after ? `&after=${encodeURIComponent(after)}` : ""}`;
          const listing = await getJSON(`${location.origin}/user/${encodeURIComponent(name)}/saved.json?${query}`);
          await run.push(P.listingItems(listing));
          after = listing?.data?.after || null;
          if (after) await UI.sleep(900);
        } while (after);
        run.finish();
      } catch (error) {
        run.finish(error);
      }
    } finally {
      importing = false;
    }
  }

  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (message?.type === "start-reddit-import") {
      importSaved();
      sendResponse({ ok: true });
    }
  });

  if (location.hash === "#stash-import-saved") {
    history.replaceState(null, "", location.pathname + location.search);
    setTimeout(importSaved, 800);
  }
})();

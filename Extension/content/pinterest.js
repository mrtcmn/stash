// Stash on Pinterest: "Save to Stash" on pin pages and on grid pins, and the import of a board.
// Pin data: Pinterest's PinResource JSON (same-origin), then the page's __PWS_DATA__ JSON, then the DOM.
(function () {
  "use strict";
  if (window.__stashPinterest) return;
  window.__stashPinterest = true;

  const UI = window.__stashUI;
  const P = globalThis.__stashPinterestParse;
  if (!UI || !P) return;
  const { t } = UI;
  const saved = new Set();

  // ---------------------------------------------------------------------------
  // Pin data

  let pageJson;
  function initialJson() {
    if (pageJson !== undefined) return pageJson;
    pageJson = [];
    for (const id of ["__PWS_DATA__", "__PWS_INITIAL_PROPS__"]) {
      try {
        const text = document.getElementById(id)?.textContent;
        if (text) pageJson.push(JSON.parse(text));
      } catch {}
    }
    return pageJson;
  }

  let pagePins;
  function initialPins() {
    if (!pagePins) pagePins = P.findPins(initialJson());
    return pagePins;
  }

  async function fetchPin(id) {
    const source = `/pin/${id}/`;
    const data = JSON.stringify({ options: { id, field_set_key: "detailed" }, context: {} });
    const url = `/resource/PinResource/get/?source_url=${encodeURIComponent(source)}&data=${encodeURIComponent(data)}`;
    const response = await fetch(url, {
      credentials: "include",
      headers: { Accept: "application/json", "X-Requested-With": "XMLHttpRequest", "X-Pinterest-Source-Url": source, "X-Pinterest-PWS-Handler": "www/pin/[id].js" },
    });
    if (!response.ok) return null;
    const json = await response.json();
    return json?.resource_response?.data || null;
  }

  const meta = (property) => document.querySelector(`meta[property="${property}"], meta[name="${property}"]`)?.getAttribute("content") || undefined;

  function largestSrc(img) {
    if (!img) return undefined;
    const set = (img.getAttribute("srcset") || "").split(",").map((s) => s.trim().split(/\s+/)[0]).filter(Boolean);
    return set[set.length - 1] || img.currentSrc || img.src;
  }

  /** The pin page from the DOM, for when no JSON matches the current pin (Pinterest navigates without reloads). */
  function pinPageFromDom(id) {
    const ogMatches = (meta("og:url") || "").includes(`/pin/${id}`);
    const closeup = document.querySelector('[data-test-id="closeup-image"] img, [data-test-id="pin-closeup-image"] img, [data-test-id="visual-content-container"] img');
    const title = document.querySelector("main h1, h1")?.textContent?.trim();
    const description = document.querySelector('[data-test-id="truncated-description"], [data-test-id="richPinInformation-description"]')?.textContent?.trim();
    return P.domPinItem({
      id,
      image: largestSrc(closeup) || (ogMatches ? meta("og:image") : undefined),
      title: title || (ogMatches ? meta("og:title") : undefined),
      text: description || closeup?.alt || (ogMatches ? meta("og:description") : undefined),
    });
  }

  function gridCardItem(id, card) {
    const img = card?.querySelector('img[src*="pinimg.com"]');
    return P.domPinItem({ id, image: largestSrc(img), text: img?.alt });
  }

  async function itemFor(id, card) {
    try {
      const fetched = await fetchPin(id);
      const item = fetched && P.pinItem(fetched);
      if (item?.image) return item;
    } catch {}
    const known = initialPins().get(id);
    if (known) return P.pinItem(known);
    return card ? gridCardItem(id, card) : pinPageFromDom(id);
  }

  // ---------------------------------------------------------------------------
  // Buttons

  function makeButton(id, className, { label = false, card = null } = {}) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `stash-site-btn ${className}`;
    button.title = t("saveToStash");
    button.setAttribute("aria-label", t("saveToStash"));
    button.innerHTML = UI.ICON;
    if (label) {
      const span = document.createElement("span");
      span.textContent = t("saveToStash");
      button.appendChild(span);
    }
    button.dataset.pinId = id;
    if (saved.has(id)) button.dataset.saved = "true";
    for (const type of ["pointerdown", "mousedown"]) button.addEventListener(type, (e) => e.stopPropagation());
    button.addEventListener("click", async (event) => {
      event.preventDefault();
      event.stopPropagation();
      if (button.dataset.busy) return;
      button.dataset.busy = "true";
      try {
        const item = await itemFor(button.dataset.pinId, card);
        if (!item?.image) UI.toast(t("cannotReadPost"), "error");
        else if (await UI.saveOne(item, "extension:pinterest")) {
          saved.add(button.dataset.pinId);
          button.dataset.saved = "true";
        }
      } finally {
        delete button.dataset.busy;
      }
    });
    return button;
  }

  // A floating button on pin pages: Pinterest's own toolbar changes too often to anchor to.
  let fab = null;
  function updateFab() {
    const id = P.pinIdFromUrl(location.pathname);
    if (!id) {
      fab?.remove();
      fab = null;
      return;
    }
    if (fab?.dataset.pinId === id) return;
    fab?.remove();
    fab = makeButton(id, "stash-pin-fab", { label: true });
    document.documentElement.appendChild(fab);
  }

  // Grid pins: [data-grid-item] is positioned by the masonry layout, so the button goes in its first child.
  function decorateGrid(root = document) {
    for (const item of root.querySelectorAll("[data-grid-item]:not([data-stash])")) {
      const link = item.querySelector('a[href*="/pin/"]');
      const id = P.pinIdFromUrl(link?.getAttribute("href"));
      const card = item.firstElementChild;
      if (!id || !card) continue;
      item.dataset.stash = id;
      card.classList.add("stash-pin-host");
      if (getComputedStyle(card).position === "static") card.classList.add("stash-pin-host-relative");
      card.appendChild(makeButton(id, "stash-pin-hover", { card }));
    }
  }

  let scheduled = false;
  new MutationObserver(() => {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(() => {
      scheduled = false;
      decorateGrid();
      updateFab();
    });
  }).observe(document.documentElement, { childList: true, subtree: true });
  decorateGrid();
  updateFab();

  // ---------------------------------------------------------------------------
  // Board import: scroll the board and save every pin the grid shows.

  function boardPinCount() {
    const path = location.pathname.replace(/\/?$/, "/");
    let count = 0;
    const seen = new Set();
    const walk = (node) => {
      if (count || !node || typeof node !== "object" || seen.has(node)) return;
      seen.add(node);
      if (node.type === "board" && node.url === decodeURIComponent(path) && Number(node.pin_count) > 0) {
        count = Number(node.pin_count);
        return;
      }
      for (const key in node) if (node[key] && typeof node[key] === "object") walk(node[key]);
    };
    walk(initialJson());
    return count;
  }

  function visibleBoardItems() {
    // Boards end with "More ideas", which are not board pins; stay inside the board feed when it is marked.
    const scope = document.querySelector('[data-test-id="board-feed"], [data-test-id="base-board-pin-grid"]') || document;
    const items = [];
    for (const gridItem of scope.querySelectorAll("[data-grid-item]")) {
      const id = P.pinIdFromUrl(gridItem.querySelector('a[href*="/pin/"]')?.getAttribute("href"));
      if (!id) continue;
      const known = initialPins().get(id);
      const item = known ? P.pinItem(known) : gridCardItem(id, gridItem);
      if (item?.image) items.push(item);
    }
    return items;
  }

  let importing = false;
  async function importBoard() {
    if (importing) return;
    importing = true;
    const run = UI.importer("import:pinterest-board");
    try {
      if (!(await UI.appReady())) return;
      const limit = boardPinCount();
      let idleRounds = 0;
      let lastCount = -1;
      window.scrollTo({ top: 0 });
      await UI.sleep(900);
      while (true) {
        await run.push(visibleBoardItems());
        idleRounds = run.count === lastCount ? idleRounds + 1 : 0;
        lastCount = run.count;
        if (limit && run.count >= limit) break;
        const atBottom = window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 300;
        if (idleRounds >= (atBottom ? 6 : 14)) break;
        window.scrollBy({ top: Math.round(window.innerHeight * 0.85), behavior: "instant" });
        await UI.sleep(700 + Math.random() * 400);
      }
      run.finish();
    } catch (error) {
      run.finish(error);
    } finally {
      importing = false;
    }
  }

  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (message?.type === "start-board-import") {
      if (!P.isBoardPath(location.pathname)) {
        sendResponse({ ok: false, error: t("openPinterestBoard") });
        return;
      }
      importBoard();
      sendResponse({ ok: true });
    }
  });
})();

// Turns Pinterest pin data into Stash "page" items. Accepts the REST shape (PinResource,
// __PWS_DATA__ redux state: `images.orig`, `pinner.full_name`) and the Relay shape
// (`imageSpec_orig`, `pinner.fullName`). Runs in the Pinterest content script and in Node tests.
(function (root) {
  "use strict";

  const FAVICON = "https://www.pinterest.com/favicon.ico";

  const str = (v) => (typeof v === "string" && v.trim() ? v.trim() : undefined);
  const pick = (obj, ...keys) => {
    for (const k of keys) {
      const v = obj?.[k];
      if (v != null && v !== "") return v;
    }
    return undefined;
  };

  function truncate(text, max = 280) {
    const s = String(text || "").replace(/\s+/g, " ").trim();
    if (!s) return undefined;
    return s.length > max ? `${s.slice(0, max - 1).trimEnd()}…` : s;
  }

  /** A pinimg.com thumbnail URL → the 736px wide version. */
  function upgradeImage(src) {
    if (!src) return undefined;
    try {
      const url = new URL(src);
      if (!/(^|\.)pinimg\.com$/.test(url.hostname)) return src;
      url.pathname = url.pathname.replace(/^\/(\d+x\d*|\d+x|originals)\//, "/736x/");
      return url.href;
    } catch {
      return src;
    }
  }

  function largestImage(pin) {
    const images = pin.images || {};
    const spec = pin.imageSpec_orig || pin.imageSpec_736x || pin.imageLargeUrl;
    const orig = images.orig || images.originals || images["736x"] || (typeof spec === "object" ? spec : undefined);
    if (orig?.url) return { url: orig.url, width: orig.width, height: orig.height };
    const flat = str(pin.image_large_url) || str(pin.imageLargeUrl) || str(pin.image_medium_url) || str(pin.imageMediumUrl);
    return flat ? { url: upgradeImage(flat) } : undefined;
  }

  /** The widest MP4 in `videos.video_list` (REST) or `videos.videoList` (Relay); HLS is skipped. */
  function bestMp4(pin) {
    const lists = [pin.videos?.video_list, pin.videos?.videoList, pin.story_pin_data?.pages?.[0]?.blocks?.[0]?.video?.video_list];
    const found = [];
    for (const list of lists) {
      if (!list || typeof list !== "object") continue;
      for (const v of Object.values(list)) {
        if (v && typeof v.url === "string" && /\.mp4(\?|$)/i.test(v.url)) found.push(v);
      }
    }
    found.sort((a, b) => (b.width || 0) - (a.width || 0));
    return found[0];
  }

  function pinner(pin) {
    const p = pin.pinner || pin.native_creator || pin.nativeCreator || pin.origin_pinner || pin.originPinner;
    if (!p) return undefined;
    const handle = str(p.username);
    const name = str(p.full_name) || str(p.fullName) || handle;
    if (!name) return undefined;
    return { name, handle, avatar: str(p.image_medium_url) || str(p.imageMediumUrl) || undefined };
  }

  function pinId(pin) {
    const id = pin?.entityId ?? pin?.id;
    return id != null && /^\d+$/.test(String(id)) ? String(id) : undefined;
  }

  function looksLikePin(obj) {
    return Boolean(obj && typeof obj === "object" && pinId(obj) && (obj.images || obj.imageSpec_orig || obj.imageSpec_736x));
  }

  /** One pin object → a Stash page item. */
  function pinItem(pin) {
    const id = pinId(pin);
    if (!id) return null;
    const image = largestImage(pin);
    const body = str(pick(pin, "description", "closeup_unified_description", "closeupUnifiedDescription", "closeup_description", "closeupDescription"));
    const alt = str(pick(pin, "auto_alt_text", "autoAltText", "alt_text", "altText"));
    const title = str(pick(pin, "title", "grid_title", "gridTitle", "seo_title", "seoTitle")) || truncate(body || alt, 90);
    const link = str(pick(pin, "link", "tracked_link"));
    const text = [body || alt, link && !/pinterest\./.test(link) ? link : ""].filter(Boolean).join("\n\n");
    const video = bestMp4(pin);
    const media = [];
    if (video) media.push({ type: "video", url: image?.url, width: video.width, height: video.height, alt, videoUrl: video.url });
    else if (image) media.push({ type: "photo", url: image.url, width: image.width, height: image.height, alt });
    const board = str(pin.board?.name);
    return {
      type: "page",
      url: `https://www.pinterest.com/pin/${id}/`,
      title,
      text,
      description: truncate(body),
      siteName: "Pinterest",
      image: image?.url,
      favicon: FAVICON,
      tags: board ? [board.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, "-").replace(/^-|-$/g, "")].filter(Boolean) : undefined,
      author: pinner(pin),
      media: media.length ? media : undefined,
    };
  }

  /** Every pin-like object anywhere in a JSON tree (first one wins per id). */
  function findPins(json) {
    const found = new Map();
    const seen = new Set();
    const walk = (node) => {
      if (!node || typeof node !== "object" || seen.has(node)) return;
      seen.add(node);
      if (!Array.isArray(node) && looksLikePin(node)) {
        const id = pinId(node);
        const known = found.get(id);
        // Keep the richest copy: Pinterest repeats pins with fewer fields in lists.
        if (!known || Object.keys(node).length > Object.keys(known).length) found.set(id, node);
      }
      for (const key in node) {
        const value = node[key];
        if (value && typeof value === "object") walk(value);
      }
    };
    walk(json);
    return found;
  }

  /** A page-level fallback from the DOM or `og:` meta tags. */
  function domPinItem({ id, image, title, text, author } = {}) {
    if (!id) return null;
    const img = upgradeImage(image);
    return {
      type: "page",
      url: `https://www.pinterest.com/pin/${id}/`,
      title: str(title) || truncate(text, 90),
      text: str(text) || "",
      description: truncate(text),
      siteName: "Pinterest",
      image: img,
      favicon: FAVICON,
      author: author?.name ? author : undefined,
      media: img ? [{ type: "photo", url: img, alt: str(text) }] : undefined,
    };
  }

  /** The pin id in a URL or path such as "/pin/123/" or "https://www.pinterest.com/pin/123/". */
  function pinIdFromUrl(href) {
    const match = /\/pin\/(\d+)/.exec(String(href || ""));
    return match ? match[1] : null;
  }

  const RESERVED = new Set(["pin", "search", "ideas", "today", "settings", "_", "business", "news_hub", "categories", "explore", "videos", "resource", "login", "signup", "password", "notifications", "inbox", "homefeed"]);

  /** True for a board path such as "/name/board/" or "/name/board/section/". */
  function isBoardPath(pathname) {
    const parts = String(pathname || "").split("/").filter(Boolean);
    if (parts.length < 2 || parts.length > 3) return false;
    if (RESERVED.has(parts[0]) || parts[0].startsWith("_")) return false;
    return !parts[1].startsWith("_") && !["pins", "boards", "followers", "following"].includes(parts[1]);
  }

  const api = { pinItem, findPins, domPinItem, upgradeImage, pinIdFromUrl, isBoardPath };
  root.__stashPinterestParse = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
})(typeof globalThis !== "undefined" ? globalThis : this);

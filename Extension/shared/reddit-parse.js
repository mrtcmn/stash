// Turns Reddit's JSON (`<permalink>.json`, `/user/<name>/saved.json`) into Stash "page" items.
// Runs in the Reddit content script and in Node tests.
(function (root) {
  "use strict";

  const ORIGIN = "https://www.reddit.com";
  const FAVICON = "https://www.reddit.com/favicon.ico";

  function decode(text) {
    if (text == null) return undefined;
    return String(text)
      .replace(/&lt;/g, "<")
      .replace(/&gt;/g, ">")
      .replace(/&quot;/g, '"')
      .replace(/&#39;|&#x27;/g, "'")
      .replace(/&amp;/g, "&");
  }

  const isHttp = (u) => typeof u === "string" && /^https?:\/\//.test(u);

  function truncate(text, max = 280) {
    const s = String(text || "").replace(/\s+/g, " ").trim();
    if (!s) return undefined;
    return s.length > max ? `${s.slice(0, max - 1).trimEnd()}…` : s;
  }

  function author(name) {
    if (!name || name === "[deleted]") return undefined;
    return { name, handle: name };
  }

  function tags(subreddit) {
    return subreddit ? [`r-${String(subreddit).toLowerCase()}`] : undefined;
  }

  function absolute(permalink) {
    if (!permalink) return undefined;
    return isHttp(permalink) ? permalink : ORIGIN + permalink;
  }

  function galleryMedia(post) {
    const items = post.gallery_data?.items;
    const meta = post.media_metadata;
    if (!Array.isArray(items) || !meta) return [];
    const out = [];
    for (const item of items) {
      const m = meta[item.media_id];
      if (!m || m.status !== "valid" || !m.s) continue;
      const alt = item.caption || undefined;
      if (m.e === "AnimatedImage") {
        const still = m.s.gif || m.p?.[m.p.length - 1]?.u;
        out.push({ type: "animated_gif", url: decode(still), width: m.s.x, height: m.s.y, alt, videoUrl: decode(m.s.mp4) });
      } else if (m.s.u) {
        out.push({ type: "photo", url: decode(m.s.u), width: m.s.x, height: m.s.y, alt });
      }
    }
    return out;
  }

  function previewSource(post) {
    const source = post.preview?.images?.[0]?.source;
    return source?.url ? { url: decode(source.url), width: source.width, height: source.height } : undefined;
  }

  function media(post) {
    if (post.is_gallery) return galleryMedia(post);
    const preview = previewSource(post);
    const video = post.secure_media?.reddit_video || post.media?.reddit_video;
    if (video?.fallback_url) {
      return [{ type: "video", url: preview?.url, width: video.width, height: video.height, videoUrl: decode(video.fallback_url) }];
    }
    const gifVideo = post.preview?.reddit_video_preview;
    if (gifVideo?.fallback_url) {
      return [{ type: "animated_gif", url: preview?.url, width: gifVideo.width, height: gifVideo.height, videoUrl: decode(gifVideo.fallback_url) }];
    }
    const link = decode(post.url_overridden_by_dest || post.url);
    if (post.post_hint === "image" || /^https:\/\/i\.redd\.it\//.test(link || "") || /\.(jpe?g|png|webp|gif)(\?|$)/i.test(link || "")) {
      const mp4 = post.preview?.images?.[0]?.variants?.mp4?.source?.url;
      if (/\.gif(\?|$)/i.test(link) && mp4) {
        return [{ type: "animated_gif", url: link, width: preview?.width, height: preview?.height, videoUrl: decode(mp4) }];
      }
      return [{ type: "photo", url: link, width: preview?.width, height: preview?.height }];
    }
    return [];
  }

  /** One Reddit post (`kind: "t3"` data) → a Stash page item. Crossposts use the original's media. */
  function postItem(post) {
    if (!post || !post.permalink) return null;
    const original = post.crosspost_parent_list?.[0];
    const list = media(post);
    const mediaList = list.length || !original ? list : media(original);
    const body = decode(post.selftext || original?.selftext || "").trim();
    const link = decode(post.url_overridden_by_dest || post.url);
    const external = !post.is_self && isHttp(link) && !/^https:\/\/(www\.|old\.|i\.|v\.)?redd\.?it/.test(link) && !/reddit\.com\//.test(link);
    const text = [body, external ? link : ""].filter(Boolean).join("\n\n");
    const preview = previewSource(post) || (original && previewSource(original));
    return {
      type: "page",
      url: absolute(post.permalink),
      title: decode(post.title),
      text,
      description: truncate(body) || (external ? link : undefined),
      siteName: "Reddit",
      image: mediaList[0]?.url || preview?.url || (isHttp(post.thumbnail) ? decode(post.thumbnail) : undefined),
      favicon: FAVICON,
      tags: tags(post.subreddit),
      author: author(post.author),
      media: mediaList.length ? mediaList : undefined,
    };
  }

  /** One saved comment (`kind: "t1"` data) → a Stash page item. */
  function commentItem(comment) {
    if (!comment || !comment.permalink) return null;
    const body = decode(comment.body || "").trim();
    return {
      type: "page",
      url: absolute(comment.permalink),
      title: `Comment on: ${decode(comment.link_title) || "Reddit"}`,
      text: body,
      description: truncate(body),
      siteName: "Reddit",
      favicon: FAVICON,
      tags: tags(comment.subreddit),
      author: author(comment.author),
    };
  }

  /** Every post and comment in a Listing (`{kind: "Listing", data: {children, after}}`). */
  function listingItems(listing) {
    const children = listing?.data?.children || [];
    const out = [];
    for (const child of children) {
      const item = child?.kind === "t3" ? postItem(child.data) : child?.kind === "t1" ? commentItem(child.data) : null;
      if (item) out.push(item);
    }
    return out;
  }

  /** The post in a `<permalink>.json` response: `[postListing, commentsListing]`. */
  function permalinkPost(json) {
    const listing = Array.isArray(json) ? json[0] : json;
    const child = listing?.data?.children?.find((c) => c?.kind === "t3");
    return child ? child.data : null;
  }

  /** The JSON address of a post permalink, e.g. "/r/a/comments/x/y/" → "https://www.reddit.com/r/a/comments/x/y.json?raw_json=1". */
  function jsonUrl(permalink, origin = ORIGIN) {
    const url = new URL(permalink, origin);
    url.pathname = url.pathname.replace(/\/+$/, "") + ".json";
    url.search = "?raw_json=1";
    url.hash = "";
    return url.href;
  }

  const api = { postItem, commentItem, listingItems, permalinkPost, jsonUrl, decode };
  root.__stashRedditParse = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
})(typeof globalThis !== "undefined" ? globalThis : this);

// Run with: node --test "Extension/tests/*.test.mjs"
import { test } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const reddit = require("../shared/reddit-parse.js");

const selfPost = {
  id: "abc123",
  name: "t3_abc123",
  subreddit: "Programming",
  author: "glasslab",
  title: "Why I write &amp; ship boring code",
  selftext: "Boring code is **easy** to read.\n\nThat is the point.",
  is_self: true,
  permalink: "/r/programming/comments/abc123/why_i_write_ship_boring_code/",
  url: "https://www.reddit.com/r/programming/comments/abc123/why_i_write_ship_boring_code/",
  thumbnail: "self",
};

const linkPost = {
  subreddit: "macapps",
  author: "maker",
  title: "A new app",
  selftext: "",
  is_self: false,
  permalink: "/r/macapps/comments/l1/a_new_app/",
  url_overridden_by_dest: "https://example.com/app",
  thumbnail: "https://b.thumbs.redditmedia.com/t.jpg",
  preview: { images: [{ source: { url: "https://external-preview.redd.it/p.jpg?a=1&amp;b=2", width: 1200, height: 630 } }] },
};

const galleryPost = {
  subreddit: "EarthPorn",
  author: "hiker",
  title: "Two views",
  is_self: false,
  is_gallery: true,
  permalink: "/r/EarthPorn/comments/g1/two_views/",
  url: "https://www.reddit.com/gallery/g1",
  gallery_data: { items: [{ media_id: "m1", caption: "Morning" }, { media_id: "m2" }, { media_id: "bad" }] },
  media_metadata: {
    m1: { status: "valid", e: "Image", s: { u: "https://preview.redd.it/m1.jpg?width=4000&amp;s=x", x: 4000, y: 3000 } },
    m2: { status: "valid", e: "AnimatedImage", s: { gif: "https://i.redd.it/m2.gif", mp4: "https://preview.redd.it/m2.gif?format=mp4", x: 480, y: 270 } },
    bad: { status: "failed" },
  },
};

const videoPost = {
  subreddit: "videos",
  author: "[deleted]",
  title: "Clip",
  is_self: false,
  is_video: true,
  permalink: "/r/videos/comments/v1/clip/",
  url: "https://v.redd.it/v1",
  secure_media: { reddit_video: { fallback_url: "https://v.redd.it/v1/DASH_720.mp4?source=fallback", width: 1280, height: 720 } },
  preview: { images: [{ source: { url: "https://external-preview.redd.it/v1.png", width: 1280, height: 720 } }] },
};

const imagePost = {
  subreddit: "pics",
  author: "snap",
  title: "Cat",
  is_self: false,
  post_hint: "image",
  permalink: "/r/pics/comments/i1/cat/",
  url_overridden_by_dest: "https://i.redd.it/cat.jpg",
  preview: { images: [{ source: { url: "https://preview.redd.it/cat.jpg", width: 800, height: 600 } }] },
};

test("a text post becomes a page item with author, tag and body", () => {
  const item = reddit.postItem(selfPost);
  assert.deepEqual(item, {
    type: "page",
    url: "https://www.reddit.com/r/programming/comments/abc123/why_i_write_ship_boring_code/",
    title: "Why I write & ship boring code",
    text: "Boring code is **easy** to read.\n\nThat is the point.",
    description: "Boring code is **easy** to read. That is the point.",
    siteName: "Reddit",
    image: undefined,
    favicon: "https://www.reddit.com/favicon.ico",
    tags: ["r-programming"],
    author: { name: "glasslab", handle: "glasslab" },
    media: undefined,
  });
});

test("a link post keeps the external link and the preview image", () => {
  const item = reddit.postItem(linkPost);
  assert.equal(item.text, "https://example.com/app");
  assert.equal(item.description, "https://example.com/app");
  assert.equal(item.image, "https://external-preview.redd.it/p.jpg?a=1&b=2");
  assert.equal(item.media, undefined);
});

test("a gallery becomes several media items and skips failed ones", () => {
  const item = reddit.postItem(galleryPost);
  assert.deepEqual(item.media, [
    { type: "photo", url: "https://preview.redd.it/m1.jpg?width=4000&s=x", width: 4000, height: 3000, alt: "Morning" },
    { type: "animated_gif", url: "https://i.redd.it/m2.gif", width: 480, height: 270, alt: undefined, videoUrl: "https://preview.redd.it/m2.gif?format=mp4" },
  ]);
  assert.equal(item.image, "https://preview.redd.it/m1.jpg?width=4000&s=x");
  assert.equal(item.text, "");
});

test("a hosted video uses the poster as url and the fallback MP4 as videoUrl", () => {
  const item = reddit.postItem(videoPost);
  assert.deepEqual(item.media, [
    { type: "video", url: "https://external-preview.redd.it/v1.png", width: 1280, height: 720, videoUrl: "https://v.redd.it/v1/DASH_720.mp4?source=fallback" },
  ]);
  assert.equal(item.author, undefined, "deleted authors are dropped");
  assert.equal(item.text, "", "v.redd.it is not an external link");
});

test("an image post becomes one photo", () => {
  const item = reddit.postItem(imagePost);
  assert.deepEqual(item.media, [{ type: "photo", url: "https://i.redd.it/cat.jpg", width: 800, height: 600 }]);
});

test("a crosspost without its own media uses the original's", () => {
  const item = reddit.postItem({ ...selfPost, selftext: "", is_self: false, url: "/r/x/comments/abc123/", crosspost_parent_list: [videoPost] });
  assert.equal(item.media[0].type, "video");
});

test("a saved listing maps posts and comments and keeps the order", () => {
  const listing = {
    kind: "Listing",
    data: {
      after: "t1_c9",
      children: [
        { kind: "t3", data: selfPost },
        {
          kind: "t1",
          data: {
            author: "commenter",
            body: "Great point.",
            subreddit: "programming",
            link_title: "Why boring code wins",
            permalink: "/r/programming/comments/abc123/why/c9/",
          },
        },
        { kind: "more", data: {} },
      ],
    },
  };
  const items = reddit.listingItems(listing);
  assert.equal(items.length, 2);
  assert.deepEqual(items[1], {
    type: "page",
    url: "https://www.reddit.com/r/programming/comments/abc123/why/c9/",
    title: "Comment on: Why boring code wins",
    text: "Great point.",
    description: "Great point.",
    siteName: "Reddit",
    favicon: "https://www.reddit.com/favicon.ico",
    tags: ["r-programming"],
    author: { name: "commenter", handle: "commenter" },
  });
});

test("permalinkPost reads the first listing of a post page response", () => {
  const json = [{ kind: "Listing", data: { children: [{ kind: "t3", data: selfPost }] } }, { kind: "Listing", data: { children: [] } }];
  assert.equal(reddit.permalinkPost(json), selfPost);
  assert.equal(reddit.permalinkPost([]), null);
});

test("jsonUrl builds the JSON address on the current host", () => {
  assert.equal(reddit.jsonUrl("/r/a/comments/x/y/"), "https://www.reddit.com/r/a/comments/x/y.json?raw_json=1");
  assert.equal(reddit.jsonUrl("/r/a/comments/x/y/?utm=1#c", "https://old.reddit.com"), "https://old.reddit.com/r/a/comments/x/y.json?raw_json=1");
});

// Run with: node --test "Extension/tests/*.test.mjs"
import { test } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const pinterest = require("../shared/pinterest-parse.js");

// REST shape, as PinResource and __PWS_DATA__ return it.
const restPin = {
  id: "123456789",
  type: "pin",
  title: "",
  grid_title: "Glass shelf",
  description: "A floating shelf made of glass.",
  auto_alt_text: "a glass shelf on a white wall",
  link: "https://example.com/shelf",
  images: {
    "236x": { url: "https://i.pinimg.com/236x/aa/bb/cc/x.jpg", width: 236, height: 300 },
    orig: { url: "https://i.pinimg.com/originals/aa/bb/cc/x.jpg", width: 1200, height: 1500 },
  },
  pinner: { full_name: "Ana Lima", username: "analima", image_medium_url: "https://i.pinimg.com/75x75_RS/a.jpg" },
  board: { name: "Home Ideas" },
};

// Relay shape, as the newer web app keeps it.
const relayVideoPin = {
  entityId: "987654321",
  gridTitle: "Pottery",
  closeupUnifiedDescription: "Throwing a bowl.",
  imageSpec_orig: { url: "https://i.pinimg.com/originals/dd/ee/ff/v.jpg", width: 720, height: 1280 },
  pinner: { fullName: "Clay Studio", username: "claystudio" },
  videos: {
    videoList: {
      vHLSV4: { url: "https://v1.pinimg.com/videos/hls/v.m3u8", width: 720 },
      v720P: { url: "https://v1.pinimg.com/videos/720p/v.mp4", width: 720, height: 1280 },
      v480P: { url: "https://v1.pinimg.com/videos/480p/v.mp4", width: 480, height: 854 },
    },
  },
};

test("a REST pin becomes a page item with the original image", () => {
  assert.deepEqual(pinterest.pinItem(restPin), {
    type: "page",
    url: "https://www.pinterest.com/pin/123456789/",
    title: "Glass shelf",
    text: "A floating shelf made of glass.\n\nhttps://example.com/shelf",
    description: "A floating shelf made of glass.",
    siteName: "Pinterest",
    image: "https://i.pinimg.com/originals/aa/bb/cc/x.jpg",
    favicon: "https://www.pinterest.com/favicon.ico",
    tags: ["home-ideas"],
    author: { name: "Ana Lima", handle: "analima", avatar: "https://i.pinimg.com/75x75_RS/a.jpg" },
    media: [{ type: "photo", url: "https://i.pinimg.com/originals/aa/bb/cc/x.jpg", width: 1200, height: 1500, alt: "a glass shelf on a white wall" }],
  });
});

test("a Relay video pin uses the widest MP4 and skips HLS", () => {
  const item = pinterest.pinItem(relayVideoPin);
  assert.equal(item.url, "https://www.pinterest.com/pin/987654321/");
  assert.equal(item.title, "Pottery");
  assert.equal(item.text, "Throwing a bowl.");
  assert.deepEqual(item.author, { name: "Clay Studio", handle: "claystudio", avatar: undefined });
  assert.deepEqual(item.media, [
    { type: "video", url: "https://i.pinimg.com/originals/dd/ee/ff/v.jpg", width: 720, height: 1280, alt: undefined, videoUrl: "https://v1.pinimg.com/videos/720p/v.mp4" },
  ]);
});

test("a pin without a title uses its description", () => {
  const item = pinterest.pinItem({ id: "1", description: "Only words here", images: { "736x": { url: "https://i.pinimg.com/736x/a.jpg" } } });
  assert.equal(item.title, "Only words here");
  assert.equal(item.image, "https://i.pinimg.com/736x/a.jpg");
});

test("findPins finds pins anywhere in page JSON and keeps the richest copy", () => {
  const json = {
    props: {
      initialReduxState: { pins: { 123456789: restPin } },
      feed: [{ id: "123456789", images: { "236x": restPin.images["236x"] } }, relayVideoPin, { id: "notapin", images: {} }, { id: "55", title: "no images" }],
    },
  };
  const pins = pinterest.findPins(json);
  assert.deepEqual([...pins.keys()].sort(), ["123456789", "987654321"]);
  assert.equal(pins.get("123456789"), restPin);
});

test("domPinItem builds a fallback item with the 736x image", () => {
  assert.deepEqual(pinterest.domPinItem({ id: "42", image: "https://i.pinimg.com/236x/aa/x.jpg", text: "Blue tiles" }), {
    type: "page",
    url: "https://www.pinterest.com/pin/42/",
    title: "Blue tiles",
    text: "Blue tiles",
    description: "Blue tiles",
    siteName: "Pinterest",
    image: "https://i.pinimg.com/736x/aa/x.jpg",
    favicon: "https://www.pinterest.com/favicon.ico",
    author: undefined,
    media: [{ type: "photo", url: "https://i.pinimg.com/736x/aa/x.jpg", alt: "Blue tiles" }],
  });
  assert.equal(pinterest.domPinItem({}), null);
});

test("upgradeImage only rewrites pinimg.com sizes", () => {
  assert.equal(pinterest.upgradeImage("https://i.pinimg.com/60x60/a/b.jpg"), "https://i.pinimg.com/736x/a/b.jpg");
  assert.equal(pinterest.upgradeImage("https://i.pinimg.com/474x/a/b.jpg"), "https://i.pinimg.com/736x/a/b.jpg");
  assert.equal(pinterest.upgradeImage("https://example.com/236x/a.jpg"), "https://example.com/236x/a.jpg");
});

test("pinIdFromUrl and isBoardPath read Pinterest paths", () => {
  assert.equal(pinterest.pinIdFromUrl("/pin/123/"), "123");
  assert.equal(pinterest.pinIdFromUrl("https://www.pinterest.com/pin/456/?nic=1"), "456");
  assert.equal(pinterest.pinIdFromUrl("/analima/home-ideas/"), null);
  assert.equal(pinterest.isBoardPath("/analima/home-ideas/"), true);
  assert.equal(pinterest.isBoardPath("/analima/home-ideas/kitchen/"), true);
  assert.equal(pinterest.isBoardPath("/analima/"), false);
  assert.equal(pinterest.isBoardPath("/analima/_saved/"), false);
  assert.equal(pinterest.isBoardPath("/pin/123/"), false);
  assert.equal(pinterest.isBoardPath("/search/pins/"), false);
  assert.equal(pinterest.isBoardPath("/ideas/home/"), false);
});

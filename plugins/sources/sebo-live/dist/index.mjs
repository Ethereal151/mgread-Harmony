import { createRequire as __mgreadCreateRequire } from 'node:module'; const require = __mgreadCreateRequire(import.meta.url);

// dist/index.mjs
import { createHash } from "node:crypto";
var base = "http://api.hclyz.com:81/mf/";
var videoHeaders = Object.freeze({ Referer: base, "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/126.0.0.0 Safari/537.36" });
var context;
var platformsCache;
var channelCache = /* @__PURE__ */ new Map();
async function activate(next) {
  context = next;
  platformsCache = void 0;
  channelCache.clear();
  next.log.info("source_activated");
}
async function search(request) {
  if (request.cursor !== null)
    throw new Error("Search cursor is unsupported.");
  const query = request.query.trim().toLocaleLowerCase("zh-CN");
  if (query === "")
    return frozen({ items: [], nextCursor: null, totalCount: 0 });
  const values = (await loadPlatforms()).filter((item) => item.title.toLocaleLowerCase("zh-CN").includes(query)).slice(0, clamp(request.pageSize)).map(summary);
  return frozen({ items: values, nextCursor: null, totalCount: values.length });
}
async function searchSuggestions(_request) {
  return frozen({ items: [], nextCursor: null });
}
async function discover(request) {
  if (request.target === null) {
    if (request.cursor !== null || request.collectionId !== null)
      throw new Error("Initial discovery request is invalid.");
    return frozen({ kind: "document", document: { components: [{ type: "section", id: "live-platform-entry", title: "直播平台", subtitle: "浏览全部平台", icon: "video", children: [{ type: "categoryCollection", id: "live-platform-categories", layout: "chips", categories: [{ id: "all", title: "全部平台", target: "category:all", count: null, url: null, icon: "video" }] }] }] } });
  }
  if (request.target !== "category:all")
    throw new Error("Discovery target is invalid.");
  const page = cursorPage(request.cursor, request.target);
  const limit = clamp(request.pageSize);
  const platforms = await loadPlatforms();
  const start = (page - 1) * limit;
  const values = platforms.slice(start, start + limit);
  const collectionId = "live:platforms";
  const items = values.map((value) => frozen({ content: summary(value), rank: null, metric: null, recommendation: null }));
  const continuation = start + values.length < platforms.length ? frozen({ target: request.target, cursor: `${request.target}:${page + 1}` }) : null;
  if (request.collectionId !== null) {
    if (request.collectionId !== collectionId)
      throw new Error("Discovery collection is invalid.");
    return frozen({ kind: "append", collectionId, items, continuation });
  }
  return frozen({ kind: "document", document: { components: [{ type: "section", id: "live-platforms-section", title: "全部平台", subtitle: null, icon: "video", children: [{ type: "contentCollection", id: collectionId, layout: "coverGrid", items, continuation }] }] } });
}
async function getDetail(request) {
  const address = contentId(request.id);
  const platform = (await loadPlatforms()).find((item2) => item2.address === address) ?? { title: address, address, image: "", count: 0 };
  const channels = await loadChannels(address);
  const item = summary({ ...platform, count: channels.length });
  return frozen({ ...item, description: `${platform.title}，共 ${channels.length} 个直播频道。`, aliases: [], catalogUrl: joinUrl(address) });
}
async function getChapters(request) {
  const address = contentId(request.id);
  const channels = await loadChannels(address);
  const items = channels.map((channel, index) => chapter(address, channel, index));
  return frozen({ items, groups: items.length === 0 ? [] : [frozen({ id: `group:${encodeKey(address)}:live`, title: "直播频道", order: 0, episodes: items })] });
}
async function getContent(request) {
  const address = contentId(request.id);
  const key = chapterKey(request.chapterId, address);
  const channels = await loadChannels(address, true);
  const channel = channels.find((value) => channelKey(value) === key);
  if (channel === void 0 || !safeUrl(channel.address))
    throw new Error("Chapter ID is invalid.");
  const resourceType = /\.m3u8(?:$|[?#])/iu.test(channel.address) ? "hls" : "video";
  return frozen({ chapterId: request.chapterId, contentKind: "video", title: channel.title, updatedAt: null, text: null, pages: [], media: { url: requireContext().resource.proxy({ kind: resourceType, url: channel.address, headers: videoHeaders }), resourceType, resourcePolicy: "sessionOnly", expiresAt: null, mimeType: mediaMimeType(channel.address, resourceType), headers: videoHeaders } });
}
async function loadPlatforms() {
  if (platformsCache !== void 0)
    return platformsCache;
  const json = await fetchJson(joinUrl("json.txt"));
  const values = [];
  for (const item of records(json.pingtai)) {
    const title = decoded(item.title);
    const address = text(item.address);
    if (title === "" || address === "" || number(item.Number) <= 0)
      continue;
    values.push({ title, address, image: text(item.xinimg), count: number(item.Number) });
  }
  platformsCache = Object.freeze(values);
  return platformsCache;
}
async function loadChannels(address, refresh = false) {
  const cached = channelCache.get(address);
  if (!refresh && cached !== void 0)
    return cached;
  try {
    const json = await fetchJson(joinUrl(address));
    const values = [];
    for (const item of records(json.zhubo)) {
      const title = decoded(item.title);
      const stream = text(item.address);
      if (title !== "" && safeUrl(stream))
        values.push({ title, address: stream, image: text(item.img) });
    }
    const result = Object.freeze(values);
    channelCache.set(address, result);
    return result;
  } catch (error) {
    if (cached !== void 0)
      return cached;
    throw error;
  }
}
async function fetchJson(url) {
  const response = await requireContext().http.fetch(url, { headers: { Accept: "application/json,text/plain,*/*" } });
  if (!response.ok)
    throw new Error("Source request failed.");
  const value = await response.json();
  if (!isObject(value))
    throw new Error("Source response is invalid.");
  return value;
}
function summary(item) {
  const id = encodeKey(item.address);
  return frozen({ id: `live:${id}`, title: item.title, contentKind: "video", coverOrientation: "landscape", author: "Live", url: joinUrl(item.address), coverUrl: proxyImage(item.image), description: `${item.count} 个直播频道`, language: null, status: "ongoing", access: "free", wordCount: null, chapterCount: item.count || null, publishedAt: null, updatedAt: null, latestChapter: { id: null, title: `${item.count} 个频道`, url: null, updatedAt: null }, categories: ["直播"], tags: [], attributes: [] });
}
function chapter(address, channel, index) {
  return frozen({ id: `live:${encodeKey(address)}:${channelKey(channel)}`, title: channel.title, order: index, url: null, volumeTitle: "直播频道", wordCount: null, updatedAt: null, isLocked: null, attributes: [] });
}
function joinUrl(path) {
  return new URL(path.replace(/^\/+/, ""), base).toString();
}
function channelKey(channel) {
  return createHash("sha256").update(`${channel.title}
${stableStreamIdentity(channel.address)}`).digest("hex").slice(0, 24);
}
function stableStreamIdentity(value) {
  const url = new URL(value);
  const volatile = /* @__PURE__ */ new Set(["auth_key", "authkey", "expire", "expires", "livekey", "sign", "signature", "token", "ts"]);
  for (const key of [...url.searchParams.keys()])
    if (volatile.has(key.toLowerCase()))
      url.searchParams.delete(key);
  url.searchParams.sort();
  url.hash = "";
  return url.toString();
}
function mediaMimeType(value, resourceType) {
  if (resourceType === "hls")
    return "application/vnd.apple.mpegurl";
  const pathname = new URL(value).pathname.toLowerCase();
  if (pathname.endsWith(".flv"))
    return "video/x-flv";
  if (pathname.endsWith(".mp4") || pathname.endsWith(".m4v"))
    return "video/mp4";
  if (pathname.endsWith(".ts"))
    return "video/mp2t";
  return null;
}
function contentId(id) {
  const encoded = /^live:([^:]+)$/u.exec(id)?.[1];
  if (encoded === void 0)
    throw new Error("Content ID is invalid.");
  return decodeKey(encoded);
}
function chapterKey(id, address) {
  const prefix = `live:${encodeKey(address)}:`;
  if (!id.startsWith(prefix) || id.length === prefix.length)
    throw new Error("Chapter ID is invalid.");
  return id.slice(prefix.length);
}
function proxyImage(value) {
  if (!safeUrl(value))
    return null;
  return requireContext().resource.proxy({ kind: "image", url: value, headers: { Referer: base } });
}
function safeUrl(value) {
  try {
    const url = new URL(value);
    return (url.protocol === "https:" || url.protocol === "http:") && url.username === "" && url.password === "";
  } catch {
    return false;
  }
}
function decoded(value) {
  const raw = text(value);
  try {
    return decodeURIComponent(raw);
  } catch {
    return raw;
  }
}
function cursorPage(cursor, target) {
  if (cursor === null)
    return 1;
  const raw = cursor.startsWith(`${target}:`) ? cursor.slice(target.length + 1) : "";
  const page = Number(raw);
  if (!Number.isSafeInteger(page) || page < 2 || page > 1e3)
    throw new Error("Cursor is invalid.");
  return page;
}
function encodeKey(value) {
  return Buffer.from(value, "utf8").toString("base64url");
}
function decodeKey(value) {
  if (!/^[A-Za-z0-9_-]+$/u.test(value))
    throw new Error("Source key is invalid.");
  return Buffer.from(value, "base64url").toString("utf8");
}
function records(value) {
  return Array.isArray(value) ? value.filter(isObject) : [];
}
function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function text(value) {
  return typeof value === "string" ? value.trim() : typeof value === "number" ? String(value) : "";
}
function number(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}
function clamp(value) {
  return Math.max(1, Math.min(60, Math.floor(value)));
}
function frozen(value) {
  return Object.freeze(value);
}
function requireContext() {
  if (context === void 0)
    throw new Error("Source is not activated.");
  return context;
}
export {
  activate,
  discover,
  getChapters,
  getContent,
  getDetail,
  search,
  searchSuggestions
};

/**
 * 蜻蜓电台原生数据源。
 *
 * 职责：直接访问 qtfm GraphQL、详情与直播音频端点。
 * 生命周期：activate 注入宿主上下文；不保存账号或跨会话状态。
 * IO：元数据走 ctx.http，直播音频经 ctx.resource.proxy 交给 Runtime。
 * 稳定标识：使用蜻蜓 channel/radio ID，章节固定为该频道的 live 节点。
 */
import { createHmac } from 'node:crypto';
const web = 'https://www.qtfm.cn';
const graphql = 'https://webbff.qtfm.cn/www';
const detailBase = 'https://webapi.qtfm.cn/api/pc/radio/';
const playBase = 'https://lhttp-hw.qtfm.cn';
const liveSignKey = 'Lwrpu$K5oP';
const headers = Object.freeze({ Accept: 'application/json,text/plain,*/*', 'Content-Type': 'application/json', Referer: web, 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0' });
const categories = Object.freeze([
    ['217', '广东'], ['99', '浙江'], ['3', '北京'], ['5', '天津'], ['7', '河北'], ['83', '上海'], ['19', '山西'], ['31', '内蒙古'], ['44', '辽宁'], ['59', '吉林'], ['69', '黑龙江'], ['85', '江苏'], ['111', '安徽'], ['129', '福建'], ['139', '江西'], ['151', '山东'], ['169', '河南'], ['187', '湖北'], ['202', '湖南'], ['239', '广西'], ['254', '海南'], ['257', '重庆'], ['259', '四川'], ['281', '贵州'], ['291', '云南'], ['316', '陕西'], ['327', '甘肃'], ['351', '宁夏'], ['357', '新疆'], ['308', '西藏'], ['342', '青海'], ['433', '资讯'], ['442', '音乐'], ['429', '交通'], ['439', '经济'], ['432', '文艺'], ['441', '都市'], ['430', '体育'], ['431', '双语'], ['440', '综合'], ['438', '生活'], ['435', '旅游'], ['436', '曲艺'], ['434', '方言'],
]);
let context;
const channels = new Map();
export async function activate(next) { context = next; channels.clear(); next.log.info('source_activated'); }
export async function search(request) {
    const query = request.query.trim();
    if (query === '')
        return frozen({ items: [], nextCursor: null, totalCount: 0 });
    const page = cursorPage(request.cursor, 'search');
    const json = await graph(`{ searchResultsPage(keyword:${JSON.stringify(query)}, page:${page}, include:"channel_live") { searchData numFound } }`);
    const values = unwrap(object(object(json.data).searchResultsPage).searchData).slice(0, clamp(request.pageSize));
    return frozen({ items: values.map(summary), nextCursor: values.length >= clamp(request.pageSize) ? `search:${page + 1}` : null, totalCount: integer(object(object(json.data).searchResultsPage).numFound) });
}
export async function searchSuggestions(_request) { return frozen({ items: [], nextCursor: null }); }
export async function discover(request) {
    if (request.target === null) {
        if (request.cursor !== null || request.collectionId !== null)
            throw new Error('Initial discovery request is invalid.');
        return frozen({ kind: 'document', document: { components: [{ type: 'section', id: 'radio-categories', title: '电台分类', subtitle: '按地区与内容浏览', icon: 'audio', children: [{ type: 'categoryCollection', id: 'radio-categories-list', layout: 'chips', categories: categories.map(([id, title]) => ({ id, title, target: `category:${id}`, count: null, url: null, icon: 'audio' })) }] }] } });
    }
    const category = categories.find(([id]) => request.target === `category:${id}`);
    if (category === undefined)
        throw new Error('Discovery target is invalid.');
    const page = cursorPage(request.cursor, request.target);
    const limit = clamp(request.pageSize);
    const [id, title] = category;
    const json = await graph(`{ radioPage(cid:${id}, page:${page}) { contents } }`);
    const values = unwrap(object(object(json.data).radioPage).contents).slice(0, limit);
    const collectionId = `radio:${id}`;
    const items = values.map((value) => frozen({ content: summary(value), rank: null, metric: null, recommendation: null }));
    const continuation = values.length >= limit ? frozen({ target: request.target, cursor: `${request.target}:${page + 1}` }) : null;
    if (request.collectionId !== null) {
        if (request.collectionId !== collectionId)
            throw new Error('Discovery collection is invalid.');
        return frozen({ kind: 'append', collectionId, items, continuation });
    }
    return frozen({ kind: 'document', document: { components: [{ type: 'section', id: `${collectionId}:section`, title, subtitle: null, icon: 'audio', children: [{ type: 'contentCollection', id: collectionId, layout: 'coverGrid', items, continuation }] }] } });
}
export async function getDetail(request) {
    const id = contentId(request.id);
    const json = await fetchJson(`${detailBase}${encodeURIComponent(id)}`);
    const value = object(json.data);
    const item = summary({ ...value, id });
    return frozen({ ...item, aliases: [], catalogUrl: item.url });
}
export async function getChapters(request) {
    const id = contentId(request.id);
    const chapter = frozen({ id: `radio:${encodeKey(id)}:live`, title: '直播', order: 0, url: null, volumeTitle: '直播', wordCount: null, updatedAt: null, isLocked: null, attributes: [] });
    return frozen({ items: [chapter], groups: [frozen({ id: `group:${encodeKey(id)}:live`, title: '直播', order: 0, episodes: [chapter] })] });
}
export async function getContent(request) {
    const id = contentId(request.id);
    if (request.chapterId !== `radio:${encodeKey(id)}:live`)
        throw new Error('Chapter ID is invalid.');
    const resource = liveAudioResource(id);
    const mediaHeaders = { Referer: web, 'User-Agent': headers['User-Agent'] };
    return frozen({ chapterId: request.chapterId, contentKind: 'audio', title: '直播', updatedAt: null, text: null, pages: [], media: { url: requireContext().resource.proxy({ kind: 'audio', url: resource.url, headers: mediaHeaders }), resourceType: 'audio', resourcePolicy: 'refreshable', expiresAt: resource.expiresAt, mimeType: 'audio/mpeg', headers: mediaHeaders } });
}
async function graph(query) { return fetchJson(graphql, { query }); }
async function fetchJson(url, body) { const response = await requireContext().http.fetch(url, body === undefined ? { headers } : { method: 'POST', headers, body: JSON.stringify(body) }); if (!response.ok)
    throw new Error('Source request failed.'); const value = await response.json(); if (!isObject(value))
    throw new Error('Source response is invalid.'); return value; }
function summary(value) { const native = text(first(value.id, value.channelId, value.radioId, value.cid)); if (native === '')
    throw new Error('Source item has no ID.'); const merged = mergeChannel(channels.get(native), value); channels.set(native, merged); const id = encodeKey(native); const title = text(first(merged.title, merged.name, merged.channelName, merged.radioName)) || native; const category = nullable(first(merged.categoryName, merged.typeName)); return frozen({ id: `radio:${id}`, title, contentKind: 'audio', coverOrientation: 'portrait', author: nullable(first(merged.nickName, merged.anchor, merged.dj, merged.speaker)), url: `${web}/channels/${encodeURIComponent(native)}`, coverUrl: proxyImage(first(merged.imgUrl, merged.cover, merged.coverUrl, merged.img, merged.pic, merged.logo, merged.image)), description: nullable(first(merged.description, merged.desc, merged.intro, merged.subtitle, merged.subTitle)), language: 'zh-CN', status: 'ongoing', access: 'unknown', wordCount: null, chapterCount: 1, publishedAt: null, updatedAt: null, latestChapter: { id: `radio:${id}:live`, title: '直播', url: null, updatedAt: null }, categories: category === null ? [] : [category], tags: [], attributes: [] }); }
function unwrap(value) { if (typeof value === 'string') {
    try {
        return unwrap(JSON.parse(value));
    }
    catch {
        return [];
    }
} if (Array.isArray(value))
    return records(value); if (!isObject(value))
    return []; for (const key of ['contents', 'items', 'list', 'data']) {
    const result = unwrap(value[key]);
    if (result.length > 0)
        return result;
} return []; }
function contentId(id) { const encoded = /^radio:([^:]+)$/u.exec(id)?.[1]; if (encoded === undefined)
    throw new Error('Content ID is invalid.'); return decodeKey(encoded); }
function cursorPage(cursor, target) { if (cursor === null)
    return 1; const match = cursor.startsWith(`${target}:`) ? cursor.slice(target.length + 1) : ''; const page = Number(match); if (!Number.isSafeInteger(page) || page < 2 || page > 1000)
    throw new Error('Cursor is invalid.'); return page; }
function absolute(value) { const raw = text(value); if (raw === '')
    return null; try {
    return new URL(raw, web).toString();
}
catch {
    return null;
} }
function proxyImage(value) { const url = absolute(value); return url === null ? null : requireContext().resource.proxy({ kind: 'image', url, headers: { Referer: web, 'User-Agent': headers['User-Agent'] } }); }
function liveAudioResource(id) {
    const path = `/live/${encodeURIComponent(id)}/64k.mp3`;
    const expiresAtSeconds = Math.floor(Date.now() / 1000) + 3600;
    const timestamp = expiresAtSeconds.toString(16);
    const canonical = `app_id=${encodeURIComponent('web')}&path=${encodeURIComponent(path)}&ts=${encodeURIComponent(timestamp)}`;
    const sign = createHmac('md5', liveSignKey).update(canonical).digest('hex');
    const query = `app_id=${encodeURIComponent('web')}&ts=${encodeURIComponent(timestamp)}&sign=${encodeURIComponent(sign)}`;
    return frozen({ url: `${playBase}${path}?${query}`, expiresAt: new Date(expiresAtSeconds * 1000).toISOString() });
}
function encodeKey(value) { return Buffer.from(value, 'utf8').toString('base64url'); }
function decodeKey(value) { if (!/^[A-Za-z0-9_-]+$/u.test(value))
    throw new Error('Source key is invalid.'); return Buffer.from(value, 'base64url').toString('utf8'); }
function first(...values) { return values.find((value) => value !== null && value !== undefined && value !== '') ?? ''; }
function mergeChannel(previous, current) { const result = { ...(previous ?? {}) }; for (const [key, value] of Object.entries(current))
    if (value !== null && value !== undefined && value !== '')
        result[key] = value; return result; }
function records(value) { return Array.isArray(value) ? value.filter(isObject) : []; }
function object(value) { return isObject(value) ? value : {}; }
function isObject(value) { return value !== null && typeof value === 'object' && !Array.isArray(value); }
function text(value) { return typeof value === 'string' ? value.trim() : typeof value === 'number' ? String(value) : ''; }
function nullable(value) { const result = text(value); return result === '' ? null : result; }
function integer(value) { const result = Number(value); return Number.isSafeInteger(result) && result >= 0 ? result : null; }
function clamp(value) { return Math.max(1, Math.min(50, Math.floor(value))); }
function frozen(value) { return Object.freeze(value); }
function requireContext() { if (context === undefined)
    throw new Error('Source is not activated.'); return context; }

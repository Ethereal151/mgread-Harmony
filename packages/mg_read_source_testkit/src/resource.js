/**
 * Runtime-owned 资源描述的有界 live 探测。
 *
 * 职责：最多检查少量候选，记录状态/MIME，并只读取首个健康响应块后立即取消。
 */
import { SourceTestFailure, causeSummary } from './diagnostics.js';
import { createRuntimeLikeFetch } from './http.js';
import { createDecipheriv } from 'node:crypto';

export async function probeReachableResource({
  requests,
  fetch: sourceFetch = globalThis.fetch,
  expectedKind = 'image',
  expectedContentType = /^image\//u,
  validatePrefix = null,
  maximumAttempts = 3,
}) {
  if (!Number.isSafeInteger(maximumAttempts) || maximumAttempts < 1 || maximumAttempts > 8) {
    throw new SourceTestFailure('source_resource_attempt_limit_invalid', 'resource', {});
  }
  if (!(expectedContentType instanceof RegExp)) {
    throw new SourceTestFailure('source_resource_content_type_invalid', 'resource', {});
  }
  if (validatePrefix !== null && typeof validatePrefix !== 'function') {
    throw new SourceTestFailure('source_resource_prefix_validator_invalid', 'resource', {});
  }
  const runtimeFetch = createRuntimeLikeFetch(sourceFetch);
  const candidates = (Array.isArray(requests) ? requests : [])
    .filter((request) => request?.kind === expectedKind && typeof request.url === 'string')
    .slice(0, maximumAttempts);
  if (candidates.length === 0) {
    throw new SourceTestFailure('source_resource_missing', 'resource', { expectedKind });
  }

  const attempts = [];
  for (let index = 0; index < candidates.length; index += 1) {
    const request = candidates[index];
    try {
      const response = await fetchRegisteredResource(request, runtimeFetch);
      const contentType = (response.headers.get('content-type') ?? '').slice(0, 80);
      const attempt = { index: index + 1, url: request.url, status: response.status, contentType };
      expectedContentType.lastIndex = 0;
      if (response.ok && expectedContentType.test(contentType)) {
        const prefix = await readFirstBodyChunk(response);
        const bytesRead = prefix.byteLength;
        if (bytesRead > 0 && (validatePrefix === null || validatePrefix(prefix, contentType, request))) {
          attempts.push(Object.freeze({ ...attempt, bytesRead }));
          return Object.freeze({
            request,
            attempts: Object.freeze(attempts),
            bytesRead,
            contentType,
          });
        }
      } else {
        await response.body?.cancel();
      }
      attempts.push(Object.freeze(attempt));
    } catch (error) {
      attempts.push(Object.freeze({ index: index + 1, url: request.url, ...causeSummary(error) }));
    }
  }
  throw new SourceTestFailure('source_resource_unreachable', 'resource', {
    expectedKind,
    attempts: Object.freeze(attempts),
  });
}

async function fetchRegisteredResource(request, runtimeFetch) {
  if (request.resourceTransform !== 'aes-cbc-split-image-v1') {
    return runtimeFetch(request.url, { headers: request.headers, redirect: 'follow' });
  }
  const urls = Array.isArray(request.urls) ? request.urls : [];
  if (urls.length < 2 || urls.length > 8 || !urls.every((url) => typeof url === 'string')) {
    throw new Error('invalid transformed resource descriptor');
  }
  const parts = await Promise.all(urls.map((url) => runtimeFetch(url, {
    headers: request.headers,
    redirect: 'follow',
  })));
  const failed = parts.find((part) => !part.ok);
  if (failed !== undefined) return failed;
  const bodies = await Promise.all(parts.map(async (part) => {
    const body = new Uint8Array(await part.arrayBuffer());
    if (body.byteLength > 8 * 1024 * 1024) throw new Error('transformed resource part is too large');
    const decipher = createDecipheriv('aes-128-cbc', Buffer.from('aaaaaaaaaaaaaaaa'), Buffer.from('0123456789aaaaaa'));
    return Buffer.concat([decipher.update(body), decipher.final()]);
  }));
  const body = Buffer.concat(bodies);
  const type = body[0];
  const restored = type === 0
    ? Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, ...body.subarray(12)])
    : type === 1
      ? Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, ...body.subarray(8)])
      : type === 3
        ? Buffer.from([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, ...body.subarray(6)])
        : type === 4
          ? Buffer.from([0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, 0x61, 0x76, 0x69, 0x66, ...body.subarray(12)])
          : (() => { throw new Error('transformed resource format is invalid'); })();
  const contentType = type === 1 ? 'image/png' : type === 3 ? 'image/gif' : type === 4 ? 'image/avif' : 'image/jpeg';
  return new Response(restored, { status: 200, headers: { 'content-type': contentType } });
}

/**
 * 按内容契约独立探测封面、漫画页图和音视频资源组。
 *
 * `requests` 是测试宿主记录的 Runtime resource.proxy 描述；`projectedUrl`
 * 用于把返回对象里的代理 URL 关联回具体描述，避免用一条可达图片覆盖
 * 其它资源组的验证结果。
 */
export async function probeResourceGroups({
  requests,
  detail,
  discoveryItems = [],
  discoverySurfaces = [],
  searchItems = [],
  contents = [],
  contentKind,
  fetch: sourceFetch = globalThis.fetch,
}) {
  const records = Array.isArray(requests) ? requests : [];
  const allContents = Array.isArray(contents) ? contents : [];
  const kind = contentKind ?? allContents[0]?.contentKind ?? detail?.contentKind ?? null;
  const normalizedDiscoverySurfaces = toArray(discoverySurfaces).length > 0
    ? toArray(discoverySurfaces)
    : [{ name: 'discover', items: toArray(discoveryItems) }];
  const coverSurfaces = [
    ...normalizedDiscoverySurfaces.map((surface, index) => ({
      name: isNonBlank(surface?.name) ? surface.name : `discover.${index + 1}`,
      items: toArray(surface?.items),
      values: toArray(surface?.items).map((item) => item?.coverUrl).filter(isNonBlank),
    })),
    {
      name: 'search',
      items: toArray(searchItems),
      values: toArray(searchItems)
        .map((item) => item?.content?.coverUrl ?? item?.coverUrl)
        .filter(isNonBlank),
    },
    {
      name: 'detail',
      items: detail === null || detail === undefined ? [] : [detail],
      values: [detail?.coverUrl].filter(isNonBlank),
    },
  ].filter((surface) => surface.items.length > 0);
  const groups = {
    cover: await probeResourceSurfaces({
      applicable: coverSurfaces.length > 0,
      surfaces: coverSurfaces.map((surface) => ({
        ...surface,
        kind: 'image',
        mime: /^(image\/|application\/octet-stream)/u,
        validatePrefix: hasImageSignature,
      })),
      records,
      fetch: sourceFetch,
    }),
    comicImages: await probeResourceSurfaces({
      applicable: kind === 'manga',
      surfaces: comicPageSurfaces(allContents),
      records,
      fetch: sourceFetch,
    }),
    audio: await probeResourceSurfaces({
      applicable: kind === 'audio',
      surfaces: mediaSurfaces(allContents, 'audio'),
      records,
      fetch: sourceFetch,
    }),
    video: await probeResourceSurfaces({
      applicable: kind === 'video',
      surfaces: mediaSurfaces(allContents, 'video'),
      records,
      fetch: sourceFetch,
    }),
  };
  return Object.freeze(groups);
}

async function probeResourceSurfaces({ applicable, surfaces, records, fetch }) {
  if (!applicable) {
    return Object.freeze({ status: 'notTested', applicable: false, candidates: 0, surfaces: Object.freeze([]) });
  }
  if (surfaces.length === 0) {
    return Object.freeze({ status: 'notRegistered', applicable: true, candidates: 0, surfaces: Object.freeze([]) });
  }
  const results = [];
  for (const surface of surfaces) {
    const result = await probeResourceGroup({
      definition: {
        name: surface.name,
        applicable: true,
        kind: surface.kind,
        kinds: surface.kinds,
        mime: surface.mime,
        validatePrefix: surface.validatePrefix,
        values: surface.values,
      },
      records,
      fetch,
    });
    const itemCount = Array.isArray(surface.items) ? surface.items.length : surface.items;
    results.push(Object.freeze({ name: surface.name, items: itemCount, declared: surface.values.length, ...result }));
  }
  const failed = results.find((surface) => surface.status === 'failed');
  const status = failed !== undefined
    ? 'failed'
    : results.every((surface) => surface.status === 'passed')
      ? 'passed'
      : 'notRegistered';
  return Object.freeze({
    status,
    applicable: true,
    candidates: results.reduce((sum, surface) => sum + surface.candidates, 0),
    surfaces: Object.freeze(results),
    ...(failed?.failureCode === undefined ? {} : { failureCode: failed.failureCode }),
  });
}

function comicPageSurfaces(contents) {
  const surfaces = [];
  for (let contentIndex = 0; contentIndex < contents.length; contentIndex += 1) {
    const pages = toArray(contents[contentIndex]?.pages);
    const indexes = [...new Set([0, Math.floor((pages.length - 1) / 2), pages.length - 1])]
      .filter((index) => index >= 0 && index < pages.length);
    for (const pageIndex of indexes) {
      const value = pages[pageIndex]?.url;
      surfaces.push({
        name: `content.${contentIndex + 1}.page.${pageIndex + 1}`,
        items: 1,
        values: isNonBlank(value) ? [value] : [],
        kind: 'image',
        mime: /^(image\/|application\/octet-stream)/u,
        validatePrefix: hasImageSignature,
      });
    }
  }
  return surfaces;
}

function mediaSurfaces(contents, contentKind) {
  return contents.map((content, index) => {
    const value = content?.media?.url;
    return {
      name: `content.${index + 1}.media`,
      items: 1,
      values: isNonBlank(value) ? [value] : [],
      ...(contentKind === 'audio'
        ? { kind: 'audio', mime: /^(audio\/|application\/octet-stream)/u, validatePrefix: hasAudioSignature }
        : {
            kinds: ['video', 'hls'],
            mime: /^(video\/|application\/|text\/plain)/u,
            validatePrefix: hasVideoOrHlsSignature,
          }),
    };
  });
}

async function probeResourceGroup({ definition, records, fetch }) {
  if (!definition.applicable) {
    return Object.freeze({ status: 'notTested', applicable: false, candidates: 0 });
  }
  if (definition.values.length === 0) {
    return Object.freeze({ status: 'notRegistered', applicable: true, candidates: 0 });
  }
  const candidates = records.filter((request) => {
    const requestKind = String(request?.kind ?? '');
    const kindMatches = definition.kinds?.includes(requestKind) ?? requestKind === definition.kind;
    if (!kindMatches) return false;
    return definition.values.some((value) => requestMatches(value, request));
  }).sort((left, right) => matchRank(left, definition.values) - matchRank(right, definition.values));
  if (candidates.length === 0) {
    return Object.freeze({ status: 'notRegistered', applicable: true, candidates: 0 });
  }
  try {
    const result = await probeReachableResource({
      requests: candidates.map((request) => ({ ...request, resourceKind: request.kind, kind: 'candidate' })),
      fetch,
      expectedKind: 'candidate',
      expectedContentType: definition.mime,
      validatePrefix: definition.validatePrefix,
      maximumAttempts: Math.min(candidates.length, 8),
    });
    return Object.freeze({
      status: 'passed',
      applicable: true,
      candidates: candidates.length,
      attempts: result.attempts,
      bytesRead: result.bytesRead,
      contentType: result.contentType,
    });
  } catch (error) {
    if (!(error instanceof SourceTestFailure)) throw error;
    return Object.freeze({
      status: 'failed',
      applicable: true,
      candidates: candidates.length,
      attempts: error.summary.attempts ?? [],
      failureCode: error.code,
    });
  }
}

function requestMatches(value, request) {
  return value === request?.projectedUrl || value === request?.url;
}

function matchRank(request, values) {
  const index = values.findIndex((value) => requestMatches(value, request));
  return index < 0 ? Number.MAX_SAFE_INTEGER : index;
}

function toArray(value) {
  return Array.isArray(value) ? value : [];
}

function isNonBlank(value) {
  return typeof value === 'string' && value.trim().length > 0;
}

async function readFirstBodyChunk(response) {
  if (response.body === null) return new Uint8Array();
  const reader = response.body.getReader();
  try {
    const first = await reader.read();
    return first.done ? new Uint8Array() : first.value;
  } finally {
    await reader.cancel().catch(() => {});
  }
}

function hasImageSignature(bytes, contentType) {
  const jpeg = startsWith(bytes, [0xff, 0xd8, 0xff]);
  const png = startsWith(bytes, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const gif = startsWith(bytes, [0x47, 0x49, 0x46, 0x38]);
  const bmp = startsWith(bytes, [0x42, 0x4d]);
  const webp = startsWith(bytes, [0x52, 0x49, 0x46, 0x46]) && startsWith(bytes, [0x57, 0x45, 0x42, 0x50], 8);
  const avif = startsWith(bytes, [0x66, 0x74, 0x79, 0x70], 4);
  if (/image\/(?:jpeg|jpg)/iu.test(contentType)) return jpeg;
  if (/image\/png/iu.test(contentType)) return png;
  if (/image\/gif/iu.test(contentType)) return gif;
  if (/image\/bmp/iu.test(contentType)) return bmp;
  if (/image\/webp/iu.test(contentType)) return webp;
  if (/image\/avif/iu.test(contentType)) return avif;
  return jpeg || png || gif || bmp || webp || avif;
}

function hasAudioSignature(bytes) {
  return startsWith(bytes, [0x49, 0x44, 0x33])
    || startsWith(bytes, [0x66, 0x4c, 0x61, 0x43])
    || startsWith(bytes, [0x4f, 0x67, 0x67, 0x53])
    || (startsWith(bytes, [0x52, 0x49, 0x46, 0x46]) && startsWith(bytes, [0x57, 0x41, 0x56, 0x45], 8))
    || startsWith(bytes, [0x66, 0x74, 0x79, 0x70], 4)
    || (bytes.length >= 2 && bytes[0] === 0xff && (bytes[1] & 0xe0) === 0xe0);
}

function hasVideoOrHlsSignature(bytes, contentType, request) {
  const text = new TextDecoder().decode(bytes.subarray(0, Math.min(bytes.length, 64))).replace(/^\ufeff/u, '').trimStart();
  if (request?.resourceKind === 'hls' || /mpegurl/iu.test(contentType) || text.startsWith('#EXTM3U')) {
    return text.startsWith('#EXTM3U');
  }
  return startsWith(bytes, [0x66, 0x74, 0x79, 0x70], 4)
    || startsWith(bytes, [0x1a, 0x45, 0xdf, 0xa3])
    || startsWith(bytes, [0x46, 0x4c, 0x56])
    || (startsWith(bytes, [0x52, 0x49, 0x46, 0x46]) && startsWith(bytes, [0x41, 0x56, 0x49, 0x20], 8))
    || bytes[0] === 0x47;
}

function startsWith(bytes, signature, offset = 0) {
  if (bytes.length < offset + signature.length) return false;
  return signature.every((value, index) => bytes[offset + index] === value);
}

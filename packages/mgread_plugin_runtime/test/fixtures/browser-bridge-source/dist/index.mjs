let context;

export async function activate(nextContext) {
  context = nextContext;
}

export async function search(request) {
  if (request.query !== "browser-session") {
    return { items: [], nextCursor: null, totalCount: 0 };
  }
  const response = await context.browser.sessionV1.request({
    version: 1,
    sessionKey: "fixture",
    url: "https://example.invalid/protected",
    method: "GET",
    headers: { accept: "text/html" },
    body: null,
    interaction: "silent",
    presentation: "hidden",
    transport: "webview",
    timeoutMs: 5_000,
    maxResponseBytes: 4_096,
  });
  return {
    items: [{
      id: `browser:${response.status}`,
      title: `browser-${response.status}`,
      contentKind: "novel",
      author: "org.mgread.browser-bridge-fixture",
      url: "https://example.invalid/browser",
      coverUrl: null,
      description: null,
      language: "zh-CN",
      status: "ongoing",
      access: "free",
      wordCount: null,
      chapterCount: 0,
      publishedAt: null,
      updatedAt: null,
      latestChapter: null,
      categories: [],
      tags: [],
      attributes: [],
    }],
    nextCursor: null,
    totalCount: 1,
  };
}

export async function discover() {
  return { kind: "document", document: { components: [] } };
}

export async function getDetail(request) {
  return {
    id: request.id,
    title: request.id,
    contentKind: "novel",
    author: "org.mgread.browser-bridge-fixture",
    url: "https://example.invalid/browser",
    coverUrl: null,
    description: null,
    language: "zh-CN",
    status: "ongoing",
    access: "free",
    wordCount: null,
    chapterCount: 0,
    publishedAt: null,
    updatedAt: null,
    latestChapter: null,
    categories: [],
    tags: [],
    attributes: [],
    aliases: [],
    catalogUrl: null,
  };
}

export async function getChapters() {
  return { items: [] };
}

export async function getContent(request) {
  return {
    contentKind: "novel",
    chapterId: request.chapterId,
    title: request.chapterId,
    updatedAt: null,
    text: "fixture",
    pages: [],
  };
}

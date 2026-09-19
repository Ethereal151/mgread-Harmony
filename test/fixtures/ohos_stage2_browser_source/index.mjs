/**
 * Local-only OHOS Stage 2 acceptance source.
 *
 * The builder publishes this same code under five independent plugin IDs. The
 * first two IDs exercise normal Runtime content and resource projection, the
 * cookie/js ID keeps a cookie in one ArkWeb page and reads rendered HTML, the
 * js ID exercises page JavaScript, and the interaction ID proves the stable
 * interaction_required -> visible-page recovery path.
 */
let context;

export async function activate(nextContext) {
  context = nextContext;
}

function summary(id, title) {
  return {
    id,
    title,
    contentKind: "novel",
    author: "OHOS Stage 2 fixture",
    url: `https://example.com/books/${encodeURIComponent(id)}`,
    coverUrl: context.resource.proxy({
      kind: "image",
      url: "https://example.com/favicon.ico",
      headers: { accept: "image/x-icon" },
    }),
    description: "本地 fixture 只用于 OHOS Runtime 与 ArkWeb 验收。",
    language: "zh-CN",
    status: "completed",
    access: "free",
    wordCount: 32,
    chapterCount: 2,
    publishedAt: null,
    updatedAt: "2026-09-19T00:00:00Z",
    latestChapter: null,
    categories: ["OHOS", "ArkWeb"],
    tags: [],
    attributes: [],
  };
}

function result(title) {
  const id = `${context.plugin.id}:book`;
  return { items: [{ content: summary(id, title), rank: null, metric: null, recommendation: null }], nextCursor: null, totalCount: 1 };
}

function browserRequest(presentation = "hidden") {
  return {
    version: 1,
    sessionKey: "ohos-stage2",
    url: "https://example.com/",
    method: "GET",
    headers: { accept: "text/html" },
    body: null,
    interaction: "allow",
    presentation,
    transport: "html",
    timeoutMs: 30_000,
    maxResponseBytes: 64 * 1024,
  };
}

function coordinatesRequest(presentation) {
  return {
    version: 1,
    sessionKey: "ohos-stage2-interaction",
    url: "https://example.com/",
    selector: "body",
    presentation,
    timeoutMs: 30_000,
    action: "coordinates",
  };
}

async function cookieAndJs() {
  const page = await context.webview.open({ visible: false, timeoutMs: 30_000 });
  try {
    await page.navigate("https://example.com/", { timeoutMs: 30_000 });
    await page.executeJavaScript(
      "document.cookie='mgread_stage2=verified; path=/'; document.title='MgRead OHOS Stage 2'; true",
      { timeoutMs: 30_000 },
    );
    const cookie = await page.executeJavaScript("document.cookie", { timeoutMs: 30_000 });
    const response = await context.browser.sessionV1.request(browserRequest());
    const html = await page.getHtml({ timeoutMs: 30_000 });
    return `cookie-js:${response.status}:${cookie.includes("mgread_stage2=verified")}:${html.includes("Example Domain")}`;
  } finally {
    await page.close({ timeoutMs: 30_000 });
  }
}

async function javascriptPage() {
  const page = await context.webview.open({ visible: false, timeoutMs: 30_000 });
  try {
    await page.navigate("https://example.com/", { timeoutMs: 30_000 });
    const title = await page.executeJavaScript("document.title", { timeoutMs: 30_000 });
    const url = await page.getUrl({ timeoutMs: 30_000 });
    const html = await page.getHtml({ timeoutMs: 30_000 });
    return `js:${title}:${url.startsWith("https://example.com/")}:${html.includes("Example Domain")}`;
  } finally {
    await page.close({ timeoutMs: 30_000 });
  }
}

async function interactionRecovery() {
  const page = await context.webview.open({ visible: false, timeoutMs: 30_000 });
  await page.navigate("https://example.com/", { timeoutMs: 30_000 });
  let required = false;
  try {
    await context.browser.sessionV1.requestCoordinates(coordinatesRequest("hidden"));
  } catch (error) {
    if (error?.code !== "interaction_required") throw error;
    required = true;
  }
  if (!required) throw new Error("The hidden interaction did not return interaction_required.");
  await page.show({ timeoutMs: 30_000 });
  try {
    const accepted = await context.browser.sessionV1.requestCoordinates(coordinatesRequest("visible"));
    return `interaction_required:${accepted.accepted === true}`;
  } finally {
    await page.hide({ timeoutMs: 30_000 });
    await page.close({ timeoutMs: 30_000 });
  }
}

export async function discover() {
  return {
    kind: "document",
    document: {
      components: [{
        type: "section",
        id: `${context.plugin.id}:section`,
        title: "OHOS 阶段 2 fixture",
        subtitle: null,
        children: [{
          type: "contentCollection",
          id: `${context.plugin.id}:collection`,
          layout: "list",
          continuation: null,
          items: [{ content: summary(`${context.plugin.id}:book`, "OHOS 阶段 2 fixture"), rank: null, metric: null, recommendation: null }],
        }],
      }],
    },
  };
}

export async function search(request) {
  if (context.plugin.id.endsWith("cookie-js")) return result(await cookieAndJs());
  if (context.plugin.id.endsWith("javascript")) return result(await javascriptPage());
  if (context.plugin.id.endsWith("interaction")) {
    if (request.query === "interaction-required") {
      const page = await context.webview.open({ visible: false, timeoutMs: 30_000 });
      await page.navigate("https://example.com/", { timeoutMs: 30_000 });
      return context.browser.sessionV1.requestCoordinates(coordinatesRequest("hidden"));
    }
    return result(await interactionRecovery());
  }
  return result(`normal:${context.plugin.id}`);
}

export async function getDetail(request) {
  return { ...summary(request.id, `detail:${context.plugin.id}`), id: request.id, aliases: [], catalogUrl: null };
}

export async function getChapters(request) {
  return {
    items: [0, 1].map((order) => ({
      id: `${request.id}:chapter-${order + 1}`,
      title: `第 ${order + 1} 章`,
      order,
      url: null,
      volumeTitle: null,
      wordCount: 16,
      updatedAt: null,
      isLocked: false,
      attributes: [],
    })),
  };
}

export async function getContent(request) {
  return {
    contentKind: "novel",
    chapterId: request.chapterId,
    title: "OHOS 阶段 2 fixture 正文",
    updatedAt: null,
    text: `Runtime 正文链路已完成：${request.chapterId}`,
    pages: [],
  };
}

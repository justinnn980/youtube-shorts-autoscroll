const http = require("http");
const fs = require("fs");
const path = require("path");

const PORT = Number(process.env.PORT || 3002);
const HOST = process.env.HOST || "0.0.0.0";

const PUBLIC_DIR = path.join(__dirname, "public");
const DIST_DIR = path.join(__dirname, "dist");
const SIMULATOR_DIR = path.join(__dirname, "simulator");
const DATA_DIR = path.join(__dirname, "data");

fs.mkdirSync(DATA_DIR, { recursive: true });

const STATS_FILE = path.join(DATA_DIR, "stats.json");
const AD_CONFIG_FILE = path.join(DATA_DIR, "ad-config.json");

const defaultStats = {
  views: 128,
  adImpressions: 384,
  downloads: {
    ios_ipa: 42,
    android_apk: 57,
    pc_ext: 19,
    userscript: 14
  }
};

const defaultAdConfig = {
  // 구글 애드센스 승인 후 ca-pub-XXXXXXXXXXXXXXXX 입력 시 전 슬롯 및 /ads.txt 자동 활성화
  adsenseClientId: "",
  // 구글 서치콘솔 & 네이버 서치어드바이저 소유권 확인 메타태그 값
  googleSiteVerification: "",
  naverSiteVerification: "",
  adsenseSlots: {
    topBanner: "",
    inArticle: "",
    downloadModal: "",
    bottomSticky: ""
  },
  // 카카오 애드핏 DAN-XXXXXXXX 입력 시 자동 활성화
  kakaoAdFitUnitTop: "",
  kakaoAdFitUnitModal: "",
  // 쿠팡 파트너스 또는 제휴 스폰서 배너 링크 (다운로드 5초 대기 모달 및 배너 클릭 시 수익 발생)
  sponsorBanner: {
    enabled: true,
    badge: "SPONSORED",
    title: "스마트폰 거치대 & 맥세이프 충전기 초특가 모음",
    subtitle: "침대에서 손 안 대고 유튜브 쇼츠 볼 때 필수템! 로켓와우 무료배송",
    ctaText: "특가 확인하기 →",
    linkUrl: "https://www.coupang.com"
  }
};

function loadJson(filePath, fallback) {
  try {
    if (fs.existsSync(filePath)) {
      return { ...fallback, ...JSON.parse(fs.readFileSync(filePath, "utf8")) };
    }
  } catch (_) {}
  fs.writeFileSync(filePath, JSON.stringify(fallback, null, 2), "utf8");
  return JSON.parse(JSON.stringify(fallback));
}

function saveJson(filePath, data) {
  try {
    fs.writeFileSync(filePath, JSON.stringify(data, null, 2), "utf8");
  } catch (_) {}
}

const stats = loadJson(STATS_FILE, defaultStats);
const adConfig = loadJson(AD_CONFIG_FILE, defaultAdConfig);

const MIME_TYPES = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".xml": "application/xml; charset=utf-8",
  ".txt": "text/plain; charset=utf-8",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".apk": "application/vnd.android.package-archive",
  ".ipa": "application/octet-stream",
  ".dylib": "application/octet-stream",
  ".zip": "application/zip"
};

function getBaseUrl(req) {
  const proto = req.headers["x-forwarded-proto"] || "https";
  const host = req.headers["x-forwarded-host"] || req.headers.host || "shorts.pyoing.cloud";
  return `${proto}://${host}`;
}

function serveFileWithRange(req, res, filePath, forceDownloadName = null) {
  if (!fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
    res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("File Not Found");
    return;
  }

  const stat = fs.statSync(filePath);
  const ext = path.extname(filePath).toLowerCase();
  const contentType = MIME_TYPES[ext] || "application/octet-stream";

  const headers = {
    "Content-Type": contentType,
    "Accept-Ranges": "bytes"
  };

  if (forceDownloadName) {
    headers["Content-Disposition"] = `attachment; filename="${forceDownloadName}"`;
  }

  const range = req.headers.range;
  if (range) {
    const parts = range.replace(/bytes=/, "").split("-");
    const start = parseInt(parts[0], 10);
    const end = parts[1] ? parseInt(parts[1], 10) : stat.size - 1;
    if (start >= stat.size || end >= stat.size) {
      res.writeHead(416, { "Content-Range": `bytes */${stat.size}` });
      res.end();
      return;
    }
    headers["Content-Range"] = `bytes ${start}-${end}/${stat.size}`;
    headers["Content-Length"] = end - start + 1;
    res.writeHead(206, headers);
    fs.createReadStream(filePath, { start, end }).pipe(res);
  } else {
    headers["Content-Length"] = stat.size;
    res.writeHead(200, headers);
    fs.createReadStream(filePath).pipe(res);
  }
}

const server = http.createServer((req, res) => {
  const parsedUrl = new URL(req.url, `http://${req.headers.host || "localhost"}`);
  const pathname = parsedUrl.pathname;
  const baseUrl = getBaseUrl(req);

  // 1. SEO: /robots.txt (구글 Googlebot, 네이버 Yeti, 다음 Daumoa 모두 수집 허용)
  if (pathname === "/robots.txt") {
    const txt = [
      "User-agent: *",
      "Allow: /",
      "User-agent: Yeti",
      "Allow: /",
      "User-agent: Googlebot",
      "Allow: /",
      `Sitemap: ${baseUrl}/sitemap.xml`,
      `Sitemap: ${baseUrl}/rss.xml`
    ].join("\n");
    res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
    res.end(txt);
    return;
  }

  // 2. SEO: /sitemap.xml (구글 서치콘솔 & 네이버 서치어드바이저 제출용)
  if (pathname === "/sitemap.xml") {
    const today = new Date().toISOString().split("T")[0];
    const xml = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>${baseUrl}/</loc>
    <lastmod>${today}</lastmod>
    <changefreq>daily</changefreq>
    <priority>1.0</priority>
  </url>
  <url>
    <loc>${baseUrl}/simulator</loc>
    <lastmod>${today}</lastmod>
    <changefreq>weekly</changefreq>
    <priority>0.8</priority>
  </url>
</urlset>`;
    res.writeHead(200, { "Content-Type": "application/xml; charset=utf-8" });
    res.end(xml);
    return;
  }

  // 3. SEO: /rss.xml (네이버 검색 노출 최적화용 RSS 2.0 피드)
  if (pathname === "/rss.xml" || pathname === "/feed.xml") {
    const pubDate = new Date().toUTCString();
    const rss = `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>유튜브 쇼츠 자동 넘김 (AutoShorts) - 아이폰·갤럭시·PC 공식 가이드</title>
    <link>${baseUrl}/</link>
    <description>순정 유튜브 공식 어플에서 쇼츠가 끝나면 반복 재생 없이 자동으로 다음 쇼츠로 넘겨주는 유틸리티 다운로드 및 설치 방법</description>
    <language>ko</language>
    <pubDate>${pubDate}</pubDate>
    <item>
      <title>아이폰(iOS) 순정 유튜브 어플 쇼츠 자동 넘김 설치 방법 (YouTube-AutoShorts.ipa)</title>
      <link>${baseUrl}/#panel-ios</link>
      <description>아이폰 순정 유튜브 앱 내부 Auto-Advance 기능을 활성화하여 쇼츠 영상이 끝날 때 자동으로 다음 쇼츠로 넘기는 방법과 Sideloadly 설치 가이드입니다.</description>
      <pubDate>${pubDate}</pubDate>
      <guid>${baseUrl}/#panel-ios</guid>
    </item>
    <item>
      <title>갤럭시(안드로이드) 유튜브 쇼츠 자동 넘김 APK 다운로드 및 설정 방법</title>
      <link>${baseUrl}/#panel-android</link>
      <description>갤럭시 스마트폰에 설치된 순정 유튜브 공식 앱의 쇼츠 탭에서 영상이 끝까지 재생되면 자동으로 다음 영상으로 스와이프해 주는 앱 설치 가이드입니다.</description>
      <pubDate>${pubDate}</pubDate>
      <guid>${baseUrl}/#panel-android</guid>
    </item>
    <item>
      <title>PC 크롬·웨일·엣지 유튜브 쇼츠 자동 스크롤 확장 프로그램 설치 가이드</title>
      <link>${baseUrl}/#panel-pc</link>
      <description>PC 브라우저에서 유튜브 쇼츠 반복 재생을 막고 영상 종료 시 자동으로 다음 쇼츠로 넘기는 확장 프로그램 다운로드입니다.</description>
      <pubDate>${pubDate}</pubDate>
      <guid>${baseUrl}/#panel-pc</guid>
    </item>
  </channel>
</rss>`;
    res.writeHead(200, { "Content-Type": "application/xml; charset=utf-8" });
    res.end(rss);
    return;
  }

  // 4. Google AdSense /ads.txt 자동 대응
  if (pathname === "/ads.txt") {
    const pubId = (adConfig.adsenseClientId || "pub-0000000000000000").replace(/^ca-/, "");
    res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
    res.end(`google.com, ${pubId}, DIRECT, f08c47fec0942fa0\n`);
    return;
  }

  // API: 방문자 및 다운로드 통계 + 광고 설정 조회
  if (pathname === "/api/bootstrap" && req.method === "GET") {
    stats.views += 1;
    stats.adImpressions += 3;
    saveJson(STATS_FILE, stats);
    res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ stats, adConfig }));
    return;
  }

  // API: 광고 노출 카운트 증가
  if (pathname === "/api/ad-impression" && req.method === "POST") {
    stats.adImpressions += 1;
    saveJson(STATS_FILE, stats);
    res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ ok: true, stats }));
    return;
  }

  // 다운로드 엔드포인트 (/download/...)
  const downloadMap = {
    "/download/AutoShorts-App.ipa": {
      file: path.join(DIST_DIR, "AutoShorts-App.ipa"),
      name: "AutoShorts-App.ipa",
      key: "ios_ipa"
    },
    "/download/YouTube-AutoShorts.ipa": {
      file: path.join(DIST_DIR, "YouTube-AutoShorts.ipa"),
      name: "YouTube-AutoShorts.ipa",
      key: "ios_ipa"
    },
    "/download/YouTubeShortsAutoScroll.apk": {
      file: path.join(DIST_DIR, "YouTubeShortsAutoScroll.apk"),
      name: "YouTubeShortsAutoScroll.apk",
      key: "android_apk"
    },
    "/download/YouTubeAutoShorts-ChromeExtension.zip": {
      file: path.join(DIST_DIR, "YouTubeAutoShorts-ChromeExtension.zip"),
      name: "YouTubeAutoShorts-ChromeExtension.zip",
      key: "pc_ext"
    },
    "/download/YouTubeAutoShorts.user.js": {
      file: path.join(DIST_DIR, "YouTubeAutoShorts.user.js"),
      name: "YouTubeAutoShorts.user.js",
      key: "userscript"
    },
    "/download/YouTubeAutoShorts.dylib": {
      file: path.join(DIST_DIR, "YouTubeAutoShorts.dylib"),
      name: "YouTubeAutoShorts.dylib",
      key: "ios_ipa"
    }
  };

  if (downloadMap[pathname]) {
    const item = downloadMap[pathname];
    stats.downloads[item.key] = (stats.downloads[item.key] || 0) + 1;
    saveJson(STATS_FILE, stats);
    const forceAttach = pathname.endsWith(".user.js") ? null : item.name;
    serveFileWithRange(req, res, item.file, forceAttach);
    return;
  }

  // 시뮬레이터 경로
  if (pathname === "/simulator" || pathname === "/simulator/") {
    serveFileWithRange(req, res, path.join(SIMULATOR_DIR, "index.html"));
    return;
  }

  // 메인 정적 파일 서빙 (public/)
  const relPath = pathname === "/" ? "index.html" : pathname.replace(/^\/+/, "");
  const safePath = path.normalize(path.join(PUBLIC_DIR, relPath));
  if (!safePath.startsWith(PUBLIC_DIR)) {
    res.writeHead(403);
    res.end("Forbidden");
    return;
  }

  serveFileWithRange(req, res, safePath);
});

server.listen(PORT, HOST, () => {
  console.log(`[AutoShorts Web Server] Running at http://${HOST}:${PORT}`);
});

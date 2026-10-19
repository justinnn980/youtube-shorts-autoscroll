const http = require("http");
const fs = require("fs");
const path = require("path");
const os = require("os");
const { spawn } = require("child_process");

const PORT = 8899;
const DIST_DIR = path.join(__dirname, "dist");

let publicTunnelUrl = "";

function getLanIp() {
  const nets = os.networkInterfaces();
  for (const name of Object.keys(nets)) {
    for (const net of nets[name]) {
      if (net.family === "IPv4" && !net.internal) {
        return net.address;
      }
    }
  }
  return "localhost";
}

// Cloudflared 터널 자동 실행 (와이파이가 달라도 LTE/5G로 스마트폰에서 즉시 접속 가능)
function startCloudflaredTunnel() {
  try {
    const cf = spawn("cloudflared", ["tunnel", "--url", `http://localhost:${PORT}`], {
      stdio: ["ignore", "pipe", "pipe"]
    });
    const onData = (chunk) => {
      const str = chunk.toString();
      const match = str.match(/https:\/\/[a-z0-9-]+\.trycloudflare\.com/i);
      if (match && !publicTunnelUrl) {
        publicTunnelUrl = match[0];
        console.log(`[Cloudflare Tunnel] 외부/5G 접속 주소 생성 완료: ${publicTunnelUrl}`);
      }
    };
    cf.stdout.on("data", onData);
    cf.stderr.on("data", onData);
    cf.on("error", () => {});
  } catch (_) {}
}

const MIME_TYPES = {
  ".html": "text/html; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".apk": "application/vnd.android.package-archive",
  ".dylib": "application/octet-stream",
  ".ipa": "application/octet-stream"
};

const server = http.createServer((req, res) => {
  const urlPath = req.url.split("?")[0];

  if (urlPath === "/api/info") {
    const lanUrl = `http://${getLanIp()}:${PORT}`;
    res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
    res.end(
      JSON.stringify({
        lanUrl,
        publicUrl: publicTunnelUrl || lanUrl
      })
    );
    return;
  }

  let filePath = path.join(DIST_DIR, urlPath === "/" ? "index.html" : urlPath);
  if (!filePath.startsWith(DIST_DIR)) {
    res.writeHead(403);
    res.end("Forbidden");
    return;
  }

  if (!fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
    res.writeHead(404);
    res.end("Not Found");
    return;
  }

  const ext = path.extname(filePath);
  const contentType = MIME_TYPES[ext] || "application/octet-stream";
  const headers = { "Content-Type": contentType };

  if (ext === ".apk" || ext === ".dylib" || ext === ".ipa") {
    headers["Content-Disposition"] = `attachment; filename="${path.basename(filePath)}"`;
  }

  res.writeHead(200, headers);
  fs.createReadStream(filePath).pipe(res);
});

server.listen(PORT, "0.0.0.0", () => {
  const lanUrl = `http://${getLanIp()}:${PORT}`;
  console.log(`====================================================`);
  console.log(`📱 스마트폰 원클릭 설치 서버가 실행되었습니다!`);
  console.log(`- 로컬 Wi-Fi 접속: ${lanUrl}`);
  console.log(`====================================================`);
  startCloudflaredTunnel();
});


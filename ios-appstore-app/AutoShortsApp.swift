import SwiftUI
import WebKit
// 앱스토어 정식 출시 시 GoogleMobileAds SDK 연동 (CocoaPods / Swift Package Manager: Google-Mobile-Ads-SDK)
// import GoogleMobileAds

/**
 * AutoShorts - iOS 앱스토어(App Store) 정식 출시 및 광고 수익화용 네이티브 앱
 *
 * [작동 원리 - 일반 사용자용 (비개발자 1초 사용)]
 * 1. 사용자는 앱스토어에서 일반 앱처럼 다운로드하여 실행합니다 (PC 연결/Sideloadly 불필요).
 * 2. WKWebView가 공식 모바일 유튜브 쇼츠(https://m.youtube.com/shorts)를 순정 그대로 로드합니다.
 *    (구글 로그인, 알고리즘, 댓글창, 좋아요 등 순정 유튜브 UI 100% 동일)
 * 3. WKUserScript가 백그라운드에서 <video>의 loop를 해제하고 재생이 100% 끝나는 시점에
 *    자동으로 다음 쇼츠로 부드럽게 스크롤합니다.
 * 4. 하단 [⚙️ 설정] 탭에서 쇼츠 자동 넘김 ON/OFF를 제어하며,
 *    배너 광고(AdMob Banner) 및 24시간 무료 충전소(보상형 리워드 광고)로 광고 수익을 창출합니다.
 */

@main
struct AutoShortsApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(.dark)
        }
    }
}

class AutoShortsSettings: ObservableObject {
    @AppStorage("autoScrollEnabled") var autoScrollEnabled: Bool = true
    @AppStorage("pauseOnComments") var pauseOnComments: Bool = true
    @AppStorage("rewardExpireTimestamp") var rewardExpireTimestamp: Double = Date().addingTimeInterval(3600 * 24).timeIntervalSince1970

    var isPassActive: Bool {
        Date().timeIntervalSince1970 < rewardExpireTimestamp
    }

    var remainingHoursText: String {
        let diff = max(0, rewardExpireTimestamp - Date().timeIntervalSince1970)
        let hours = Int(diff) / 3600
        let mins = (Int(diff) % 3600) / 60
        return "\(hours)시간 \(mins)분 남음"
    }

    func grant24HoursReward() {
        let base = max(Date().timeIntervalSince1970, rewardExpireTimestamp)
        rewardExpireTimestamp = base + (24 * 3600)
    }
}

struct MainTabView: View {
    @StateObject private var settings = AutoShortsSettings()
    @State private var selectedTab: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                // 탭 1: 순정 유튜브 쇼츠 플레이어 (화면 가리는 플로팅 버튼 일절 없음)
                YouTubeShortsWebView(settings: settings)
                    .edgesIgnoringSafeArea(.top)
                    .tabItem {
                        Image(systemName: "play.rectangle.fill")
                        Text("Shorts")
                    }
                    .tag(0)

                // 탭 2: 설정(Settings) 전용 화면 (ON/OFF 스위치 & 리워드 광고 충전소)
                SettingsScreen(settings: settings)
                    .tabItem {
                        Image(systemName: "gearshape.fill")
                        Text("설정")
                    }
                    .tag(1)
            }

            // 하단 고정 AdMob 배너 광고 영역 (수익화 1: 상시 노출 배너 광고)
            AdMobBannerContainerView()
                .frame(height: 50)
                .background(Color(red: 0.08, green: 0.08, blue: 0.1))
        }
    }
}

struct SettingsScreen: View {
    @ObservedObject var settings: AutoShortsSettings
    @State private var showingRewardAdAlert = false

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("쇼츠 자동 넘김 설정")) {
                    Toggle(isOn: $settings.autoScrollEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("쇼츠 자동 넘김 (반복 재생 방지)")
                                .font(.headline)
                            Text("영상이 끝까지(100%) 재생되면 자동으로 다음 쇼츠로 넘어갑니다.")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .tint(.blue)

                    Toggle(isOn: $settings.pauseOnComments) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("댓글·설명창 열람 시 일시정지")
                                .font(.headline)
                            Text("댓글을 읽고 있는 동안에는 영상이 끝나도 넘어가지 않습니다.")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .tint(.blue)
                }

                // 수익화 2: 보상형 리워드 광고 (단가가 가장 높은 핵심 수익원)
                Section(header: Text("무료 자동 넘김 이용 시간")) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("남은 자동 넘김 활성화 시간")
                                .font(.subheadline)
                            Text(settings.remainingHoursText)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                        }
                        Spacer()
                        Button(action: {
                            // 실제 출시 시 GADRewardedAd.load(...) 표시 후 완료 콜백에서 호출
                            showingRewardAdAlert = true
                        }) {
                            Text("🎬 광고 보고 +24시간 충전")
                                .font(.caption)
                                .fontWeight(.bold)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                }
            }
            .navigationTitle("설정")
            .alert("리워드 광고 시청 완료!", isPresented: $showingRewardAdAlert) {
                Button("확인", role: .cancel) {
                    settings.grant24HoursReward()
                }
            } message: {
                Text("자동 넘김 무료 이용 시간이 24시간 연장되었습니다.")
            }
        }
    }
}

struct YouTubeShortsWebView: UIViewRepresentable {
    @ObservedObject var settings: AutoShortsSettings

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let scriptSource = """
        (function() {
            window.__ytAutoShortsEnabled = \(settings.autoScrollEnabled && settings.isPassActive ? "true" : "false");
            window.__ytPauseOnComments = \(settings.pauseOnComments ? "true" : "false");
            let lastScrollAt = 0;
            let maxRatio = 0;
            let lastSrc = "";

            function isCommentsOpen() {
                if (!window.__ytPauseOnComments) return false;
                const panel = document.querySelector("ytm-engagement-panel-section-list-renderer, .engagement-panel-container");
                return Boolean(panel && panel.offsetParent !== null);
            }

            function scrollNext() {
                const now = Date.now();
                if (now - lastScrollAt < 1400 || isCommentsOpen()) return;
                lastScrollAt = now;
                maxRatio = 0;

                const activeSlide = document.querySelector("ytm-reel-item-renderer.reel-item-active");
                if (activeSlide && activeSlide.nextElementSibling) {
                    activeSlide.nextElementSibling.scrollIntoView({ behavior: "smooth", block: "center" });
                    return;
                }
                window.scrollBy({ top: window.innerHeight, behavior: "smooth" });
            }

            setInterval(() => {
                if (!location.pathname.startsWith("/shorts")) return;
                const videos = Array.from(document.querySelectorAll("video"));
                const v = videos.find(el => !el.paused && el.readyState >= 2) || videos[0];
                if (!v) return;

                if (window.__ytAutoShortsEnabled && v.hasAttribute("loop")) {
                    v.removeAttribute("loop");
                    v.loop = false;
                }

                if (v.dataset.boundAutoShorts === "1") return;
                v.dataset.boundAutoShorts = "1";

                v.addEventListener("timeupdate", () => {
                    if (!window.__ytAutoShortsEnabled) return;
                    const dur = v.duration;
                    const cur = v.currentTime;
                    if (!dur || dur <= 0.4) return;
                    if (v.currentSrc !== lastSrc) {
                        lastSrc = v.currentSrc;
                        maxRatio = 0;
                    }
                    const ratio = cur / dur;
                    if (ratio >= 0.985 || (maxRatio >= 0.85 && ratio < 0.12)) {
                        scrollNext();
                        return;
                    }
                    if (ratio > maxRatio) maxRatio = ratio;
                });

                v.addEventListener("ended", () => {
                    if (window.__ytAutoShortsEnabled) scrollNext();
                });
            }, 250);
        })();
        """

        let userScript = WKUserScript(source: scriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        config.userContentController.addUserScript(userScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
        if let url = URL(string: "https://m.youtube.com/shorts") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let active = (settings.autoScrollEnabled && settings.isPassActive) ? "true" : "false"
        let pause = settings.pauseOnComments ? "true" : "false"
        webView.evaluateJavaScript("window.__ytAutoShortsEnabled = \(active); window.__ytPauseOnComments = \(pause);", completionHandler: nil)
    }
}

struct AdMobBannerContainerView: View {
    var body: some View {
        HStack {
            Text("AD")
                .font(.caption2)
                .fontWeight(.bold)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.yellow.opacity(0.85))
                .foregroundColor(.black)
                .cornerRadius(4)
            Text("Google AdMob 배너 광고 영역 (월 고정 광고 수익)")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}


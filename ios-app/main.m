#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <CoreMotion/CoreMotion.h>
#import <AVFoundation/AVFoundation.h>

static NSString * const kPrefAutoAdvance   = @"AS_AutoAdvance_v2";
static NSString * const kPrefShakeToSkip   = @"AS_ShakeToSkip_v2";
static NSString * const kPrefPauseComments = @"AS_PauseComments_v2";

@interface AutoShortsBridgeHandler : NSObject <WKScriptMessageHandler>
@property (nonatomic, weak) id target;
@property (nonatomic, assign) SEL action;
- (instancetype)initWithTarget:(id)target action:(SEL)action;
@end

@implementation AutoShortsBridgeHandler
- (instancetype)initWithTarget:(id)target action:(SEL)action {
    if (self = [super init]) {
        _target = target;
        _action = action;
    }
    return self;
}
- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    if (_target && [_target respondsToSelector:_action]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [_target performSelector:_action withObject:message];
#pragma clang diagnostic pop
    }
}
@end

@interface AutoShortsViewController : UIViewController <WKNavigationDelegate, WKUIDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) CMMotionManager *motionManager;
@property (nonatomic, strong) UISelectionFeedbackGenerator *scrubHaptic;
@property (nonatomic, assign) double lastAccelX;
@property (nonatomic, assign) double lastAccelY;
@property (nonatomic, assign) double lastAccelZ;
@property (nonatomic, assign) BOOL hasBaselineAccel;
@property (nonatomic, assign) NSTimeInterval lastShakeTime;
@property (nonatomic, assign) BOOL isOnShortsTab;
@end

@implementation AutoShortsViewController

- (void)initializeDefaults {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    if ([defs objectForKey:kPrefAutoAdvance] == nil)   [defs setBool:YES forKey:kPrefAutoAdvance];
    if ([defs objectForKey:kPrefShakeToSkip] == nil)   [defs setBool:YES forKey:kPrefShakeToSkip];
    if ([defs objectForKey:kPrefPauseComments] == nil) [defs setBool:YES forKey:kPrefPauseComments];
    [defs synchronize];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self initializeDefaults];

    UIColor *ytDark = [UIColor colorWithRed:15.0/255.0 green:15.0/255.0 blue:15.0/255.0 alpha:1.0];
    self.view.backgroundColor = ytDark;
    self.scrubHaptic = [[UISelectionFeedbackGenerator alloc] init];

    NSError *audioErr = nil;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback
                                     withOptions:AVAudioSessionCategoryOptionMixWithOthers
                                           error:&audioErr];
    [[AVAudioSession sharedInstance] setActive:YES error:&audioErr];

    [UIApplication sharedApplication].idleTimerDisabled = YES;

    [self setupPureYouTubeWebView];
    [self setupMotionManager];

    NSURL *ytHome = [NSURL URLWithString:@"https://m.youtube.com"];
    [self.webView loadRequest:[NSURLRequest requestWithURL:ytHome]];
}

- (void)setupPureYouTubeWebView {
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;
    config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    config.websiteDataStore = [WKWebsiteDataStore defaultDataStore];

    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    AutoShortsBridgeHandler *handler = [[AutoShortsBridgeHandler alloc] initWithTarget:self action:@selector(handleBridgeMessage:)];
    [ucc addScriptMessageHandler:handler name:@"autoshorts"];

    WKUserScript *script = [[WKUserScript alloc] initWithSource:[self injectedJavaScriptSource]
                                                  injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                               forMainFrameOnly:YES];
    [ucc addUserScript:script];
    config.userContentController = ucc;

    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
    UIColor *ytDark = [UIColor colorWithRed:15.0/255.0 green:15.0/255.0 blue:15.0/255.0 alpha:1.0];
    self.webView.backgroundColor = ytDark;
    self.webView.opaque = NO;
    self.webView.scrollView.backgroundColor = ytDark;
    self.webView.scrollView.bounces = NO;
    self.webView.allowsBackForwardNavigationGestures = YES;
    self.webView.customUserAgent = @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1";

    [self.view addSubview:self.webView];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.webView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.webView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor]
    ]];
}

- (WKWebView *)webView:(WKWebView *)webView
createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
   forNavigationAction:(WKNavigationAction *)navigationAction
        windowFeatures:(WKWindowFeatures *)windowFeatures {
    if (!navigationAction.targetFrame.isMainFrame && navigationAction.request.URL) {
        [webView loadRequest:navigationAction.request];
    }
    return nil;
}

- (void)webView:(WKWebView *)webView
decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = navigationAction.request.URL;
    NSString *scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"] || [scheme isEqualToString:@"about"] || [scheme isEqualToString:@"blob"]) {
        decisionHandler(WKNavigationActionPolicyAllow);
    } else {
        decisionHandler(WKNavigationActionPolicyCancel);
    }
}

- (void)handleBridgeMessage:(WKScriptMessage *)message {
    if (![message.body isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *body = (NSDictionary *)message.body;
    NSString *type = body[@"type"];
    if ([type isEqualToString:@"route"]) {
        self.isOnShortsTab = [body[@"isShorts"] boolValue];
    } else if ([type isEqualToString:@"scrubHaptic"]) {
        [self.scrubHaptic selectionChanged];
        [self.scrubHaptic prepare];
    } else if ([type isEqualToString:@"savePrefs"]) {
        NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
        if (body[@"enabled"] != nil) {
            [defs setBool:[body[@"enabled"] boolValue] forKey:kPrefAutoAdvance];
        }
        if (body[@"shake"] != nil) {
            [defs setBool:[body[@"shake"] boolValue] forKey:kPrefShakeToSkip];
        }
        [defs synchronize];
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [gen impactOccurred];
    }
}

#pragma mark - 쇼츠 탭 흔들기 스킵 (CoreMotion)

- (void)setupMotionManager {
    self.motionManager = [[CMMotionManager alloc] init];
    if (!self.motionManager.isAccelerometerAvailable) return;
    self.motionManager.accelerometerUpdateInterval = 1.0 / 50.0;
    __weak typeof(self) weakSelf = self;
    [self.motionManager startAccelerometerUpdatesToQueue:[NSOperationQueue mainQueue]
                                             withHandler:^(CMAccelerometerData * _Nullable data, NSError * _Nullable error) {
        if (!data || error) return;
        [weakSelf handleAccelerometer:data];
    }];
}

- (void)handleAccelerometer:(CMAccelerometerData *)data {
    if (!self.isOnShortsTab) return;
    BOOL shakeEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:kPrefShakeToSkip];
    if (!shakeEnabled) return;

    double x = data.acceleration.x;
    double y = data.acceleration.y;
    double z = data.acceleration.z;
    if (!self.hasBaselineAccel) {
        self.lastAccelX = x;
        self.lastAccelY = y;
        self.lastAccelZ = z;
        self.hasBaselineAccel = YES;
        return;
    }
    double dx = x - self.lastAccelX;
    double dy = y - self.lastAccelY;
    double dz = z - self.lastAccelZ;
    self.lastAccelX = x;
    self.lastAccelY = y;
    self.lastAccelZ = z;

    double delta = sqrt(dx * dx + dy * dy + dz * dz);
    if (delta >= 1.85) {
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (now - self.lastShakeTime >= 1.3) {
            self.lastShakeTime = now;
            UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
            [gen impactOccurred];
            [self.webView evaluateJavaScript:@"window.__ytAutoShortsNext && window.__ytAutoShortsNext();" completionHandler:nil];
        }
    }
}

#pragma mark - 순정 유튜브 100% UI + 순정 쇼츠 하단 스크러빙(원하는 지점 이동) 바 + 쇼츠 자동 넘김 엔진

- (NSString *)injectedJavaScriptSource {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    BOOL autoAdv = [defs boolForKey:kPrefAutoAdvance];
    BOOL shake   = [defs boolForKey:kPrefShakeToSkip];
    BOOL pauseComm = [defs boolForKey:kPrefPauseComments];

    return [NSString stringWithFormat:@
"(function() {\n"
"  if (window.__ytPureAutoShortsInstalled) return;\n"
"  window.__ytPureAutoShortsInstalled = true;\n"
"\n"
"  const state = {\n"
"    enabled: %@,\n"
"    shake: %@,\n"
"    pauseOnComments: %@,\n"
"    isScrubbing: false,\n"
"    lastAdvanceAt: 0,\n"
"    maxRatio: 0,\n"
"    lastUrl: location.href\n"
"  };\n"
"\n"
"  // 1. 순정 유튜브 iOS 앱과 100%% 동일한 하단 시크바(Scrubber) 스타일 및 '앱에서 열기' 배너 제거\n"
"  const style = document.createElement('style');\n"
"  style.textContent = `\n"
"    ytm-mealbar-promo-renderer,\n"
"    ytm-app-promo-banner-renderer,\n"
"    .upsell-dialog-renderer,\n"
"    .open-in-app-button,\n"
"    a[href*=\"vnd.youtube\"] {\n"
"      display: none !important;\n"
"    }\n"
"    body, html {\n"
"      background-color: #0f0f0f !important;\n"
"      -webkit-user-select: none;\n"
"      -webkit-touch-callout: none;\n"
"    }\n"
"    /* 순정 유튜브 앱처럼 쇼츠 재생 중에도 하단 빨간 진행바가 항상 보이도록 활성화 */\n"
"    .ytMwebShortsPlayerControlsHostHideProgressBar {\n"
"      visibility: visible !important;\n"
"      height: 3px !important;\n"
"      opacity: 1 !important;\n"
"    }\n"
"    .ytPlayerProgressBarHostReadOnly {\n"
"      pointer-events: auto !important;\n"
"    }\n"
"    /* 하단 진행바를 손가락으로 잡고 끌 때(Scrubbing) 순정 유튜브 앱과 동일하게 바가 두꺼워지고 빨간 점이 커짐 */\n"
"    body.yt-native-scrubbing .ytMwebShortsPlayerControlsHost {\n"
"      height: 6px !important;\n"
"      visibility: visible !important;\n"
"    }\n"
"    body.yt-native-scrubbing .ytProgressBarLineProgressBarLine {\n"
"      height: 6px !important;\n"
"      border-radius: 3px !important;\n"
"    }\n"
"    body.yt-native-scrubbing .ytProgressBarPlayheadProgressBarPlayheadDot {\n"
"      transform: scale(1.35) !important;\n"
"      background-color: #ff0033 !important;\n"
"      box-shadow: 0 0 8px rgba(255, 0, 51, 0.7) !important;\n"
"    }\n"
"    /* 드래그 중에는 순정 유튜브 앱처럼 채널명/설명/우측 버튼이 살짝 투명해져 영상 프레임과 시간표시가 잘 보이게 처리 */\n"
"    body.yt-native-scrubbing .ytReelPlayerOverlayViewModelMetadataContainer,\n"
"    body.yt-native-scrubbing .ytReelPlayerOverlayViewModelActionsContainer {\n"
"      opacity: 0.12 !important;\n"
"      transition: opacity 0.15s ease !important;\n"
"    }\n"
"    /* 순정 유튜브 쇼츠 하단 드래그 시간 미리보기 캡슐 (0:14 / 0:38) */\n"
"    #yt-native-scrub-time-pill {\n"
"      position: fixed;\n"
"      bottom: 42px;\n"
"      left: 50%%;\n"
"      transform: translateX(-50%%) scale(0.92);\n"
"      background: rgba(15, 15, 15, 0.88);\n"
"      color: #ffffff;\n"
"      font-family: -apple-system, BlinkMacSystemFont, Roboto, sans-serif;\n"
"      font-size: 15px;\n"
"      font-weight: 700;\n"
"      letter-spacing: 0.3px;\n"
"      padding: 7px 16px;\n"
"      border-radius: 999px;\n"
"      pointer-events: none;\n"
"      z-index: 99999;\n"
"      opacity: 0;\n"
"      transition: opacity 0.12s ease, transform 0.12s ease;\n"
"      box-shadow: 0 4px 16px rgba(0, 0, 0, 0.45);\n"
"    }\n"
"    body.yt-native-scrubbing #yt-native-scrub-time-pill {\n"
"      opacity: 1;\n"
"      transform: translateX(-50%%) scale(1);\n"
"    }\n"
"    /* 쇼츠 하단 34px 터치 스크러빙 영역 (재생 중 일시정지 없이 언제든 바로 드래그/탭하여 원하는 지점으로 이동) */\n"
"    #yt-native-scrub-hitbox {\n"
"      position: fixed;\n"
"      left: 0;\n"
"      right: 0;\n"
"      bottom: 0;\n"
"      height: 34px;\n"
"      z-index: 99998;\n"
"      display: none;\n"
"      touch-action: none;\n"
"      -webkit-user-select: none;\n"
"    }\n"
"    body.on-shorts-route #yt-native-scrub-hitbox {\n"
"      display: block;\n"
"    }\n"
"  `;\n"
"  document.documentElement.appendChild(style);\n"
"\n"
"  function postNative(payload) {\n"
"    try {\n"
"      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.autoshorts) {\n"
"        window.webkit.messageHandlers.autoshorts.postMessage(payload);\n"
"      }\n"
"    } catch (e) {}\n"
"  }\n"
"\n"
"  function isShortsRoute() {\n"
"    return location.pathname.startsWith('/shorts');\n"
"  }\n"
"\n"
"  function formatTime(sec) {\n"
"    if (!sec || !isFinite(sec) || sec < 0) sec = 0;\n"
"    const total = Math.floor(sec);\n"
"    const m = Math.floor(total / 60);\n"
"    const s = total %% 60;\n"
"    return m + ':' + (s < 10 ? '0' + s : s);\n"
"  }\n"
"\n"
"  function getActiveVideo() {\n"
"    const videos = Array.from(document.querySelectorAll('video'));\n"
"    return videos.find(el => el.readyState >= 1 && el.offsetParent !== null) || videos[0] || null;\n"
"  }\n"
"\n"
"  // 2. 순정 유튜브 앱과 100%% 동일한 하단 터치·드래그 시크(Scrubbing) 컨트롤러 설치\n"
"  function setupNativeShortsScrubber() {\n"
"    if (document.getElementById('yt-native-scrub-hitbox')) return;\n"
"    if (!document.body) return;\n"
"\n"
"    const pill = document.createElement('div');\n"
"    pill.id = 'yt-native-scrub-time-pill';\n"
"    pill.innerHTML = '<span id=\"yt-scrub-cur\">0:00</span> <span style=\"color:#aaa;font-weight:500;\">/</span> <span id=\"yt-scrub-dur\" style=\"color:#ccc;\">0:00</span>';\n"
"    document.body.appendChild(pill);\n"
"\n"
"    const hitbox = document.createElement('div');\n"
"    hitbox.id = 'yt-native-scrub-hitbox';\n"
"    document.body.appendChild(hitbox);\n"
"\n"
"    let lastSeekTime = 0;\n"
"    let targetRatio = 0;\n"
"\n"
"    function updateScrubVisualsAndSeek(clientX, forceCommit) {\n"
"      const v = getActiveVideo();\n"
"      if (!v || !v.duration || !isFinite(v.duration) || v.duration <= 0.5) return;\n"
"\n"
"      const width = window.innerWidth || document.documentElement.clientWidth || 390;\n"
"      const pad = 12;\n"
"      const clampedX = Math.max(pad, Math.min(width - pad, clientX));\n"
"      targetRatio = Math.max(0, Math.min(0.992, (clampedX - pad) / (width - pad * 2)));\n"
"      const targetSec = targetRatio * v.duration;\n"
"\n"
"      // 진행바 UI 즉시 업데이트 (60fps)\n"
"      const pct = (targetRatio * 100).toFixed(2) + '%%';\n"
"      document.querySelectorAll('.ytProgressBarLineProgressBarPlayed').forEach(el => {\n"
"        el.style.width = pct;\n"
"      });\n"
"      document.querySelectorAll('.ytProgressBarPlayheadHost').forEach(el => {\n"
"        el.style.marginLeft = pct;\n"
"      });\n"
"\n"
"      const curEl = document.getElementById('yt-scrub-cur');\n"
"      const durEl = document.getElementById('yt-scrub-dur');\n"
"      if (curEl) curEl.textContent = formatTime(targetSec);\n"
"      if (durEl) durEl.textContent = formatTime(v.duration);\n"
"\n"
"      // 실제 비디오 시점 이동 (드래그 중 실시간 반영 + 손 뗄 때 정밀 확정)\n"
"      const now = Date.now();\n"
"      if (forceCommit || (now - lastSeekTime >= 45)) {\n"
"        lastSeekTime = now;\n"
"        try {\n"
"          v.currentTime = targetSec;\n"
"          const mp = document.getElementById('movie_player');\n"
"          if (mp && typeof mp.seekTo === 'function') {\n"
"            mp.seekTo(targetSec, true);\n"
"          }\n"
"        } catch (err) {}\n"
"      }\n"
"\n"
"      // 뒤로 되감았을 때 루프 감지가 오작동하지 않도록 maxRatio 동기화\n"
"      state.maxRatio = targetRatio;\n"
"    }\n"
"\n"
"    hitbox.addEventListener('touchstart', function(e) {\n"
"      if (!isShortsRoute() || !e.touches || !e.touches[0]) return;\n"
"      e.stopPropagation();\n"
"      e.preventDefault();\n"
"      state.isScrubbing = true;\n"
"      document.body.classList.add('yt-native-scrubbing');\n"
"      postNative({ type: 'scrubHaptic' });\n"
"      updateScrubVisualsAndSeek(e.touches[0].clientX, true);\n"
"    }, { passive: false });\n"
"\n"
"    hitbox.addEventListener('touchmove', function(e) {\n"
"      if (!state.isScrubbing || !e.touches || !e.touches[0]) return;\n"
"      e.stopPropagation();\n"
"      e.preventDefault();\n"
"      updateScrubVisualsAndSeek(e.touches[0].clientX, false);\n"
"    }, { passive: false });\n"
"\n"
"    function endScrub(e) {\n"
"      if (!state.isScrubbing) return;\n"
"      if (e) {\n"
"        e.stopPropagation();\n"
"        e.preventDefault();\n"
"      }\n"
"      if (e && e.changedTouches && e.changedTouches[0]) {\n"
"        updateScrubVisualsAndSeek(e.changedTouches[0].clientX, true);\n"
"      }\n"
"      document.body.classList.remove('yt-native-scrubbing');\n"
"      setTimeout(function() {\n"
"        state.isScrubbing = false;\n"
"      }, 220);\n"
"    }\n"
"\n"
"    hitbox.addEventListener('touchend', endScrub, { passive: false });\n"
"    hitbox.addEventListener('touchcancel', endScrub, { passive: false });\n"
"  }\n"
"\n"
"  function isCommentsOpen() {\n"
"    if (!state.pauseOnComments) return false;\n"
"    const panels = document.querySelectorAll('ytm-engagement-panel-section-list-renderer, .engagement-panel-container, [aria-modal=\"true\"]');\n"
"    for (const p of panels) {\n"
"      if (p && p.offsetParent !== null && p.getBoundingClientRect().height > 120) return true;\n"
"    }\n"
"    return false;\n"
"  }\n"
"\n"
"  window.__ytAutoShortsNext = function() {\n"
"    if (!isShortsRoute() || state.isScrubbing) return false;\n"
"    const now = Date.now();\n"
"    if (now - state.lastAdvanceAt < 1100) return false;\n"
"    if (isCommentsOpen()) return false;\n"
"\n"
"    state.lastAdvanceAt = now;\n"
"    state.maxRatio = 0;\n"
"\n"
"    const a11yBtns = document.querySelectorAll('.ytShortsCarouselShortsA11yNavButton');\n"
"    if (a11yBtns.length >= 2 && !a11yBtns[1].disabled) {\n"
"      a11yBtns[1].click();\n"
"      return true;\n"
"    }\n"
"\n"
"    const nextBtn = document.querySelector('#navigation-button-down button') ||\n"
"                    document.querySelector('button[aria-label*=\"다음 동영상\"]') ||\n"
"                    document.querySelector('button[aria-label*=\"Next video\"]');\n"
"    if (nextBtn) {\n"
"      nextBtn.click();\n"
"      return true;\n"
"    }\n"
"    return false;\n"
"  };\n"
"\n"
"  function injectIntoNativeYouTubeMenu() {\n"
"    const menus = document.querySelectorAll('ytm-menu-popup-renderer .menu-content, .bottom-sheet-media-menu-item, ytm-settings-page');\n"
"    menus.forEach(menu => {\n"
"      if (menu.querySelector('.yt-native-autoshorts-row')) return;\n"
"      const row = document.createElement('div');\n"
"      row.className = 'yt-native-autoshorts-row';\n"
"      row.style.cssText = 'display:flex;align-items:center;justify-content:space-between;padding:14px 16px;font-size:14px;color:#fff;cursor:pointer;border-top:1px solid rgba(255,255,255,0.08);';\n"
"      const render = () => {\n"
"        row.innerHTML = '<span>⚡ 쇼츠 자동 넘김</span><span style=\"color:' + (state.enabled ? '#3ea6ff' : '#888') + ';font-weight:600;\">' + (state.enabled ? '켜짐' : '꺼짐') + '</span>';\n"
"      };\n"
"      render();\n"
"      row.addEventListener('click', (e) => {\n"
"        e.stopPropagation();\n"
"        state.enabled = !state.enabled;\n"
"        render();\n"
"        postNative({ type: 'savePrefs', enabled: state.enabled });\n"
"      });\n"
"      menu.appendChild(row);\n"
"    });\n"
"  }\n"
"\n"
"  setInterval(function() {\n"
"    setupNativeShortsScrubber();\n"
"    const onShorts = isShortsRoute();\n"
"    if (document.body) {\n"
"      document.body.classList.toggle('on-shorts-route', onShorts);\n"
"    }\n"
"    postNative({ type: 'route', isShorts: onShorts });\n"
"    injectIntoNativeYouTubeMenu();\n"
"\n"
"    if (!onShorts) {\n"
"      state.maxRatio = 0;\n"
"      return;\n"
"    }\n"
"\n"
"    const unmuteBtn = document.querySelector('button.ytp-unmute');\n"
"    if (unmuteBtn && unmuteBtn.offsetParent !== null && unmuteBtn.style.display !== 'none') {\n"
"      unmuteBtn.click();\n"
"    }\n"
"\n"
"    if (state.isScrubbing) return;\n"
"\n"
"    const v = getActiveVideo();\n"
"    if (!v) return;\n"
"\n"
"    if (state.enabled && v.hasAttribute('loop')) {\n"
"      v.removeAttribute('loop');\n"
"      v.loop = false;\n"
"    }\n"
"\n"
"    const dur = v.duration;\n"
"    const cur = v.currentTime;\n"
"    if (!dur || !isFinite(dur) || dur <= 0.8) return;\n"
"\n"
"    const ratio = cur / dur;\n"
"\n"
"    // 재생 중에도 하단 빨간 진행바가 실시간으로 부드럽게 차오르도록 동기화\n"
"    const pct = Math.max(0, Math.min(100, ratio * 100)).toFixed(2) + '%%';\n"
"    document.querySelectorAll('.ytProgressBarLineProgressBarPlayed').forEach(el => {\n"
"      el.style.width = pct;\n"
"    });\n"
"    document.querySelectorAll('.ytProgressBarPlayheadHost').forEach(el => {\n"
"      el.style.marginLeft = pct;\n"
"    });\n"
"\n"
"    if (!state.enabled) return;\n"
"\n"
"    if (location.href !== state.lastUrl) {\n"
"      state.lastUrl = location.href;\n"
"      state.maxRatio = 0;\n"
"    }\n"
"\n"
"    const reachedEnd = ratio >= 0.985 || (dur - cur <= 0.22);\n"
"    const loopedBack = state.maxRatio >= 0.85 && ratio < 0.15;\n"
"\n"
"    if (reachedEnd || loopedBack) {\n"
"      window.__ytAutoShortsNext();\n"
"      return;\n"
"    }\n"
"    if (ratio > state.maxRatio) {\n"
"      state.maxRatio = ratio;\n"
"    }\n"
"  }, 100);\n"
"})();\n",
    autoAdv ? @"true" : @"false",
    shake ? @"true" : @"false",
    pauseComm ? @"true" : @"false"];
}

@end

@interface AutoShortsAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation AutoShortsAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[AutoShortsViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AutoShortsAppDelegate class]));
    }
}

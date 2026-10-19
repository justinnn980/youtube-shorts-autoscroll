#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <CoreMotion/CoreMotion.h>
#import <AVFoundation/AVFoundation.h>

static NSString * const kPrefOnboardingDone = @"AS_OnboardingDone_v1";
static NSString * const kPrefAutoAdvance    = @"AS_AutoAdvance_v1";
static NSString * const kPrefShakeToSkip    = @"AS_ShakeToSkip_v1";
static NSString * const kPrefShakeSens      = @"AS_ShakeSens_v1"; // 0: 민감, 1: 보통, 2: 둔감
static NSString * const kPrefPauseComments  = @"AS_PauseComments_v1";
static NSString * const kPrefKeepAwake      = @"AS_KeepAwake_v1";

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
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UISegmentedControl *platformSegment;
@property (nonatomic, strong) UIButton *keywordButton;
@property (nonatomic, strong) UIButton *settingsButton;
@property (nonatomic, strong) UIView *statusDot;
@property (nonatomic, strong) UILabel *toastLabel;
@property (nonatomic, strong) UIView *onboardingOverlay;

// CoreMotion (흔들어서 스킵)
@property (nonatomic, strong) CMMotionManager *motionManager;
@property (nonatomic, assign) double lastAccelX;
@property (nonatomic, assign) double lastAccelY;
@property (nonatomic, assign) double lastAccelZ;
@property (nonatomic, assign) BOOL hasBaselineAccel;
@property (nonatomic, assign) NSTimeInterval lastShakeTime;

// State
@property (nonatomic, assign) BOOL isInputOrLoginScreen;
@property (nonatomic, assign) BOOL isModalOpen;
@property (nonatomic, copy) NSString *activeKeyword;
@property (nonatomic, strong) NSTimer *sleepTimer;
@property (nonatomic, assign) NSInteger sleepMinutesRemaining;
@end

@implementation AutoShortsViewController

- (void) initializeDefaultPreferences {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    if ([defs objectForKey:kPrefAutoAdvance] == nil)   [defs setBool:YES forKey:kPrefAutoAdvance];
    if ([defs objectForKey:kPrefShakeToSkip] == nil)   [defs setBool:YES forKey:kPrefShakeToSkip];
    if ([defs objectForKey:kPrefShakeSens] == nil)     [defs setInteger:1 forKey:kPrefShakeSens];
    if ([defs objectForKey:kPrefPauseComments] == nil) [defs setBool:YES forKey:kPrefPauseComments];
    if ([defs objectForKey:kPrefKeepAwake] == nil)     [defs setBool:YES forKey:kPrefKeepAwake];
    [defs synchronize];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self initializeDefaultPreferences];
    self.view.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.06 alpha:1.0];

    // 오디오 세션 설정 (무음 모드에서도 쇼츠 사운드 정상 재생)
    NSError *audioErr = nil;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback
                                     withOptions:AVAudioSessionCategoryOptionMixWithOthers
                                           error:&audioErr];
    [[AVAudioSession sharedInstance] setActive:YES error:&audioErr];

    [self applyKeepAwakeSetting];
    [self setupTopBar];
    [self setupWebView];
    [self setupToastLabel];
    [self setupMotionManager];

    BOOL onboardingDone = [[NSUserDefaults standardUserDefaults] boolForKey:kPrefOnboardingDone];
    if (!onboardingDone) {
        [self showOnboardingOverlay];
    } else {
        [self loadYouTubeShortsHome];
    }
}

- (void)applyKeepAwakeSetting {
    BOOL keepAwake = [[NSUserDefaults standardUserDefaults] boolForKey:kPrefKeepAwake];
    [UIApplication sharedApplication].idleTimerDisabled = keepAwake;
}

#pragma mark - UI Construction

- (void)setupTopBar {
    self.topBar = [[UIView alloc] init];
    self.topBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.topBar.backgroundColor = [UIColor colorWithRed:0.06 green:0.06 blue:0.08 alpha:0.96];
    [self.view addSubview:self.topBar];

    UIView *bottomBorder = [[UIView alloc] init];
    bottomBorder.translatesAutoresizingMaskIntoConstraints = NO;
    bottomBorder.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    [self.topBar addSubview:bottomBorder];

    // 상태 표시 점 (초록 = 자동넘김 ON, 회색 = OFF)
    self.statusDot = [[UIView alloc] init];
    self.statusDot.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusDot.layer.cornerRadius = 4.0;
    [self.topBar addSubview:self.statusDot];
    [self updateStatusDot];

    // 플랫폼 전환 (YouTube 쇼츠 / 인스타 릴스)
    self.platformSegment = [[UISegmentedControl alloc] initWithItems:@[@"YouTube 쇼츠", @"릴스"]];
    self.platformSegment.translatesAutoresizingMaskIntoConstraints = NO;
    self.platformSegment.selectedSegmentIndex = 0;
    self.platformSegment.selectedSegmentTintColor = [UIColor colorWithRed:0.92 green:0.15 blue:0.20 alpha:1.0];
    [self.platformSegment setTitleTextAttributes:@{
        NSForegroundColorAttributeName: [UIColor whiteColor],
        NSFontAttributeName: [UIFont boldSystemFontOfSize:12.0]
    } forState:UIControlStateNormal];
    [self.platformSegment setTitleTextAttributes:@{
        NSForegroundColorAttributeName: [UIColor whiteColor],
        NSFontAttributeName: [UIFont boldSystemFontOfSize:12.0]
    } forState:UIControlStateSelected];
    [self.platformSegment addTarget:self action:@selector(onPlatformChanged:) forControlEvents:UIControlEventValueChanged];
    [self.topBar addSubview:self.platformSegment];

    // 키워드 이어보기 버튼
    self.keywordButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.keywordButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.keywordButton setTitle:@"🔍 키워드" forState:UIControlStateNormal];
    [self.keywordButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.keywordButton.titleLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
    self.keywordButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
    self.keywordButton.layer.cornerRadius = 14.0;
    [self.keywordButton addTarget:self action:@selector(showKeywordSheet) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.keywordButton];

    // 설정 버튼
    self.settingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.settingsButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.settingsButton setTitle:@"⚙️ 설정" forState:UIControlStateNormal];
    [self.settingsButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.settingsButton.titleLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
    self.settingsButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
    self.settingsButton.layer.cornerRadius = 14.0;
    [self.settingsButton addTarget:self action:@selector(showSettingsSheet) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.settingsButton];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.topBar.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.topBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.topBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.topBar.heightAnchor constraintEqualToConstant:44.0],

        [bottomBorder.leadingAnchor constraintEqualToAnchor:self.topBar.leadingAnchor],
        [bottomBorder.trailingAnchor constraintEqualToAnchor:self.topBar.trailingAnchor],
        [bottomBorder.bottomAnchor constraintEqualToAnchor:self.topBar.bottomAnchor],
        [bottomBorder.heightAnchor constraintEqualToConstant:0.5],

        [self.statusDot.leadingAnchor constraintEqualToAnchor:self.topBar.leadingAnchor constant:12.0],
        [self.statusDot.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
        [self.statusDot.widthAnchor constraintEqualToConstant:8.0],
        [self.statusDot.heightAnchor constraintEqualToConstant:8.0],

        [self.platformSegment.leadingAnchor constraintEqualToAnchor:self.statusDot.trailingAnchor constant:8.0],
        [self.platformSegment.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
        [self.platformSegment.heightAnchor constraintEqualToConstant:28.0],

        [self.settingsButton.trailingAnchor constraintEqualToAnchor:self.topBar.trailingAnchor constant:-10.0],
        [self.settingsButton.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
        [self.settingsButton.widthAnchor constraintGreaterThanOrEqualToConstant:64.0],
        [self.settingsButton.heightAnchor constraintEqualToConstant:28.0],

        [self.keywordButton.trailingAnchor constraintEqualToAnchor:self.settingsButton.leadingAnchor constant:-6.0],
        [self.keywordButton.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
        [self.keywordButton.widthAnchor constraintGreaterThanOrEqualToConstant:72.0],
        [self.keywordButton.heightAnchor constraintEqualToConstant:28.0]
    ]];
}

- (void)updateStatusDot {
    BOOL enabled = [[NSUserDefaults standardUserDefaults] boolForKey:kPrefAutoAdvance];
    self.statusDot.backgroundColor = enabled
        ? [UIColor colorWithRed:0.18 green:0.84 blue:0.45 alpha:1.0]
        : [UIColor colorWithWhite:0.45 alpha:1.0];
}

- (void)setupWebView {
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
    self.webView.backgroundColor = [UIColor blackColor];
    self.webView.opaque = NO;
    self.webView.scrollView.backgroundColor = [UIColor blackColor];
    self.webView.allowsBackForwardNavigationGestures = YES;
    // 모바일 Safari 표준 User-Agent 지정 (Google 계정 로그인 차단 방지 및 모바일 쇼츠 최적화)
    self.webView.customUserAgent = @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1";

    [self.view addSubview:self.webView];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.webView.topAnchor constraintEqualToAnchor:self.topBar.bottomAnchor],
        [self.webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.webView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor]
    ]];
}

- (void)setupToastLabel {
    self.toastLabel = [[UILabel alloc] init];
    self.toastLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.toastLabel.backgroundColor = [UIColor colorWithRed:0.10 green:0.10 blue:0.14 alpha:0.92];
    self.toastLabel.textColor = [UIColor whiteColor];
    self.toastLabel.font = [UIFont boldSystemFontOfSize:13.0];
    self.toastLabel.textAlignment = NSTextAlignmentCenter;
    self.toastLabel.layer.cornerRadius = 16.0;
    self.toastLabel.layer.masksToBounds = YES;
    self.toastLabel.alpha = 0.0;
    [self.view addSubview:self.toastLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.toastLabel.topAnchor constraintEqualToAnchor:self.topBar.bottomAnchor constant:12.0],
        [self.toastLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.toastLabel.heightAnchor constraintEqualToConstant:32.0],
        [self.toastLabel.widthAnchor constraintGreaterThanOrEqualToConstant:160.0]
    ]];
}

- (void)showToast:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.toastLabel.text = [NSString stringWithFormat:@"   %@   ", text];
        [UIView animateWithDuration:0.18 animations:^{
            self.toastLabel.alpha = 1.0;
        } completion:^(BOOL finished) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [UIView animateWithDuration:0.25 animations:^{
                    self.toastLabel.alpha = 0.0;
                }];
            });
        }];
    });
}

#pragma mark - First-Launch Onboarding ("스냅쇼츠" 스타일 로그인 선택 화면)

- (void)showOnboardingOverlay {
    self.isModalOpen = YES;
    self.onboardingOverlay = [[UIView alloc] init];
    self.onboardingOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    self.onboardingOverlay.backgroundColor = [UIColor colorWithRed:0.04 green:0.04 blue:0.05 alpha:1.0];
    [self.view addSubview:self.onboardingOverlay];

    [NSLayoutConstraint activateConstraints:@[
        [self.onboardingOverlay.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.onboardingOverlay.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.onboardingOverlay.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.onboardingOverlay.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 18.0;
    [self.onboardingOverlay addSubview:stack];

    // 아이콘 배지
    UILabel *logoBadge = [[UILabel alloc] init];
    logoBadge.text = @"▶️";
    logoBadge.font = [UIFont systemFontOfSize:46.0];
    logoBadge.textAlignment = NSTextAlignmentCenter;
    logoBadge.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    logoBadge.layer.cornerRadius = 24.0;
    logoBadge.layer.masksToBounds = YES;
    [logoBadge.widthAnchor constraintEqualToConstant:88.0].active = YES;
    [logoBadge.heightAnchor constraintEqualToConstant:88.0].active = YES;
    [stack addArrangedSubview:logoBadge];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"🔐 유튜브 로그인 선택";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont systemFontOfSize:24.0 weight:UIFontWeightHeavy];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [stack addArrangedSubview:titleLabel];

    UILabel *subLabel = [[UILabel alloc] init];
    subLabel.text = @"로그인 하시면 맞춤 알고리즘 쇼츠가 재생됩니다.\n영상이 끝나면 자동으로 넘어가고,\n휴대폰을 가볍게 흔들면 즉시 다음 영상으로 스킵됩니다!";
    subLabel.textColor = [UIColor colorWithWhite:0.72 alpha:1.0];
    subLabel.font = [UIFont systemFontOfSize:14.5 weight:UIFontWeightRegular];
    subLabel.textAlignment = NSTextAlignmentCenter;
    subLabel.numberOfLines = 0;
    [stack addArrangedSubview:subLabel];

    UIButton *loginBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [loginBtn setTitle:@"➔  네, 로그인할래요" forState:UIControlStateNormal];
    [loginBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    loginBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16.5];
    loginBtn.backgroundColor = [UIColor colorWithRed:0.96 green:0.32 blue:0.32 alpha:1.0];
    loginBtn.layer.cornerRadius = 26.0;
    [loginBtn.widthAnchor constraintEqualToConstant:260.0].active = YES;
    [loginBtn.heightAnchor constraintEqualToConstant:52.0].active = YES;
    [loginBtn addTarget:self action:@selector(onOnboardingLoginTapped) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:loginBtn];

    UIButton *skipBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [skipBtn setTitle:@"로그인 없이 바로 시작하기 ➔" forState:UIControlStateNormal];
    [skipBtn setTitleColor:[UIColor colorWithWhite:0.68 alpha:1.0] forState:UIControlStateNormal];
    skipBtn.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
    [skipBtn.heightAnchor constraintEqualToConstant:40.0].active = YES;
    [skipBtn addTarget:self action:@selector(onOnboardingSkipTapped) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:skipBtn];

    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:self.onboardingOverlay.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:self.onboardingOverlay.centerYAnchor],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.onboardingOverlay.leadingAnchor constant:28.0],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:self.onboardingOverlay.trailingAnchor constant:-28.0]
    ]];
}

- (void)dismissOnboarding {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kPrefOnboardingDone];
    [[NSUserDefaults standardUserDefaults] synchronize];
    self.isModalOpen = NO;
    [UIView animateWithDuration:0.25 animations:^{
        self.onboardingOverlay.alpha = 0.0;
    } completion:^(BOOL finished) {
        [self.onboardingOverlay removeFromSuperview];
        self.onboardingOverlay = nil;
    }];
}

- (void)onOnboardingLoginTapped {
    [self dismissOnboarding];
    NSURL *loginURL = [NSURL URLWithString:@"https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fm.youtube.com%2Fshorts"];
    [self.webView loadRequest:[NSURLRequest requestWithURL:loginURL]];
}

- (void)onOnboardingSkipTapped {
    [self dismissOnboarding];
    [self loadYouTubeShortsHome];
}

#pragma mark - Navigation & Platform Actions

- (void)loadYouTubeShortsHome {
    self.activeKeyword = nil;
    [self.keywordButton setTitle:@"🔍 키워드" forState:UIControlStateNormal];
    NSURL *url = [NSURL URLWithString:@"https://m.youtube.com/shorts"];
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
}

- (void)loadInstagramReels {
    self.activeKeyword = nil;
    [self.keywordButton setTitle:@"🔍 키워드" forState:UIControlStateNormal];
    NSURL *url = [NSURL URLWithString:@"https://www.instagram.com/reels/"];
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
}

- (void)onPlatformChanged:(UISegmentedControl *)seg {
    if (seg.selectedSegmentIndex == 0) {
        [self loadYouTubeShortsHome];
        [self showToast:@"📺 YouTube 쇼츠 자동 넘김 모드"];
    } else {
        [self loadInstagramReels];
        [self showToast:@"📸 Instagram 릴스 자동 넘김 모드"];
    }
}

- (void)loadKeywordShorts:(NSString *)keyword {
    if (!keyword || keyword.length == 0) {
        [self loadYouTubeShortsHome];
        return;
    }
    self.platformSegment.selectedSegmentIndex = 0;
    self.activeKeyword = keyword;
    [self.keywordButton setTitle:[NSString stringWithFormat:@"🔍 %@", keyword] forState:UIControlStateNormal];

    NSString *query = [NSString stringWithFormat:@"%@ #shorts", keyword];
    NSString *encoded = [query stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *urlStr = [NSString stringWithFormat:@"https://m.youtube.com/results?search_query=%@&autoshorts_kw=1", encoded];
    [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:urlStr]]];
    [self showToast:[NSString stringWithFormat:@"🔍 '%@' 쇼츠 이어보기 시작", keyword]];
}

#pragma mark - Keyword Sheet ("원하는 키워드만 이어보기")

- (void)showKeywordSheet {
    self.isModalOpen = YES;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"🔍 원하는 키워드 쇼츠만 이어보기"
                                                                   message:@"알고리즘에 끌려다니지 않고 선택한 주제의 쇼츠만 연속으로 자동 재생합니다."
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray<NSDictionary *> *presets = @[
        @{@"title": @"🔥 기본 알고리즘 추천 쇼츠", @"kw": @""},
        @{@"title": @"🐶 귀여운 동물 힐링 쇼츠", @"kw": @"귀여운 동물"},
        @{@"title": @"🍳 요리 · 레시피 · 먹방", @"kw": @"요리 레시피"},
        @{@"title": @"💪 운동 · 홈트 · 헬스 자극", @"kw": @"운동 홈트"},
        @{@"title": @"📚 공부 · 자기계발 · 명언", @"kw": @"공부 자극"},
        @{@"title": @"🎵 음악 · 라이브 · 플레이리스트", @"kw": @"음악 라이브"},
        @{@"title": @"🎮 게임 하이라이트", @"kw": @"게임 하이라이트"},
        @{@"title": @"😂 유머 · 예능 레전드", @"kw": @"유머 레전드"}
    ];

    for (NSDictionary *item in presets) {
        NSString *title = item[@"title"];
        NSString *kw = item[@"kw"];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            self.isModalOpen = NO;
            [self loadKeywordShorts:kw];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"✏️ 직접 키워드 입력하기..." style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self showCustomKeywordPrompt];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"닫기" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        self.isModalOpen = NO;
    }]];

    UIPopoverPresentationController *pop = sheet.popoverPresentationController;
    if (pop) {
        pop.sourceView = self.keywordButton;
        pop.sourceRect = self.keywordButton.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)showCustomKeywordPrompt {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"키워드 직접 입력"
                                                                   message:@"연속으로 감상할 쇼츠 검색어를 입력하세요."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"예: 고양이, 축구, 캠핑, 피아노";
        textField.text = self.activeKeyword ?: @"";
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"취소" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        self.isModalOpen = NO;
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"이어보기 시작" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        self.isModalOpen = NO;
        NSString *kw = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (kw.length > 0) {
            [self loadKeywordShorts:kw];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Settings Sheet ("설정 화면에서 깔끔하게 제어")

- (void)showSettingsSheet {
    self.isModalOpen = YES;
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    BOOL autoAdv = [defs boolForKey:kPrefAutoAdvance];
    BOOL shake   = [defs boolForKey:kPrefShakeToSkip];
    NSInteger sens = [defs integerForKey:kPrefShakeSens];
    BOOL pauseComm = [defs boolForKey:kPrefPauseComments];
    BOOL keepAwake = [defs boolForKey:kPrefKeepAwake];

    NSArray *sensNames = @[@"민감", @"보통", @"둔감"];
    NSString *sensLabel = (sens >= 0 && sens < 3) ? sensNames[sens] : @"보통";
    NSString *timerText = self.sleepMinutesRemaining > 0
        ? [NSString stringWithFormat:@"%ld분 남음", (long)self.sleepMinutesRemaining]
        : @"꺼짐";

    NSString *msg = [NSString stringWithFormat:
        @"현재 상태:\n"
        @"• 쇼츠 자동 넘기기: %@\n"
        @"• 흔들어서 스킵: %@ (감도: %@)\n"
        @"• 댓글 열림 시 일시정지: %@\n"
        @"• 화면 꺼짐 방지: %@\n"
        @"• 취침 타이머: %@",
        autoAdv ? @"켜짐 ✅" : @"꺼짐 ❌",
        shake ? @"켜짐 ✅" : @"꺼짐 ❌",
        sensLabel,
        pauseComm ? @"켜짐 ✅" : @"꺼짐 ❌",
        keepAwake ? @"켜짐 ✅" : @"꺼짐 ❌",
        timerText];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"⚙️ 스냅쇼츠 (AutoShorts) 설정"
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:(autoAdv ? @"🚀 쇼츠 자동 넘기기: 켜짐 (탭하여 끄기)" : @"🚀 쇼츠 자동 넘기기: 꺼짐 (탭하여 켜기)")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        self.isModalOpen = NO;
        [defs setBool:!autoAdv forKey:kPrefAutoAdvance];
        [defs synchronize];
        [self updateStatusDot];
        [self syncSettingsToWebView];
        [self showToast:(!autoAdv ? @"🚀 쇼츠 자동 넘기기 켜짐" : @"⏸ 쇼츠 자동 넘기기 꺼짐")];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:(shake ? @"👋 흔들어서 즉시 스킵: 켜짐 (탭하여 끄기)" : @"👋 흔들어서 즉시 스킵: 꺼짐 (탭하여 켜기)")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        self.isModalOpen = NO;
        [defs setBool:!shake forKey:kPrefShakeToSkip];
        [defs synchronize];
        [self showToast:(!shake ? @"👋 흔들어서 스킵 켜짐" : @"👋 흔들어서 스킵 꺼짐")];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"🎚 흔들기 감도 변경 (현재: %@)", sensLabel]
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        self.isModalOpen = NO;
        NSInteger nextSens = (sens + 1) % 3;
        [defs setInteger:nextSens forKey:kPrefShakeSens];
        [defs synchronize];
        [self showToast:[NSString stringWithFormat:@"🎚 흔들기 감도: %@", sensNames[nextSens]]];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:(pauseComm ? @"💬 댓글창 열림 시 일시정지: 켜짐" : @"💬 댓글창 열림 시 일시정지: 꺼짐")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        self.isModalOpen = NO;
        [defs setBool:!pauseComm forKey:kPrefPauseComments];
        [defs synchronize];
        [self syncSettingsToWebView];
        [self showToast:(!pauseComm ? @"💬 댓글 열림 시 자동 넘김 일시정지 켜짐" : @"💬 댓글 열림 시 일시정지 꺼짐")];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"⏰ 취침 타이머 설정 (현재: %@)", timerText]
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        self.isModalOpen = NO;
        [self cycleSleepTimer];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"🔐 유튜브 계정 로그인 / 전환"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        self.isModalOpen = NO;
        NSURL *loginURL = [NSURL URLWithString:@"https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fm.youtube.com%2Fshorts"];
        [self.webView loadRequest:[NSURLRequest requestWithURL:loginURL]];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"닫기" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        self.isModalOpen = NO;
    }]];

    UIPopoverPresentationController *pop = sheet.popoverPresentationController;
    if (pop) {
        pop.sourceView = self.settingsButton;
        pop.sourceRect = self.settingsButton.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)cycleSleepTimer {
    [self.sleepTimer invalidate];
    self.sleepTimer = nil;

    if (self.sleepMinutesRemaining == 0) {
        self.sleepMinutesRemaining = 15;
    } else if (self.sleepMinutesRemaining <= 15) {
        self.sleepMinutesRemaining = 30;
    } else if (self.sleepMinutesRemaining <= 30) {
        self.sleepMinutesRemaining = 60;
    } else {
        self.sleepMinutesRemaining = 0;
    }

    if (self.sleepMinutesRemaining > 0) {
        [self showToast:[NSString stringWithFormat:@"⏰ %ld분 후 자동 정지 타이머 켜짐", (long)self.sleepMinutesRemaining]];
        self.sleepTimer = [NSTimer scheduledTimerWithTimeInterval:60.0
                                                           target:self
                                                         selector:@selector(onSleepTimerTick)
                                                         userInfo:nil
                                                          repeats:YES];
    } else {
        [self showToast:@"⏰ 취침 타이머 해제됨"];
    }
}

- (void)onSleepTimerTick {
    self.sleepMinutesRemaining -= 1;
    if (self.sleepMinutesRemaining <= 0) {
        [self.sleepTimer invalidate];
        self.sleepTimer = nil;
        self.sleepMinutesRemaining = 0;
        [self.webView evaluateJavaScript:@"document.querySelectorAll('video').forEach(v => v.pause());" completionHandler:nil];
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        [self showToast:@"🌙 취침 타이머 종료로 영상이 일시정지되었습니다"];
    }
}

#pragma mark - CoreMotion Shake / Snap to Skip ("흔들어서 즉시 스킵")

- (void)setupMotionManager {
    self.motionManager = [[CMMotionManager alloc] init];
    if (!self.motionManager.isAccelerometerAvailable) return;

    self.motionManager.accelerometerUpdateInterval = 1.0 / 50.0;
    __weak typeof(self) weakSelf = self;
    [self.motionManager startAccelerometerUpdatesToQueue:[NSOperationQueue mainQueue]
                                             withHandler:^(CMAccelerometerData * _Nullable accelerometerData, NSError * _Nullable error) {
        if (!accelerometerData || error) return;
        [weakSelf handleAccelerometerData:accelerometerData];
    }];
}

- (void)handleAccelerometerData:(CMAccelerometerData *)data {
    BOOL shakeEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:kPrefShakeToSkip];
    if (!shakeEnabled || self.isModalOpen || self.isInputOrLoginScreen) return;

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

    NSInteger sens = [[NSUserDefaults standardUserDefaults] integerForKey:kPrefShakeSens];
    double threshold = 1.75; // 보통
    if (sens == 0) threshold = 1.35;      // 민감
    else if (sens == 2) threshold = 2.25; // 둔감

    if (delta >= threshold) {
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (now - self.lastShakeTime >= 1.25) {
            self.lastShakeTime = now;
            [self triggerShakeSkip];
        }
    }
}

- (void)triggerShakeSkip {
    UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [gen impactOccurred];
    [self showToast:@"👋 흔들어서 다음 영상으로 스킵!"];
    [self.webView evaluateJavaScript:@"window.__autoShortsNext && window.__autoShortsNext('shake');" completionHandler:nil];
}

#pragma mark - WebView & JavaScript Auto-Advance Engine

- (void)syncSettingsToWebView {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    BOOL autoAdv = [defs boolForKey:kPrefAutoAdvance];
    BOOL pauseComm = [defs boolForKey:kPrefPauseComments];
    NSString *js = [NSString stringWithFormat:
        @"if (window.__autoShortsUpdateConfig) { window.__autoShortsUpdateConfig({ enabled: %@, pauseOnComments: %@ }); }",
        autoAdv ? @"true" : @"false",
        pauseComm ? @"true" : @"false"];
    [self.webView evaluateJavaScript:js completionHandler:nil];
}

- (void)handleBridgeMessage:(WKScriptMessage *)message {
    if (![message.body isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *body = (NSDictionary *)message.body;
    NSString *type = body[@"type"];
    if ([type isEqualToString:@"state"]) {
        self.isInputOrLoginScreen = [body[@"isInputOrLogin"] boolValue];
    } else if ([type isEqualToString:@"advanced"]) {
        NSString *reason = body[@"reason"] ?: @"auto";
        if ([reason isEqualToString:@"auto"]) {
            // 조용하고 자연스럽게 넘어감
        }
    }
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [self syncSettingsToWebView];
}

- (NSString *)injectedJavaScriptSource {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    BOOL autoAdv = [defs boolForKey:kPrefAutoAdvance];
    BOOL pauseComm = [defs boolForKey:kPrefPauseComments];

    return [NSString stringWithFormat:@
"(function() {\n"
"  if (window.__autoShortsInstalled) return;\n"
"  window.__autoShortsInstalled = true;\n"
"\n"
"  const cfg = {\n"
"    enabled: %@,\n"
"    pauseOnComments: %@,\n"
"    lastAdvanceAt: 0,\n"
"    maxRatio: 0,\n"
"    lastUrl: location.href\n"
"  };\n"
"\n"
"  window.__autoShortsUpdateConfig = function(nextCfg) {\n"
"    if (typeof nextCfg.enabled === 'boolean') cfg.enabled = nextCfg.enabled;\n"
"    if (typeof nextCfg.pauseOnComments === 'boolean') cfg.pauseOnComments = nextCfg.pauseOnComments;\n"
"  };\n"
"\n"
"  function postToNative(payload) {\n"
"    try {\n"
"      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.autoshorts) {\n"
"        window.webkit.messageHandlers.autoshorts.postMessage(payload);\n"
"      }\n"
"    } catch (e) {}\n"
"  }\n"
"\n"
"  function isInputOrLogin() {\n"
"    const host = location.hostname || '';\n"
"    if (host.includes('accounts.google') || location.pathname.includes('/signin') || location.pathname.includes('/accounts/login')) {\n"
"      return true;\n"
"    }\n"
"    const el = document.activeElement;\n"
"    if (el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable)) {\n"
"      return true;\n"
"    }\n"
"    return false;\n"
"  }\n"
"\n"
"  function isCommentsOpen() {\n"
"    if (!cfg.pauseOnComments) return false;\n"
"    const panels = document.querySelectorAll('ytm-engagement-panel-section-list-renderer, .engagement-panel-container, [aria-modal=\"true\"]');\n"
"    for (const p of panels) {\n"
"      if (p && p.offsetParent !== null && p.getBoundingClientRect().height > 120) return true;\n"
"    }\n"
"    return false;\n"
"  }\n"
"\n"
"  window.__autoShortsNext = function(reason) {\n"
"    const now = Date.now();\n"
"    if (now - cfg.lastAdvanceAt < 1100) return false;\n"
"    if (reason === 'auto' && isCommentsOpen()) return false;\n"
"\n"
"    cfg.lastAdvanceAt = now;\n"
"    cfg.maxRatio = 0;\n"
"\n"
"    // 1. 모바일 YouTube Shorts 캐러셀 (shorts-carousel 내 다음 동영상 버튼)\n"
"    const a11yBtns = document.querySelectorAll('.ytShortsCarouselShortsA11yNavButton');\n"
"    if (a11yBtns.length >= 2 && !a11yBtns[1].disabled) {\n"
"      a11yBtns[1].click();\n"
"      postToNative({ type: 'advanced', reason: reason });\n"
"      return true;\n"
"    }\n"
"\n"
"    // 2. 데스크톱/태블릿 YouTube Shorts 다음 버튼\n"
"    const nextBtn = document.querySelector('#navigation-button-down button') ||\n"
"                    document.querySelector('button[aria-label*=\"다음 동영상\"]') ||\n"
"                    document.querySelector('button[aria-label*=\"Next video\"]');\n"
"    if (nextBtn) {\n"
"      nextBtn.click();\n"
"      postToNative({ type: 'advanced', reason: reason });\n"
"      return true;\n"
"    }\n"
"\n"
"    // 3. Instagram Reels 및 일반 스냅 스크롤 컨테이너\n"
"    const videos = Array.from(document.querySelectorAll('video'));\n"
"    const activeVideo = videos.find(v => v.offsetParent !== null) || videos[0];\n"
"    if (activeVideo) {\n"
"      let scroller = activeVideo.parentElement;\n"
"      while (scroller && scroller !== document.body) {\n"
"        const style = window.getComputedStyle(scroller);\n"
"        if ((style.overflowY === 'scroll' || style.overflowY === 'auto') && scroller.scrollHeight > scroller.clientHeight + 50) {\n"
"          scroller.scrollBy({ top: scroller.clientHeight, behavior: 'smooth' });\n"
"          postToNative({ type: 'advanced', reason: reason });\n"
"          return true;\n"
"        }\n"
"        scroller = scroller.parentElement;\n"
"      }\n"
"    }\n"
"\n"
"    window.scrollBy({ top: window.innerHeight * 0.9, behavior: 'smooth' });\n"
"    postToNative({ type: 'advanced', reason: reason });\n"
"    return true;\n"
"  };\n"
"\n"
"  // 키워드 검색 결과 페이지에서 첫 번째 쇼츠로 자동 진입\n"
"  function checkKeywordSearchAutoEnter() {\n"
"    if (location.pathname === '/results' && location.search.includes('autoshorts_kw=1')) {\n"
"      const firstShort = document.querySelector('a[href*=\"/shorts/\"]');\n"
"      if (firstShort && !window.__enteredKeywordShort) {\n"
"        window.__enteredKeywordShort = true;\n"
"        firstShort.click();\n"
"      }\n"
"    } else {\n"
"      window.__enteredKeywordShort = false;\n"
"    }\n"
"  }\n"
"\n"
"  setInterval(function() {\n"
"    postToNative({ type: 'state', isInputOrLogin: isInputOrLogin() });\n"
"    checkKeywordSearchAutoEnter();\n"
"\n"
"    // 모바일 유튜브 초기 음소거 해제 버튼 자동 클릭 보조\n"
"    const unmuteBtn = document.querySelector('button.ytp-unmute');\n"
"    if (unmuteBtn && unmuteBtn.offsetParent !== null && unmuteBtn.style.display !== 'none') {\n"
"      unmuteBtn.click();\n"
"    }\n"
"\n"
"    if (!cfg.enabled) return;\n"
"\n"
"    if (location.href !== cfg.lastUrl) {\n"
"      cfg.lastUrl = location.href;\n"
"      cfg.maxRatio = 0;\n"
"    }\n"
"\n"
"    const videos = Array.from(document.querySelectorAll('video'));\n"
"    const v = videos.find(el => !el.paused && el.readyState >= 2 && el.offsetParent !== null) || videos[0];\n"
"    if (!v) return;\n"
"\n"
"    if (v.hasAttribute('loop')) {\n"
"      v.removeAttribute('loop');\n"
"      v.loop = false;\n"
"    }\n"
"\n"
"    const dur = v.duration;\n"
"    const cur = v.currentTime;\n"
"    if (!dur || !isFinite(dur) || dur <= 0.8) return;\n"
"\n"
"    const ratio = cur / dur;\n"
"    const reachedEnd = ratio >= 0.985 || (dur - cur <= 0.22);\n"
"    const loopedBack = cfg.maxRatio >= 0.85 && ratio < 0.15;\n"
"\n"
"    if (reachedEnd || loopedBack) {\n"
"      window.__autoShortsNext('auto');\n"
"      return;\n"
"    }\n"
"    if (ratio > cfg.maxRatio) {\n"
"      cfg.maxRatio = ratio;\n"
"    }\n"
"  }, 140);\n"
"})();\n",
    autoAdv ? @"true" : @"false",
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

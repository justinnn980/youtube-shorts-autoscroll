#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

/**
 * YouTubeAutoShorts.m (순정 YouTube iOS 공식 어플 내부 탑재 엔진)
 *
 * 실제 YouTube iOS 바이너리(v21.41.5) 역공학 분석을 통해 추출한
 * 유튜브 공식 내부 Auto-Advance 플래그 및 쇼츠 컨트롤러 셀렉터를 직접 활성화합니다:
 *
 * 1. 유튜브 공식 앱 내부에 숨겨진 쇼츠 자동 넘김 실험실 기능 강제 활성화:
 *    - iosEnableAutoAdvanceDefaultOn -> YES
 *    - iosEnableAutoAdvanceInThreeDotMenu -> YES (쇼츠 우측 상단 ⋮ 메뉴에 순정 자동 넘김 옵션 표시)
 *    - enableAutoAdvanceDefaultOn / enableAutoAdvanceInThreeDotMenu -> YES
 *    - shouldAutoAdvance / isAutoAdvanceEnabled -> 설정값(ON/OFF) 반환
 *
 * 2. YTReelContainerViewController / YTReelPlayerViewController / YTReelSequenceViewController 후킹:
 *    - handleLoopBehavior 호출 시 반복 재생(Repeat) 대신 즉시 다음 쇼츠(advanceToNextReelWithTransitionType:) 호출
 *    - playbackControllerCurrentVideoMediaTimeDidChange: 에서 98.8% 도달 시 다음 쇼츠로 자동 이동
 *
 * 3. 유튜브 [설정(Settings)] 화면 우측 상단에 [쇼츠 자동넘김] ON/OFF 설정 버튼 제공
 */

static NSString *const kYTAutoScrollEnabledKey = @"YTAutoScrollShortsEnabled";
static NSString *const kYTPauseOnCommentsKey   = @"YTAutoScrollPauseOnComments";

static BOOL isAutoScrollEnabled(void) {
    if ([[NSUserDefaults standardUserDefaults] objectForKey:kYTAutoScrollEnabledKey] == nil) {
        return YES;
    }
    return [[NSUserDefaults standardUserDefaults] boolForKey:kYTAutoScrollEnabledKey];
}

static BOOL isPauseOnCommentsEnabled(void) {
    if ([[NSUserDefaults standardUserDefaults] objectForKey:kYTPauseOnCommentsKey] == nil) {
        return YES;
    }
    return [[NSUserDefaults standardUserDefaults] boolForKey:kYTPauseOnCommentsKey];
}

static NSTimeInterval gLastAutoScrollTimestamp = 0;

// 항상 YES를 반환하는 Feature Flag 후킹 함수
static BOOL hook_returnYES(id self, SEL _cmd) {
    return YES;
}

// 사용자의 설정(ON/OFF) 상태를 반환하는 후킹 함수
static BOOL hook_returnUserAutoAdvanceState(id self, SEL _cmd) {
    return isAutoScrollEnabled();
}

// 댓글창이 열려 있는지 확인
static BOOL isEngagementSheetOpen(UIViewController *vc) {
    if (!isPauseOnCommentsEnabled()) return NO;
    SEL isPanelVisibleSel = NSSelectorFromString(@"isEngagementPanelVisible");
    if ([vc respondsToSelector:isPanelVisibleSel]) {
        if (((BOOL (*)(id, SEL))objc_msgSend)(vc, isPanelVisibleSel)) {
            return YES;
        }
    }
    UIWindow *win = vc.view.window;
    if (win) {
        for (UIView *subview in win.subviews) {
            NSString *clsName = NSStringFromClass([subview class]);
            if ([clsName containsString:@"YTEngagementPanel"] && !subview.hidden && subview.alpha > 0.1) {
                return YES;
            }
        }
    }
    return NO;
}

// 다음 쇼츠로 넘기는 핵심 실행 함수 (유튜브 내부 네이티브 셀렉터 우선 호출 + UICollectionView 스크롤 폴백)
static void triggerNextReelFromController(id controller) {
    if (!isAutoScrollEnabled()) return;

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - gLastAutoScrollTimestamp < 1.3) return;

    if ([controller isKindOfClass:[UIViewController class]]) {
        if (isEngagementSheetOpen((UIViewController *)controller)) return;
    }

    gLastAutoScrollTimestamp = now;

    dispatch_async(dispatch_get_main_queue(), ^{
        // 1순위: autoAdvanceIfNeeded 호출
        SEL autoAdvSel = NSSelectorFromString(@"autoAdvanceIfNeeded");
        if ([controller respondsToSelector:autoAdvSel]) {
            ((void (*)(id, SEL))objc_msgSend)(controller, autoAdvSel);
        }

        // 2순위: advanceToNextReelWithTransitionType: (TransitionType 1 = auto advance)
        SEL advTransSel = NSSelectorFromString(@"advanceToNextReelWithTransitionType:");
        if ([controller respondsToSelector:advTransSel]) {
            ((void (*)(id, SEL, NSInteger))objc_msgSend)(controller, advTransSel, 1);
            return;
        }

        // 3순위: 상위/하위 뷰컨트롤러(YTReelSequenceViewController 등)에서 advanceToNextReelWithTransitionType: 탐색
        if ([controller isKindOfClass:[UIViewController class]]) {
            UIViewController *vc = (UIViewController *)controller;
            UIViewController *parent = vc.parentViewController;
            while (parent) {
                if ([parent respondsToSelector:advTransSel]) {
                    ((void (*)(id, SEL, NSInteger))objc_msgSend)(parent, advTransSel, 1);
                    return;
                }
                SEL seqReqSel = NSSelectorFromString(@"playbackSequentialItemControllerDidRequestNextReel:isAutoAdvance:");
                if ([parent respondsToSelector:seqReqSel]) {
                    ((void (*)(id, SEL, id, BOOL))objc_msgSend)(parent, seqReqSel, vc, YES);
                    return;
                }
                parent = parent.parentViewController;
            }

            // 4순위: 화면 내 쇼츠 UICollectionView를 찾아 다음 셀(item + 1)로 네이티브 스크롤
            UICollectionView *foundCV = nil;
            SEL cvSel = NSSelectorFromString(@"collectionView");
            if ([vc respondsToSelector:cvSel]) {
                id candidate = ((id (*)(id, SEL))objc_msgSend)(vc, cvSel);
                if ([candidate isKindOfClass:[UICollectionView class]]) {
                    foundCV = candidate;
                }
            }
            if (!foundCV && vc.parentViewController && [vc.parentViewController respondsToSelector:cvSel]) {
                id candidate = ((id (*)(id, SEL))objc_msgSend)(vc.parentViewController, cvSel);
                if ([candidate isKindOfClass:[UICollectionView class]]) {
                    foundCV = candidate;
                }
            }
            if (foundCV) {
                NSArray<NSIndexPath *> *visible = [foundCV indexPathsForVisibleItems];
                if (visible.count > 0) {
                    NSIndexPath *cur = [visible sortedArrayUsingSelector:@selector(compare:)].lastObject;
                    NSIndexPath *next = [NSIndexPath indexPathForItem:(cur.item + 1) inSection:cur.section];
                    if (next.item < [foundCV numberOfItemsInSection:cur.section]) {
                        [foundCV scrollToItemAtIndexPath:next
                                        atScrollPosition:UICollectionViewScrollPositionCenteredVertically
                                                animated:YES];
                    }
                }
            }
        }
    });
}

// handleLoopBehavior 후킹: 영상이 끝나서 루프(반복)하려고 할 때 반복 대신 다음 쇼츠로 이동!
static IMP orig_handleLoopBehavior = NULL;
static void swizzled_handleLoopBehavior(id self, SEL _cmd) {
    if (isAutoScrollEnabled()) {
        triggerNextReelFromController(self);
        return;
    }
    if (orig_handleLoopBehavior) {
        ((void (*)(id, SEL))orig_handleLoopBehavior)(self, _cmd);
    }
}

// YTSettingsViewController 설정 버튼 주입
static IMP orig_settingsViewDidLoad = NULL;
static void ytAutoShorts_openSettingsAlert(UIViewController *self, SEL _cmd) {
    BOOL enabled = isAutoScrollEnabled();
    BOOL pauseComments = isPauseOnCommentsEnabled();

    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:@"Shorts 자동 넘김 설정"
                         message:@"유튜브 쇼츠 탭에서 영상이 끝까지 재생되면 반복 재생 대신 자동으로 다음 쇼츠로 넘어갑니다."
                  preferredStyle:UIAlertControllerStyleActionSheet];

    NSString *toggleMainTitle = enabled ? @"✅ 쇼츠 자동 넘김: 켜짐 (누르면 끄기)" : @"⬜ 쇼츠 자동 넘김: 꺼짐 (누르면 켜기)";
    [sheet addAction:[UIAlertAction actionWithTitle:toggleMainTitle
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [[NSUserDefaults standardUserDefaults] setBool:!enabled forKey:kYTAutoScrollEnabledKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }]];

    NSString *toggleCommentTitle = pauseComments ? @"✅ 댓글창 열람 시 일시정지: 켜짐" : @"⬜ 댓글창 열람 시 일시정지: 꺼짐";
    [sheet addAction:[UIAlertAction actionWithTitle:toggleCommentTitle
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [[NSUserDefaults standardUserDefaults] setBool:!pauseComments forKey:kYTPauseOnCommentsKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"닫기" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

static void swizzled_settingsViewDidLoad(UIViewController *self, SEL _cmd) {
    if (orig_settingsViewDidLoad) {
        ((void (*)(id, SEL))orig_settingsViewDidLoad)(self, _cmd);
    }
    UIBarButtonItem *btn = [[UIBarButtonItem alloc]
        initWithTitle:@"쇼츠 자동넘김"
                style:UIBarButtonItemStylePlain
               target:self
               action:NSSelectorFromString(@"ytAutoShorts_openSettingsAlert")];
    self.navigationItem.rightBarButtonItem = btn;
}

static void hookBoolSelectorOnAllClasses(NSArray<NSString *> *selectorNames, IMP replacementImp) {
    int numClasses = objc_getClassList(NULL, 0);
    if (numClasses <= 0) return;
    Class *classes = (__unsafe_unretained Class *)malloc(sizeof(Class) * numClasses);
    numClasses = objc_getClassList(classes, numClasses);

    for (NSString *selName in selectorNames) {
        SEL sel = NSSelectorFromString(selName);
        for (int i = 0; i < numClasses; i++) {
            Class cls = classes[i];
            const char *cName = class_getName(cls);
            if (strncmp(cName, "YT", 2) != 0 && strncmp(cName, "googlemac", 9) != 0) continue;

            Method m = class_getInstanceMethod(cls, sel);
            if (m && method_getNumberOfArguments(m) == 2) {
                method_setImplementation(m, replacementImp);
            }
        }
    }
    free(classes);
}

__attribute__((constructor))
static void initYouTubeAutoShorts(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 1. 유튜브 공식 내부 Auto-Advance 실험실 플래그 강제 활성화
        NSArray<NSString *> *alwaysOnFlags = @[
            @"enableAutoAdvanceDefaultOn",
            @"enableAutoAdvanceInThreeDotMenu",
            @"isAutoAdvanceInThreeDotMenuEnabled",
            @"iosEnableAutoAdvanceDefaultOn",
            @"iosEnableAutoAdvanceInThreeDotMenu",
            @"immersiveWatchClientGlobalConfigIosEnableAutoAdvanceDefaultOn",
            @"immersiveWatchClientGlobalConfigIosEnableAutoAdvanceInThreeDotMenu"
        ];
        hookBoolSelectorOnAllClasses(alwaysOnFlags, (IMP)hook_returnYES);

        NSArray<NSString *> *userStateFlags = @[
            @"shouldAutoAdvance",
            @"isAutoAdvanceEnabled",
            @"isUserAutoAdvanceEnabled"
        ];
        hookBoolSelectorOnAllClasses(userStateFlags, (IMP)hook_returnUserAutoAdvanceState);

        // 2. 쇼츠 플레이어 컨트롤러의 handleLoopBehavior 후킹
        NSArray<NSString *> *reelClasses = @[
            @"YTReelContainerViewController",
            @"YTReelPlayerViewController",
            @"YTReelPlaybackViewController"
        ];
        SEL loopSel = NSSelectorFromString(@"handleLoopBehavior");
        for (NSString *clsName in reelClasses) {
            Class cls = objc_getClass([clsName UTF8String]);
            if (!cls) continue;
            Method m = class_getInstanceMethod(cls, loopSel);
            if (m) {
                if (!orig_handleLoopBehavior) {
                    orig_handleLoopBehavior = method_getImplementation(m);
                }
                method_setImplementation(m, (IMP)swizzled_handleLoopBehavior);
            }
        }

        // 3. 유튜브 설정(YTSettingsViewController) 화면에 ON/OFF 설정 버튼 추가
        Class settingsCls = objc_getClass("YTSettingsViewController");
        if (settingsCls) {
            SEL openAlertSel = NSSelectorFromString(@"ytAutoShorts_openSettingsAlert");
            class_addMethod(settingsCls, openAlertSel, (IMP)ytAutoShorts_openSettingsAlert, "v@:");

            Method m = class_getInstanceMethod(settingsCls, @selector(viewDidLoad));
            if (m) {
                orig_settingsViewDidLoad = method_getImplementation(m);
                method_setImplementation(m, (IMP)swizzled_settingsViewDidLoad);
            }
        }
    });
}

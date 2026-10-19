#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

/**
 * YouTubeAutoShorts (iOS 순정 YouTube 앱 내부 탑재 트윅)
 *
 * 1. 아이폰 순정 유튜브 앱의 [설정(Settings)] 메뉴 안에
 *    "쇼츠 자동 넘김 (반복 재생 방지)" ON/OFF 토글 스위치를 네이티브로 추가합니다.
 *    (영상 화면 위에 거슬리는 플로팅 버튼을 절대 띄우지 않습니다.)
 * 2. YTReelPlayerViewController(쇼츠 플레이어)에서 영상이 끝까지 재생되는 시점
 *    (또는 루프 되감기 직전)을 감지하여 자동으로 다음 쇼츠 셀로 스크롤합니다.
 */

static NSString *const kYTAutoScrollEnabledKey = @"YTAutoScrollShortsEnabled";
static NSString *const kYTPauseOnCommentsKey   = @"YTAutoScrollPauseOnComments";

static BOOL isAutoScrollEnabled(void) {
    if ([[NSUserDefaults standardUserDefaults] objectForKey:kYTAutoScrollEnabledKey] == nil) {
        return YES; // 기본값: 활성화
    }
    return [[NSUserDefaults standardUserDefaults] boolForKey:kYTAutoScrollEnabledKey];
}

static BOOL isPauseOnCommentsEnabled(void) {
    if ([[NSUserDefaults standardUserDefaults] objectForKey:kYTPauseOnCommentsKey] == nil) {
        return YES; // 기본값: 댓글창 열람 시 일시정지 활성화
    }
    return [[NSUserDefaults standardUserDefaults] boolForKey:kYTPauseOnCommentsKey];
}

#pragma mark - YouTube Internal Class Declarations

@interface YTPlayerViewController : UIViewController
- (CGFloat)currentVideoMediaTime;
- (CGFloat)currentVideoTotalMediaTime;
- (NSString *)currentVideoID;
@end

@interface YTReelPlayerViewController : UIViewController
- (YTPlayerViewController *)player;
- (UICollectionView *)collectionView;
- (void)scrollToNextReel;
- (BOOL)isEngagementPanelVisible;
@end

@interface YTSettingsSectionItem : NSObject
+ (instancetype)switchItemWithTitle:(NSString *)title
                   titleDescription:(NSString *)titleDescription
                  accessibilityIdentifier:(NSString *)accessibilityIdentifier
                             switchOn:(BOOL)switchOn
                           switchBlock:(BOOL (^)(YTSettingsCell *cell, BOOL enabled))switchBlock
                      settingItemId:(int)settingItemId;
@end

@interface YTSettingsViewController : UIViewController
- (void)setSectionItems:(NSArray *)items forCategory:(NSInteger)category title:(NSString *)title titleDescription:(NSString *)titleDescription headerHidden:(BOOL)headerHidden;
@end

#pragma mark - State Tracking for Loop Prevention

static NSString *gLastVideoID = nil;
static CGFloat gMaxProgressRatio = 0.0f;
static NSTimeInterval gLastAutoScrollTimestamp = 0;

/**
 * 현재 YTReelPlayerViewController에서 다음 쇼츠로 부드럽게 넘기는 헬퍼 함수
 */
static void advanceToNextShort(YTReelPlayerViewController *reelVC) {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - gLastAutoScrollTimestamp < 1.5) {
        return; // 중복 스크롤 방지 쿨다운
    }

    // 댓글창(Engagement Panel)이 열려 있는지 확인
    if (isPauseOnCommentsEnabled()) {
        if ([reelVC respondsToSelector:@selector(isEngagementPanelVisible)] && [reelVC isEngagementPanelVisible]) {
            return;
        }
        // 서브뷰 중 댓글 바텀시트가 열려 있는지 추가 확인
        for (UIView *subview in reelVC.view.window.subviews) {
            NSString *clsName = NSStringFromClass([subview class]);
            if ([clsName containsString:@"YTEngagementPanel"] && !subview.hidden && subview.alpha > 0.1) {
                return;
            }
        }
    }

    gLastAutoScrollTimestamp = now;
    gMaxProgressRatio = 0.0f;

    dispatch_async(dispatch_get_main_queue(), ^{
        // 1순위: 네이티브 scrollToNextReel 셀렉터가 존재하면 호출
        if ([reelVC respondsToSelector:@selector(scrollToNextReel)]) {
            [reelVC scrollToNextReel];
            return;
        }

        // 2순위: 쇼츠 UICollectionView에서 현재 인덱스 + 1로 네이티브 스크롤
        if ([reelVC respondsToSelector:@selector(collectionView)]) {
            UICollectionView *cv = [reelVC collectionView];
            if (cv) {
                NSArray<NSIndexPath *> *visible = [cv indexPathsForVisibleItems];
                if (visible.count > 0) {
                    NSIndexPath *currentPath = [visible sortedArrayUsingSelector:@selector(compare:)].lastObject;
                    NSIndexPath *nextPath = [NSIndexPath indexPathForItem:(currentPath.item + 1) inSection:currentPath.section];
                    NSInteger totalItems = [cv numberOfItemsInSection:currentPath.section];
                    if (nextPath.item < totalItems) {
                        [cv scrollToItemAtIndexPath:nextPath
                                   atScrollPosition:UICollectionViewScrollPositionCenteredVertically
                                           animated:YES];
                    }
                }
            }
        }
    });
}

#pragma mark - Hooks: YTReelPlayerViewController & YTPlayerViewController

%hook YTReelPlayerViewController

// 쇼츠 플레이어 시간 업데이트 시점 후킹
- (void)playerViewController:(YTPlayerViewController *)playerVC
    didChangeCurrentMediaTime:(CGFloat)currentTime
               totalMediaTime:(CGFloat)totalTime {
    %orig;

    if (!isAutoScrollEnabled() || totalTime <= 0.5f) {
        return;
    }

    NSString *videoID = [playerVC respondsToSelector:@selector(currentVideoID)] ? [playerVC currentVideoID] : @"";
    if (videoID && ![videoID isEqualToString:gLastVideoID]) {
        gLastVideoID = [videoID copy];
        gMaxProgressRatio = 0.0f;
    }

    CGFloat ratio = currentTime / totalTime;

    // (1) 영상이 98.8% 이상 끝까지 재생되었거나
    // (2) 85% 이상 재생된 직후 12% 미만으로 루프(되감기)된 순간 즉시 다음 쇼츠로 이동
    BOOL reachedEnd = (ratio >= 0.988f);
    BOOL loopedBack = (gMaxProgressRatio >= 0.85f && ratio < 0.12f);

    if (reachedEnd || loopedBack) {
        advanceToNextShort(self);
        return;
    }

    if (ratio > gMaxProgressRatio) {
        gMaxProgressRatio = ratio;
    }
}

%end

#pragma mark - Hooks: YouTube 순정 설정(Settings) 화면에 토글 메뉴 추가

%hook YTSettingsViewController

- (void)loadWithModel:(id)model fromView:(UIView *)view {
    %orig;

    // 우측 상단 또는 하단 설정 테이블에 '쇼츠 자동 넘김' 설정 섹션 주입
    UIBarButtonItem *autoShortsSettingBtn = [[UIBarButtonItem alloc]
        initWithTitle:@"쇼츠 자동넘김"
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(ytAutoShorts_openSettingsAlert)];
    self.navigationItem.rightBarButtonItem = autoShortsSettingBtn;
}

%new
- (void)ytAutoShorts_openSettingsAlert {
    BOOL enabled = isAutoScrollEnabled();
    BOOL pauseComments = isPauseOnCommentsEnabled();

    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:@"Shorts 자동 넘김 설정"
                         message:@"영상이 끝까지 재생되면 반복 재생되지 않고 자동으로 다음 쇼츠로 넘어갑니다."
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

%end


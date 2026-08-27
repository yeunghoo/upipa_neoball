//
//  VKMediaLoader.m
//  Runner
//
//  TopOn (AnyThink) + Facebook Audience Network 中介广告封装
//  保留原有调用场景与展示规则（冷启动保护、横幅显隐等）
//

#import "VKMediaLoader.h"
#import <AppTrackingTransparency/AppTrackingTransparency.h>
#import <AdSupport/AdSupport.h>
#import <AnyThinkSDK/AnyThinkSDK.h>

#if __has_include(<FBAudienceNetwork/FBAdSettings.h>)
#import <FBAudienceNetwork/FBAdSettings.h>
#define VK_HAS_FB_ATE 1
#else
#define VK_HAS_FB_ATE 0
#endif

@interface VKMediaLoader () <ATAdLoadingDelegate, ATBannerDelegate, ATInterstitialDelegate, ATRewardedVideoDelegate>
@end

@implementation VKMediaLoader

#pragma mark - TopOn 广告位配置

// TopOn AppID / AppKey
static NSString * const kVKTopOnAppID  = @"h6a8c10dc32e8d";
static NSString * const kVKTopOnAppKey = @"a69ce7b6e6b029709ac32db287d9d37ff";

// 广告位 ID
static NSString * const kVKBannerPlacementID      = @"n6a8c116f47819";
static NSString * const kVKInterstitialPlacementID = @"n6a8c1173f2e4e";
static NSString * const kVKRewardedPlacementID     = @"n6a8c11717d29f";

static const CGSize kVKBannerSize = {320.0, 50.0};
static const NSInteger kVKMaxRetry = 3;

#pragma mark - 状态

static NSDate *vk_startupTime;

static ATBannerView *vk_bannerView;
static UIView *vk_bannerFrame;
static BOOL vk_bannerShouldBeVisible = NO;
static BOOL vk_bannerLoading = NO;
static NSInteger vk_bannerRetry = 0;
static BOOL vk_bannerReady = NO;
static NSDate *vk_bannerCooldownUntil;

static BOOL vk_interLoading = NO;
static BOOL vk_interPresenting = NO;
static BOOL vk_interReady = NO;
static NSInteger vk_interRetry = 0;
static NSDate *vk_interCooldownUntil;

static BOOL vk_rwdLoading = NO;
static BOOL vk_rwdPresenting = NO;
static BOOL vk_rwdReady = NO;
static BOOL vk_rwdEarned = NO;
static NSInteger vk_rwdRetry = 0;
static NSDate *vk_rwdCooldownUntil;
static void (^vk_rwdHandler)(BOOL) = nil;

static NSDictionary *vk_privacyConsent;
static BOOL vk_sdkStarted = NO;

static NSMutableArray<NSString *> *vk_supportNotes;
static const NSUInteger kVKSupportNoteMaxLines = 8000;

static void VKAdLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

#pragma mark - 本次启动支持详情缓冲

+ (NSString *)vks_jsonSafeObject:(id)obj {
    if (obj == nil || obj == [NSNull null]) {
        return @"null";
    }
    if ([obj isKindOfClass:[NSString class]] ||
        [obj isKindOfClass:[NSNumber class]]) {
        return [obj description];
    }
    if ([obj isKindOfClass:[NSError class]]) {
        return [self vks_formatError:(NSError *)obj compact:YES];
    }
    if ([obj isKindOfClass:[NSDate class]]) {
        return [(NSDate *)obj description];
    }
    if ([obj isKindOfClass:[NSData class]]) {
        return [NSString stringWithFormat:@"<Data %lu bytes>", (unsigned long)[(NSData *)obj length]];
    }
    if ([obj isKindOfClass:[NSURL class]]) {
        return [(NSURL *)obj absoluteString] ?: @"";
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *items = [NSMutableArray array];
        for (id item in (NSArray *)obj) {
            [items addObject:[self vks_jsonSafeObject:item]];
        }
        return [NSString stringWithFormat:@"[%@]", [items componentsJoinedByString:@", "]];
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        return [self vks_formatDictionary:(NSDictionary *)obj];
    }
    return [obj description] ?: @"";
}

+ (NSString *)vks_formatDictionary:(NSDictionary *)dict {
    if (!dict || dict.count == 0) {
        return @"{}";
    }
    // Prefer real JSON when possible
    NSMutableDictionary *safe = [NSMutableDictionary dictionaryWithCapacity:dict.count];
    [dict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        NSString *k = [key description] ?: @"?";
        if ([obj isKindOfClass:[NSString class]] ||
            [obj isKindOfClass:[NSNumber class]] ||
            obj == [NSNull null]) {
            safe[k] = obj ?: [NSNull null];
        } else if ([obj isKindOfClass:[NSArray class]] || [obj isKindOfClass:[NSDictionary class]]) {
            // nested: stringify to keep JSONSerialization happy
            safe[k] = [self vks_jsonSafeObject:obj];
        } else if ([obj isKindOfClass:[NSError class]]) {
            safe[k] = [self vks_formatError:(NSError *)obj compact:YES];
        } else {
            safe[k] = [obj description] ?: @"";
        }
    }];
    NSError *jsonError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:safe options:0 error:&jsonError];
    if (data) {
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"{}";
    }
    return dict.description ?: @"{}";
}

+ (NSString *)vks_formatError:(NSError *)error compact:(BOOL)compact {
    if (!error) {
        return @"(nil error)";
    }
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"domain=%@ code=%ld desc=%@",
     error.domain ?: @"",
     (long)error.code,
     error.localizedDescription ?: @""];
    if (error.localizedFailureReason.length > 0) {
        [s appendFormat:@" reason=%@", error.localizedFailureReason];
    }
    if (error.localizedRecoverySuggestion.length > 0) {
        [s appendFormat:@" recovery=%@", error.localizedRecoverySuggestion];
    }
    if (error.userInfo.count > 0) {
        [s appendFormat:@" userInfo=%@", [self vks_formatDictionary:error.userInfo]];
    }
    if (!compact) {
        NSError *ue = error.userInfo[NSUnderlyingErrorKey];
        if ([ue isKindOfClass:[NSError class]]) {
            [s appendFormat:@" | underlying={%@}", [self vks_formatError:ue compact:YES]];
        }
    }
    return s;
}

+ (NSString *)vks_tagForPlacement:(NSString *)placementID {
    if ([placementID isEqualToString:kVKBannerPlacementID]) {
        return @"[横幅广告]";
    }
    if ([placementID isEqualToString:kVKInterstitialPlacementID]) {
        return @"[插页广告]";
    }
    if ([placementID isEqualToString:kVKRewardedPlacementID]) {
        return @"[激励视频]";
    }
    return @"[TopOn广告]";
}

+ (void)vks_logEvent:(NSString *)event
         placementID:(NSString *)placementID
               extra:(NSDictionary *)extra
               error:(NSError *)error {
    NSString *tag = [self vks_tagForPlacement:placementID];
    NSMutableString *line = [NSMutableString stringWithFormat:@"%@ %@ placement=%@", tag, event, placementID ?: @"-"];
    if (extra.count > 0) {
        [line appendFormat:@" extra=%@", [self vks_formatDictionary:extra]];
    }
    if (error) {
        [line appendFormat:@" error={%@}", [self vks_formatError:error compact:NO]];
    }
    VKAdLog(@"%@", line);
}

+ (void)vka_resetSupportNotes {
    if (!vk_supportNotes) {
        vk_supportNotes = [NSMutableArray array];
    } else {
        [vk_supportNotes removeAllObjects];
    }
}

+ (void)vka_appendSupportNote:(NSString *)message {
    if (message.length == 0) {
        return;
    }
    NSLog(@"%@", message);
    if (!vk_supportNotes) {
        vk_supportNotes = [NSMutableArray array];
    }
    static NSDateFormatter *fmt;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        fmt.dateFormat = @"HH:mm:ss.SSS";
    });
    NSString *line = [NSString stringWithFormat:@"[%@] %@", [fmt stringFromDate:[NSDate date]], message];
    @synchronized (self) {
        [vk_supportNotes addObject:line];
        if (vk_supportNotes.count > kVKSupportNoteMaxLines) {
            NSUInteger overflow = vk_supportNotes.count - kVKSupportNoteMaxLines;
            [vk_supportNotes removeObjectsInRange:NSMakeRange(0, overflow)];
        }
    }
}

+ (NSString *)vka_exportSupportDetails {
    NSMutableString *out = [NSMutableString string];
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"-";
    NSString *build = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"-";
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier] ?: @"-";
    UIDevice *device = [UIDevice currentDevice];
    [out appendFormat:@"Ballocity Support Details\n"];
    [out appendFormat:@"App: %@ (%@)\n", version, build];
    [out appendFormat:@"Bundle: %@\n", bundleId];
    [out appendFormat:@"Device: %@ | iOS %@\n", device.model, device.systemVersion];
    if (@available(iOS 14, *)) {
        ATTrackingManagerAuthorizationStatus status = [ATTrackingManager trackingAuthorizationStatus];
        [out appendFormat:@"ATT: %@ (%ld)\n", [self vks_attStatusText:status], (long)status];
    }
    NSString *idfa = [[[ASIdentifierManager sharedManager] advertisingIdentifier] UUIDString] ?: @"-";
    [out appendFormat:@"IDFA: %@\n", idfa];
    [out appendFormat:@"Banner: %@ | Inter: %@ | Reward: %@\n",
     kVKBannerPlacementID, kVKInterstitialPlacementID, kVKRewardedPlacementID];
    [out appendFormat:@"Exported: %@\n\n", [NSDate date]];
    @synchronized (self) {
        if (vk_supportNotes.count == 0) {
            [out appendString:@"(No details captured yet)\n"];
        } else {
            [out appendString:[vk_supportNotes componentsJoinedByString:@"\n"]];
            [out appendString:@"\n"];
        }
    }
    return [out copy];
}

static void VKAdLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void VKAdLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [VKMediaLoader vka_appendSupportNote:message];
}

#pragma mark - 单例 / GDPR

+ (instancetype)vka_sharedInstance {
    static VKMediaLoader *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

+ (void)vka_setGDPR:(NSDictionary * _Nullable)consentDictionary {
    vk_privacyConsent = consentDictionary;
    VKAdLog(@"[TopOn广告] 已设置隐私同意信息: %@", consentDictionary ?: @"nil");
}

#pragma mark - 启动

+ (void)vka_startSession {
    [self vka_resetSupportNotes];
    VKAdLog(@"[广告规则] ====== 广告系统点火初始化（TopOn + Facebook） ======");
    vk_bannerRetry = 0;
    vk_interRetry = 0;
    vk_rwdRetry = 0;
    vk_bannerLoading = NO;
    vk_interLoading = NO;
    vk_rwdLoading = NO;
    vk_interPresenting = NO;
    vk_rwdPresenting = NO;
    vk_rwdEarned = NO;
    vk_rwdHandler = nil;
    vk_bannerShouldBeVisible = NO;
    vk_bannerReady = NO;
    vk_interReady = NO;
    vk_rwdReady = NO;
    vk_bannerCooldownUntil = nil;
    vk_interCooldownUntil = nil;
    vk_rwdCooldownUntil = nil;

    vk_startupTime = [NSDate date];
    VKAdLog(@"[广告规则] 已记录应用启动时间，从此刻起2分钟(120秒)内不展示插页广告");
    VKAdLog(@"[广告规则] 开始初始化 TopOn SDK 并预加载广告（横幅/插页/激励视频）");
    [self vks_prepareSDK];
}

+ (void)vks_prepareSDK {
    if (@available(iOS 14, *)) {
        ATTrackingManagerAuthorizationStatus status = [ATTrackingManager trackingAuthorizationStatus];
        VKAdLog(@"[TopOn广告] 当前ATT状态: %@ (%ld)", [self vks_attStatusText:status], (long)status);
        if (status == ATTrackingManagerAuthorizationStatusNotDetermined) {
            VKAdLog(@"[TopOn广告] ATT未确定，延时2秒后请求授权");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [ATTrackingManager requestTrackingAuthorizationWithCompletionHandler:^(ATTrackingManagerAuthorizationStatus result) {
                    VKAdLog(@"[TopOn广告] ATT授权结果: %@ (%ld)", [self vks_attStatusText:result], (long)result);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self vks_applyFacebookATE:result];
                        [self vks_initTopOnSDK];
                    });
                }];
            });
            return;
        }
        [self vks_applyFacebookATE:status];
    } else {
        VKAdLog(@"[TopOn广告] iOS 14以下，直接初始化SDK");
    }
    [self vks_initTopOnSDK];
}

+ (void)vks_applyFacebookATE:(ATTrackingManagerAuthorizationStatus)status API_AVAILABLE(ios(14.0)) {
#if VK_HAS_FB_ATE
    BOOL enabled = (status == ATTrackingManagerAuthorizationStatusAuthorized);
    [FBAdSettings setAdvertiserTrackingEnabled:enabled];
    VKAdLog(@"[TopOn广告][Facebook] 已设置 AdvertiserTrackingEnabled=%@", enabled ? @"YES" : @"NO");
#else
    (void)status;
    VKAdLog(@"[TopOn广告][Facebook] 未找到 FBAdSettings，跳过 ATE 设置（由 TopOn Adapter 处理）");
#endif
}

+ (void)vks_initTopOnSDK {
    if (vk_sdkStarted) {
        VKAdLog(@"[TopOn广告] SDK已初始化，跳过重复初始化");
        [self vks_schedulePreload];
        return;
    }

    [ATAPI setLogEnabled:YES];
    VKAdLog(@"[TopOn广告] 开始初始化 SDK，AppID=%@ AppKey=%@", kVKTopOnAppID, kVKTopOnAppKey);

    NSError *error = nil;
    BOOL ok = [[ATAPI sharedInstance] startWithAppID:kVKTopOnAppID appKey:kVKTopOnAppKey error:&error];
    if (!ok || error) {
        VKAdLog(@"[TopOn广告] SDK初始化失败: %@", error.localizedDescription ?: @"未知错误");
    } else {
        vk_sdkStarted = YES;
        VKAdLog(@"[TopOn广告] SDK初始化成功");
#if DEBUG
        [ATAPI integrationChecking];
        VKAdLog(@"[TopOn广告] 已触发集成检查（仅 Debug）");
#endif
    }

    [self vk_mountBannerFrame];
    [self vks_schedulePreload];
}

+ (void)vks_schedulePreload {
    NSTimeInterval delay = 3.0;
    if (@available(iOS 14, *)) {
        ATTrackingManagerAuthorizationStatus status = [ATTrackingManager trackingAuthorizationStatus];
        if (status == ATTrackingManagerAuthorizationStatusDenied) {
            delay = 5.0;
            VKAdLog(@"[TopOn广告] 用户拒绝追踪，延长预加载延迟到5秒");
        } else if (status == ATTrackingManagerAuthorizationStatusNotDetermined) {
            delay = 4.0;
            VKAdLog(@"[TopOn广告] ATT未确定，延长预加载延迟到4秒");
        }
    }
    VKAdLog(@"[TopOn广告] 将在 %.1f 秒后开始预加载广告", delay);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self vks_scanAndLoad];
    });
}

#pragma mark - 预加载

+ (BOOL)vks_isCoolingDown:(NSDate * _Nullable)until tag:(NSString *)tag {
    if (!until) {
        return NO;
    }
    NSTimeInterval left = [until timeIntervalSinceNow];
    if (left <= 0) {
        return NO;
    }
    VKAdLog(@"%@ 冷却中（还需 %.0f 秒），跳过本次请求", tag, ceil(left));
    return YES;
}

+ (void)vks_scanAndLoad {
    VKAdLog(@"[TopOn广告] 开始预加载全部广告位");
    [self vkx_fetchBannerAd];
    [self vks_loadInterstitial];
    [self vks_loadRewarded];
}

+ (void)vkx_fetchBannerAd {
    if (vk_bannerLoading) {
        VKAdLog(@"[横幅广告] 正在加载中，跳过重复请求");
        return;
    }
    if ([self vks_isCoolingDown:vk_bannerCooldownUntil tag:@"[横幅广告]"]) {
        return;
    }
    UIViewController *vc = [self vks_currentVC];
    if (!vc) {
        VKAdLog(@"[横幅广告] 根控制器未就绪，3秒后重试加载");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self vkx_fetchBannerAd];
        });
        return;
    }

    vk_bannerLoading = YES;
    vk_bannerReady = NO;
    VKAdLog(@"[横幅广告] 开始加载，广告位=%@ 尺寸=%.0fx%.0f", kVKBannerPlacementID, kVKBannerSize.width, kVKBannerSize.height);

    NSMutableDictionary *extra = [NSMutableDictionary dictionary];
    [extra setValue:[NSValue valueWithCGSize:kVKBannerSize] forKey:kATAdLoadingExtraBannerAdSizeKey];

    [[ATAdManager sharedManager] loadADWithPlacementID:kVKBannerPlacementID
                                                 extra:extra
                                        viewController:vc
                                              delegate:[self vka_sharedInstance]];
}

+ (void)vks_loadInterstitial {
    if (vk_interLoading) {
        VKAdLog(@"[插页广告] 正在加载中，跳过重复请求");
        return;
    }
    if ([self vks_isCoolingDown:vk_interCooldownUntil tag:@"[插页广告]"]) {
        return;
    }
    vk_interLoading = YES;
    vk_interReady = NO;
    VKAdLog(@"[插页广告] 开始加载，广告位=%@", kVKInterstitialPlacementID);
    [[ATAdManager sharedManager] loadADWithPlacementID:kVKInterstitialPlacementID
                                                 extra:nil
                                              delegate:[self vka_sharedInstance]];
}

+ (void)vks_loadRewarded {
    if (vk_rwdLoading) {
        VKAdLog(@"[激励视频] 正在加载中，跳过重复请求");
        return;
    }
    if ([self vks_isCoolingDown:vk_rwdCooldownUntil tag:@"[激励视频]"]) {
        return;
    }
    vk_rwdLoading = YES;
    vk_rwdReady = NO;
    VKAdLog(@"[激励视频] 开始加载，广告位=%@", kVKRewardedPlacementID);
    [[ATAdManager sharedManager] loadADWithPlacementID:kVKRewardedPlacementID
                                                 extra:nil
                                              delegate:[self vka_sharedInstance]];
}

#pragma mark - 激励视频展示

+ (void)vks_emitReward:(BOOL)earned {
    void (^cb)(BOOL) = vk_rwdHandler;
    vk_rwdHandler = nil;
    vk_rwdEarned = NO;
    if (cb) {
        dispatch_async(dispatch_get_main_queue(), ^{
            VKAdLog(@"[激励视频] 回调触发，是否获得奖励=%@", earned ? @"是" : @"否");
            cb(earned);
        });
    }
}

+ (void)vka_launchReward {
    if (vk_rwdPresenting) {
        VKAdLog(@"[激励视频] 跳过展示：当前已有激励视频正在展示中");
        [self vks_emitReward:NO];
        return;
    }

    BOOL ready = [[ATAdManager sharedManager] rewardedVideoReadyForPlacementID:kVKRewardedPlacementID];
    if (!ready) {
        if (vk_rwdLoading) {
            VKAdLog(@"[激励视频] 跳过展示：广告未就绪（正在加载中），不重复请求");
        } else {
            VKAdLog(@"[激励视频] 跳过展示：广告未就绪，触发重新加载");
            [self vks_loadRewarded];
        }
        [self vks_emitReward:NO];
        return;
    }

    UIViewController *rootVC = [self vks_currentVC];
    if (!rootVC) {
        VKAdLog(@"[激励视频] 错误：无法获取有效的根视图控制器");
        [self vks_emitReward:NO];
        return;
    }
    if (!rootVC.view.window) {
        VKAdLog(@"[激励视频] 错误：根视图控制器的视图不在窗口层级中");
        [self vks_emitReward:NO];
        return;
    }

    VKAdLog(@"[激励视频] 广告已准备就绪，即将展示");
    ATShowConfig *config = [[ATShowConfig alloc] initWithScene:@"" showCustomExt:@""];
    [[ATAdManager sharedManager] showRewardedVideoWithPlacementID:kVKRewardedPlacementID
                                                           config:config
                                                 inViewController:rootVC
                                                         delegate:[self vka_sharedInstance]];
}

+ (void)vka_launchRewardCb:(void (^)(BOOL earned))completion {
    VKAdLog(@"[激励视频] 设置回调并开始播放激励视频广告");
    vk_rwdEarned = NO;
    vk_rwdHandler = [completion copy];
    [self vka_launchReward];
}

+ (bool)vka_isRwdReady {
    return [[ATAdManager sharedManager] rewardedVideoReadyForPlacementID:kVKRewardedPlacementID];
}

#pragma mark - 插页展示规则

+ (BOOL)vks_postWarmup {
    if (!vk_startupTime) {
        VKAdLog(@"[广告规则] 冷启动检查：应用启动时间未设置，视为未超过2分钟保护期");
        return NO;
    }
    NSTimeInterval sinceLaunch = [[NSDate date] timeIntervalSinceDate:vk_startupTime];
    BOOL passed = sinceLaunch >= 120.0;
    VKAdLog(@"[广告规则] 冷启动检查：距离应用启动已 %.1f 秒，需要 >= 120秒(2分钟)，结果：%@", sinceLaunch, passed ? @"通过" : @"未通过");
    return passed;
}

+ (void)vka_showInterstitial {
    VKAdLog(@"[广告规则] ====== 插页广告展示判断开始 ======");

    if (vk_interPresenting) {
        VKAdLog(@"[广告规则] 判断结果：跳过展示 - 当前已有插页广告正在展示中");
        return;
    }

    BOOL ready = [[ATAdManager sharedManager] interstitialReadyForPlacementID:kVKInterstitialPlacementID];
    if (!ready) {
        VKAdLog(@"[广告规则] 判断结果：跳过展示 - 插页广告未就绪（%@）", vk_interLoading ? @"正在加载中" : @"需要重新加载");
        if (!vk_interLoading) {
            VKAdLog(@"[广告规则] 触发重新加载插页广告");
            [self vks_loadInterstitial];
        }
        return;
    }

    NSTimeInterval sinceLaunch = vk_startupTime ? [[NSDate date] timeIntervalSinceDate:vk_startupTime] : -1.0;
    VKAdLog(@"[广告规则] 规则1检查 - 冷启动保护：距离应用启动已 %.1f 秒（需要 >= 120秒才允许展示）", sinceLaunch);
    if (![self vks_postWarmup]) {
        VKAdLog(@"[广告规则] 判断结果：跳过展示 - 应用启动后前2分钟内不显示插页广告");
        return;
    }
    VKAdLog(@"[广告规则] 规则1通过 - 已超过2分钟冷启动保护期");
    VKAdLog(@"[广告规则] 规则2检查 - 60秒冷却间隔（已取消）");

    UIViewController *rootVC = [self vks_currentVC];
    if (!rootVC) {
        VKAdLog(@"[广告规则] 判断结果：展示失败 - 无法获取有效的根视图控制器");
        return;
    }
    if (!rootVC.view.window) {
        VKAdLog(@"[广告规则] 判断结果：展示失败 - 根视图控制器的视图不在窗口层级中");
        return;
    }

    VKAdLog(@"[广告规则] 所有规则通过 - 插页广告已准备就绪，开始展示！");
    [self vks_presentInterstitialFrom:rootVC];
    VKAdLog(@"[广告规则] ====== 插页广告展示判断结束 ======");
}

+ (void)vka_pushInterstitial {
    if (vk_interPresenting) {
        VKAdLog(@"[插页广告][强制] 跳过展示：当前已有插页正在展示");
        return;
    }
    BOOL ready = [[ATAdManager sharedManager] interstitialReadyForPlacementID:kVKInterstitialPlacementID];
    if (!ready) {
        VKAdLog(@"[插页广告][强制] 未就绪：%@，跳过本次展示", vk_interLoading ? @"正在加载中" : @"需要重新加载");
        if (!vk_interLoading) {
            [self vks_loadInterstitial];
        }
        return;
    }

    UIViewController *rootVC = [self vks_currentVC];
    if (!rootVC) {
        VKAdLog(@"[插页广告][强制] 错误：无法获取有效的根视图控制器");
        return;
    }
    if (!rootVC.view.window) {
        VKAdLog(@"[插页广告][强制] 错误：根视图控制器的视图不在窗口层级中");
        return;
    }

    VKAdLog(@"[插页广告][强制] 广告已准备就绪，即将展示");
    [self vks_presentInterstitialFrom:rootVC];
}

+ (void)vks_presentInterstitialFrom:(UIViewController *)rootVC {
    ATShowConfig *config = [[ATShowConfig alloc] initWithScene:@"" showCustomExt:@""];
    [[ATAdManager sharedManager] showInterstitialWithPlacementID:kVKInterstitialPlacementID
                                                      showConfig:config
                                                inViewController:rootVC
                                                        delegate:[self vka_sharedInstance]
                                              nativeMixViewBlock:nil];
}

#pragma mark - 横幅显隐（调用场景保持不变）

+ (void)showAdBanner {
    VKAdLog(@"[横幅广告] showAdBanner 被调用，准备显示横幅");
    dispatch_async(dispatch_get_main_queue(), ^{
        vk_bannerShouldBeVisible = YES;
        UIViewController *topVC = [self vks_currentVC];
        if (!topVC) {
            VKAdLog(@"[横幅广告] 无法获取顶层视图控制器");
            return;
        }

        if (!vk_bannerFrame || vk_bannerFrame.superview != topVC.view) {
            VKAdLog(@"[横幅广告] 重新创建容器到当前视图控制器");
            if (vk_bannerFrame) {
                [vk_bannerFrame removeFromSuperview];
            }
            vk_bannerFrame = [[UIView alloc] init];
            vk_bannerFrame.translatesAutoresizingMaskIntoConstraints = NO;
            vk_bannerFrame.backgroundColor = [UIColor clearColor];
            vk_bannerFrame.clipsToBounds = YES;
            [topVC.view addSubview:vk_bannerFrame];
            [self vks_setupConstraints];
        }

        [self vks_attachBannerIfNeeded];

        if (vk_bannerFrame) {
            vk_bannerFrame.hidden = NO;
            [topVC.view bringSubviewToFront:vk_bannerFrame];
            VKAdLog(@"[横幅广告] 容器已显示");
        }

        if (!vk_bannerReady && !vk_bannerLoading) {
            if ([self vks_isCoolingDown:vk_bannerCooldownUntil tag:@"[横幅广告]"]) {
                VKAdLog(@"[横幅广告] 广告未就绪，等待冷却后自动重试（本次不强制加载）");
            } else {
                VKAdLog(@"[横幅广告] 广告未就绪，触发加载");
                [self vkx_fetchBannerAd];
            }
        }
    });
}

+ (void)vka_closeBanner {
    VKAdLog(@"[横幅广告] vka_closeBanner 被调用，隐藏横幅");
    dispatch_async(dispatch_get_main_queue(), ^{
        vk_bannerShouldBeVisible = NO;
        if (vk_bannerFrame) {
            vk_bannerFrame.hidden = YES;
            VKAdLog(@"[横幅广告] 容器已隐藏");
        }
    });
}

+ (void)vkx_raiseBanner {
    VKAdLog(@"[横幅广告] vkx_raiseBanner 被调用");
    dispatch_async(dispatch_get_main_queue(), ^{
        vk_bannerShouldBeVisible = YES;
        if (!vk_bannerFrame) {
            [self vk_mountBannerFrame];
        }
        if (vk_bannerFrame) {
            vk_bannerFrame.hidden = NO;
            [vk_bannerFrame.superview bringSubviewToFront:vk_bannerFrame];
            VKAdLog(@"[横幅广告] 安全显示横幅广告");
        }
        [self vks_attachBannerIfNeeded];
    });
}

+ (void)vks_setupConstraints {
    UIViewController *rootVC = [self vks_currentVC];
    if (!rootVC || !vk_bannerFrame) {
        VKAdLog(@"[横幅广告] 设置约束失败：rootVC或container为nil");
        return;
    }

    [vk_bannerFrame removeFromSuperview];
    [rootVC.view addSubview:vk_bannerFrame];

    [vk_bannerFrame.heightAnchor constraintEqualToConstant:kVKBannerSize.height].active = YES;
    [vk_bannerFrame.widthAnchor constraintEqualToConstant:kVKBannerSize.width].active = YES;
    [vk_bannerFrame.centerXAnchor constraintEqualToAnchor:rootVC.view.centerXAnchor].active = YES;
    if (@available(iOS 11.0, *)) {
        [vk_bannerFrame.bottomAnchor constraintEqualToAnchor:rootVC.view.safeAreaLayoutGuide.bottomAnchor].active = YES;
    } else {
        [vk_bannerFrame.bottomAnchor constraintEqualToAnchor:rootVC.view.bottomAnchor].active = YES;
    }
    VKAdLog(@"[横幅广告] 约束设置完成，容器尺寸：%.0fx%.0f", kVKBannerSize.width, kVKBannerSize.height);
}

+ (void)centerBannerView {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!vk_bannerFrame || !vk_bannerView) {
            return;
        }
        [vk_bannerFrame layoutIfNeeded];
        CGFloat cw = vk_bannerFrame.bounds.size.width ?: kVKBannerSize.width;
        CGFloat ch = vk_bannerFrame.bounds.size.height ?: kVKBannerSize.height;
        CGFloat aw = vk_bannerView.bounds.size.width ?: kVKBannerSize.width;
        CGFloat ah = vk_bannerView.bounds.size.height ?: kVKBannerSize.height;
        vk_bannerView.frame = CGRectMake((cw - aw) / 2.0, (ch - ah) / 2.0, aw, ah);
        VKAdLog(@"[横幅广告] 广告居中完成");
    });
}

+ (void)vk_mountBannerFrame {
    if (vk_bannerFrame && vk_bannerFrame.superview) {
        [self vks_attachBannerIfNeeded];
        return;
    }
    UIViewController *rootVC = [self vks_currentVC];
    if (!rootVC) {
        VKAdLog(@"[横幅广告] ensure: rootVC 尚未就绪");
        return;
    }
    vk_bannerFrame = [[UIView alloc] init];
    vk_bannerFrame.translatesAutoresizingMaskIntoConstraints = NO;
    vk_bannerFrame.backgroundColor = [UIColor clearColor];
    vk_bannerFrame.clipsToBounds = YES;
    vk_bannerFrame.hidden = !vk_bannerShouldBeVisible;
    [rootVC.view addSubview:vk_bannerFrame];
    [self vks_setupConstraints];
    [self vks_attachBannerIfNeeded];
    VKAdLog(@"[横幅广告] 容器已创建");
}

+ (void)vks_attachBannerIfNeeded {
    if (!vk_bannerView || !vk_bannerFrame) {
        return;
    }
    if (vk_bannerView.superview != vk_bannerFrame) {
        [vk_bannerView removeFromSuperview];
        vk_bannerView.translatesAutoresizingMaskIntoConstraints = NO;
        [vk_bannerFrame addSubview:vk_bannerView];
        [vk_bannerView.centerXAnchor constraintEqualToAnchor:vk_bannerFrame.centerXAnchor].active = YES;
        [vk_bannerView.centerYAnchor constraintEqualToAnchor:vk_bannerFrame.centerYAnchor].active = YES;
        [vk_bannerView.widthAnchor constraintEqualToConstant:kVKBannerSize.width].active = YES;
        [vk_bannerView.heightAnchor constraintEqualToConstant:kVKBannerSize.height].active = YES;
        VKAdLog(@"[横幅广告] Banner 视图已挂载到容器");
    }
    [self centerBannerView];
}

+ (void)vks_retrieveAndMountBanner {
    ATShowConfig *config = [[ATShowConfig alloc] initWithScene:@"" showCustomExt:@""];
    ATBannerView *banner = [[ATAdManager sharedManager] retrieveBannerViewForPlacementID:kVKBannerPlacementID
                                                                                  config:config
                                                                  nativeMixBannerViewBlock:nil];
    if (!banner) {
        // 兼容旧 API
        if ([[ATAdManager sharedManager] respondsToSelector:@selector(retrieveBannerViewForPlacementID:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            banner = [[ATAdManager sharedManager] performSelector:@selector(retrieveBannerViewForPlacementID:)
                                                       withObject:kVKBannerPlacementID];
#pragma clang diagnostic pop
        }
    }
    if (!banner) {
        VKAdLog(@"[横幅广告] retrieveBannerView 返回 nil");
        return;
    }

    if (vk_bannerView && vk_bannerView != banner) {
        [vk_bannerView removeFromSuperview];
    }
    vk_bannerView = banner;
    vk_bannerView.delegate = [self vka_sharedInstance];
    UIViewController *vc = [self vks_currentVC];
    if (vc) {
        vk_bannerView.presentingViewController = vc;
    }
    [self vk_mountBannerFrame];
    [self vks_attachBannerIfNeeded];
    if (vk_bannerFrame) {
        vk_bannerFrame.hidden = !vk_bannerShouldBeVisible;
        if (!vk_bannerFrame.hidden) {
            [vk_bannerFrame.superview bringSubviewToFront:vk_bannerFrame];
        }
    }
    VKAdLog(@"[横幅广告] Banner 视图已获取并挂载，期望可见=%@", vk_bannerShouldBeVisible ? @"是" : @"否");
}

#pragma mark - ATAdLoadingDelegate

- (void)didFinishLoadingADWithPlacementID:(NSString *)placementID {
    if ([placementID isEqualToString:kVKBannerPlacementID]) {
        VKAdLog(@"[横幅广告] 加载成功，广告位=%@", placementID);
        vk_bannerLoading = NO;
        vk_bannerReady = YES;
        vk_bannerRetry = 0;
        vk_bannerCooldownUntil = nil;
        [VKMediaLoader vks_retrieveAndMountBanner];
    } else if ([placementID isEqualToString:kVKInterstitialPlacementID]) {
        VKAdLog(@"[插页广告] 加载成功，已准备就绪，广告位=%@", placementID);
        vk_interLoading = NO;
        vk_interReady = YES;
        vk_interRetry = 0;
        vk_interCooldownUntil = nil;
    } else if ([placementID isEqualToString:kVKRewardedPlacementID]) {
        VKAdLog(@"[激励视频] 加载成功，已准备就绪，广告位=%@", placementID);
        vk_rwdLoading = NO;
        vk_rwdReady = YES;
        vk_rwdRetry = 0;
        vk_rwdCooldownUntil = nil;
    } else {
        VKAdLog(@"[TopOn广告] 未知广告位加载成功: %@", placementID);
    }
}

- (void)didFailToLoadADWithPlacementID:(NSString *)placementID error:(NSError *)error {
    NSString *tag = [VKMediaLoader vks_tagForPlacement:placementID];
    NSInteger *retryPtr = NULL;
    NSInteger adKind = 0; // 1 banner 2 inter 3 rwd
    void (^reloadBlock)(void) = nil;

    if ([placementID isEqualToString:kVKBannerPlacementID]) {
        vk_bannerLoading = NO;
        vk_bannerReady = NO;
        retryPtr = &vk_bannerRetry;
        adKind = 1;
        reloadBlock = ^{ [VKMediaLoader vkx_fetchBannerAd]; };
    } else if ([placementID isEqualToString:kVKInterstitialPlacementID]) {
        vk_interLoading = NO;
        vk_interReady = NO;
        retryPtr = &vk_interRetry;
        adKind = 2;
        reloadBlock = ^{ [VKMediaLoader vks_loadInterstitial]; };
    } else if ([placementID isEqualToString:kVKRewardedPlacementID]) {
        vk_rwdLoading = NO;
        vk_rwdReady = NO;
        retryPtr = &vk_rwdRetry;
        adKind = 3;
        reloadBlock = ^{ [VKMediaLoader vks_loadRewarded]; };
    }

    VKAdLog(@"%@ 加载失败 placement=%@ error={%@}",
            tag,
            placementID ?: @"-",
            [VKMediaLoader vks_formatError:error compact:NO]);
    [VKMediaLoader vkx_checkATTStatus];

    if (!retryPtr || !reloadBlock || adKind == 0) {
        return;
    }

    void (^applyCooldown)(NSTimeInterval) = ^(NSTimeInterval seconds) {
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:MAX(0, seconds)];
        if (adKind == 1) {
            vk_bannerCooldownUntil = until;
        } else if (adKind == 2) {
            vk_interCooldownUntil = until;
        } else if (adKind == 3) {
            vk_rwdCooldownUntil = until;
        }
    };

    // TopOn 1019：失败后短时间内禁止再次 load
    if (error.code == 1019) {
        applyCooldown(60);
        VKAdLog(@"%@ 触发 TopOn 加载频率限制(1019)，60秒后再试（不计入短重试）", tag);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            VKAdLog(@"%@ 频率限制冷却结束，重新加载", tag);
            reloadBlock();
        });
        return;
    }

    if (*retryPtr >= kVKMaxRetry) {
        applyCooldown(60);
        VKAdLog(@"%@ 已达到最大重试次数(%ld)，停止重试；后续由展示场景再触发加载", tag, (long)kVKMaxRetry);
        return;
    }
    (*retryPtr)++;
    NSInteger delaySec = (*retryPtr == 1) ? 15 : ((*retryPtr == 2) ? 30 : 60);
    applyCooldown(delaySec);
    VKAdLog(@"%@ 将在 %ld 秒后进行第 %ld 次重试", tag, (long)delaySec, (long)(*retryPtr));
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delaySec * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        VKAdLog(@"%@ 开始重试加载", tag);
        reloadBlock();
    });
}

- (void)didRevenueForPlacementID:(NSString *)placementID extra:(NSDictionary *)extra {
    [VKMediaLoader vks_logEvent:@"广告源收益回调" placementID:placementID extra:extra error:nil];
}

- (void)didStartLoadingADSourceWithPlacementID:(NSString *)placementID extra:(NSDictionary *)extra {
    [VKMediaLoader vks_logEvent:@"广告源开始加载" placementID:placementID extra:extra error:nil];
}

- (void)didFinishLoadingADSourceWithPlacementID:(NSString *)placementID extra:(NSDictionary *)extra {
    [VKMediaLoader vks_logEvent:@"广告源加载成功" placementID:placementID extra:extra error:nil];
}

- (void)didFailToLoadADSourceWithPlacementID:(NSString *)placementID extra:(NSDictionary *)extra error:(NSError *)error {
    [VKMediaLoader vks_logEvent:@"广告源加载失败" placementID:placementID extra:extra error:error];
}

- (void)didStartBiddingADSourceWithPlacementID:(NSString *)placementID extra:(NSDictionary *)extra {
    [VKMediaLoader vks_logEvent:@"竞价开始" placementID:placementID extra:extra error:nil];
}

- (void)didFinishBiddingADSourceWithPlacementID:(NSString *)placementID extra:(NSDictionary *)extra {
    [VKMediaLoader vks_logEvent:@"竞价成功" placementID:placementID extra:extra error:nil];
}

- (void)didFailBiddingADSourceWithPlacementID:(NSString *)placementID extra:(NSDictionary *)extra error:(NSError *)error {
    [VKMediaLoader vks_logEvent:@"竞价失败" placementID:placementID extra:extra error:error];
}

#pragma mark - ATBannerDelegate

- (void)bannerView:(ATBannerView *)bannerView didShowAdWithPlacementID:(NSString *)placementID extra:(NSDictionary *)extra {
    [VKMediaLoader vks_logEvent:@"横幅已展示" placementID:placementID extra:extra error:nil];
}

- (void)bannerView:(ATBannerView *)bannerView didClickWithPlacementID:(NSString *)placementID extra:(NSDictionary *)extra {
    [VKMediaLoader vks_logEvent:@"横幅被点击" placementID:placementID extra:extra error:nil];
}

- (void)bannerView:(ATBannerView *)bannerView didTapCloseButtonWithPlacementID:(NSString *)placementID extra:(NSDictionary *)extra {
    [VKMediaLoader vks_logEvent:@"横幅关闭按钮" placementID:placementID extra:extra error:nil];
    [VKMediaLoader vka_closeBanner];
}

- (void)bannerView:(ATBannerView *)bannerView didAutoRefreshWithPlacement:(NSString *)placementID extra:(NSDictionary *)extra {
    [VKMediaLoader vks_logEvent:@"横幅自动刷新成功" placementID:placementID extra:extra error:nil];
}

- (void)bannerView:(ATBannerView *)bannerView failedToAutoRefreshWithPlacementID:(NSString *)placementID error:(NSError *)error {
    [VKMediaLoader vks_logEvent:@"横幅自动刷新失败" placementID:placementID extra:nil error:error];
}

#pragma mark - ATInterstitialDelegate

- (void)interstitialDidShowForPlacementID:(NSString *)placementID extra:(NSDictionary *)extra {
    [VKMediaLoader vks_logEvent:@"插页已展示" placementID:placementID extra:extra error:nil];
    vk_interPresenting = YES;
    vk_interReady = NO;
}

- (void)interstitialFailedToShowForPlacementID:(NSString *)placementID error:(NSError *)error extra:(NSDictionary *)extra {
    [VKMediaLoader vks_logEvent:@"插页展示失败" placementID:placementID extra:extra error:error];
    vk_interPresenting = NO;
    [VKMediaLoader vks_loadInterstitial];
}

- (void)interstitialDidCloseForPlacementID:(NSString *)placementID extra:(NSDictionary *)extra {
    [VKMediaLoader vks_logEvent:@"插页已关闭" placementID:placementID extra:extra error:nil];
    vk_interPresenting = NO;
    [VKMediaLoader vks_loadInterstitial];
}

- (void)interstitialDidClickForPlacementID:(NSString *)placementID extra:(NSDictionary *)extra {
    [VKMediaLoader vks_logEvent:@"插页被点击" placementID:placementID extra:extra error:nil];
}

- (void)interstitialDidFailToPlayVideoForPlacementID:(NSString *)placementID error:(NSError *)error extra:(NSDictionary *)extra {
    [VKMediaLoader vks_logEvent:@"插页视频播放失败" placementID:placementID extra:extra error:error];
    [VKMediaLoader vks_loadInterstitial];
}

#pragma mark - ATRewardedVideoDelegate

- (void)rewardedVideoDidRewardSuccessForPlacemenID:(NSString *)placementID extra:(NSDictionary *)extra {
    [VKMediaLoader vks_logEvent:@"激励奖励发放成功" placementID:placementID extra:extra error:nil];
    vk_rwdEarned = YES;
    [VKMediaLoader _rewardCompleted];
}

- (void)rewardedVideoDidStartPlayingForPlacementID:(NSString *)placementID extra:(NSDictionary *)extra {
    [VKMediaLoader vks_logEvent:@"激励视频开始播放" placementID:placementID extra:extra error:nil];
    vk_rwdPresenting = YES;
    vk_rwdReady = NO;
}

- (void)rewardedVideoDidEndPlayingForPlacementID:(NSString *)placementID extra:(NSDictionary *)extra {
    [VKMediaLoader vks_logEvent:@"激励视频播放结束" placementID:placementID extra:extra error:nil];
}

- (void)rewardedVideoDidFailToPlayForPlacementID:(NSString *)placementID error:(NSError *)error extra:(NSDictionary *)extra {
    [VKMediaLoader vks_logEvent:@"激励视频播放失败" placementID:placementID extra:extra error:error];
    vk_rwdPresenting = NO;
    [VKMediaLoader vks_emitReward:NO];
    [VKMediaLoader _rewardErrored];
    [VKMediaLoader vks_loadRewarded];
}

- (void)rewardedVideoDidCloseForPlacementID:(NSString *)placementID rewarded:(BOOL)rewarded extra:(NSDictionary *)extra {
    BOOL earned = rewarded || vk_rwdEarned;
    VKAdLog(@"[激励视频] 用户关闭了视频，是否获得奖励: %@ extra=%@",
            earned ? @"是" : @"否",
            [VKMediaLoader vks_formatDictionary:extra ?: @{}]);
    vk_rwdPresenting = NO;
    [VKMediaLoader vks_emitReward:earned];
    [VKMediaLoader vks_loadRewarded];
}

- (void)rewardedVideoDidClickForPlacementID:(NSString *)placementID extra:(NSDictionary *)extra {
    [VKMediaLoader vks_logEvent:@"激励视频被点击" placementID:placementID extra:extra error:nil];
}

#pragma mark - 通知 / 调试

+ (void)_rewardCompleted {
    VKAdLog(@"[激励视频] 奖励完成通知已发送");
    [[NSNotificationCenter defaultCenter] postNotificationName:@"VKRewardComplete" object:nil userInfo:nil];
}

+ (void)_rewardErrored {
    VKAdLog(@"[激励视频] 奖励失败通知已发送");
    [[NSNotificationCenter defaultCenter] postNotificationName:@"VKRewardError" object:nil userInfo:nil];
}

+ (void)vka_debugBanner {
    VKAdLog(@"[横幅广告] === 状态调试 ===");
    VKAdLog(@"[横幅广告] Banner对象: %@", vk_bannerView ? @"存在" : @"nil");
    VKAdLog(@"[横幅广告] Container对象: %@", vk_bannerFrame ? @"存在" : @"nil");
    VKAdLog(@"[横幅广告] 加载中: %@ 已就绪: %@ 期望可见: %@",
          vk_bannerLoading ? @"是" : @"否",
          vk_bannerReady ? @"是" : @"否",
          vk_bannerShouldBeVisible ? @"是" : @"否");
    BOOL sdkReady = [[ATAdManager sharedManager] bannerAdReadyForPlacementID:kVKBannerPlacementID];
    VKAdLog(@"[横幅广告] TopOn Ready: %@", sdkReady ? @"是" : @"否");
    UIViewController *rootVC = [self vks_currentVC];
    VKAdLog(@"[横幅广告] 当前根视图控制器: %@", rootVC ? NSStringFromClass([rootVC class]) : @"nil");
    VKAdLog(@"[横幅广告] === 调试结束 ===");
}

#pragma mark - Helpers

+ (UIViewController *)vks_currentVC {
    __block UIViewController *rootVC = nil;
    if (@available(iOS 13.0, *)) {
        NSSet *connectedScenes = [UIApplication sharedApplication].connectedScenes;
        [connectedScenes enumerateObjectsUsingBlock:^(__kindof UIScene * _Nonnull scene, BOOL * _Nonnull stop) {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *window in windowScene.windows) {
                    if (window.isKeyWindow) {
                        rootVC = window.rootViewController;
                        *stop = YES;
                        break;
                    }
                }
            }
        }];
        if (!rootVC) {
            for (UIScene *scene in connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    UIWindowScene *windowScene = (UIWindowScene *)scene;
                    if (windowScene.windows.firstObject) {
                        rootVC = windowScene.windows.firstObject.rootViewController;
                        break;
                    }
                }
            }
        }
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
#pragma clang diagnostic pop
    }

    if (rootVC) {
        UIViewController *topVC = rootVC;
        while (topVC.presentedViewController) {
            topVC = topVC.presentedViewController;
        }
        if (topVC != rootVC) {
            VKAdLog(@"[广告] 检测到模态视图控制器，使用其作为展示容器");
            return topVC;
        }
    }
    return rootVC;
}

+ (NSString *)vks_attStatusText:(ATTrackingManagerAuthorizationStatus)status API_AVAILABLE(ios(14.0)) {
    switch (status) {
        case ATTrackingManagerAuthorizationStatusNotDetermined: return @"未确定";
        case ATTrackingManagerAuthorizationStatusRestricted: return @"受限";
        case ATTrackingManagerAuthorizationStatusDenied: return @"拒绝";
        case ATTrackingManagerAuthorizationStatusAuthorized: return @"授权";
        default: return @"未知";
    }
}

+ (void)vkx_checkATTStatus {
    if (@available(iOS 14, *)) {
        ATTrackingManagerAuthorizationStatus status = [ATTrackingManager trackingAuthorizationStatus];
        VKAdLog(@"[TopOn广告] 当前ATT状态: %@ (%ld)", [self vks_attStatusText:status], (long)status);
    }
}

@end

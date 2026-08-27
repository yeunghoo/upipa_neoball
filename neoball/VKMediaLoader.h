//
//  VKMediaLoader.h
//  Runner
//
//  TopOn (AnyThink) + Facebook Audience Network 中介广告封装
//  对外 API 保持不变，业务侧调用场景无需修改。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface VKMediaLoader : NSObject

+ (instancetype)vka_sharedInstance;
+ (void)vka_startSession;
+ (void)vka_setGDPR:(NSDictionary * _Nullable)consentDictionary;

+ (void)showAdBanner;
+ (void)vkx_raiseBanner;
+ (void)vk_mountBannerFrame;
+ (void)centerBannerView;

+ (void)vka_closeBanner;
+ (void)vka_showInterstitial;
+ (void)vka_pushInterstitial;
+ (void)vka_launchReward;
+ (void)vka_launchRewardCb:(nullable void(^)(BOOL earned))completion;
+ (bool)vka_isRwdReady;
+ (void)vka_debugBanner;

/// 记录一条本次启动的支持详情（同时写入控制台）
+ (void)vka_appendSupportNote:(NSString *)message;
/// 导出本次启动的支持详情文本，供剪贴板分享
+ (NSString *)vka_exportSupportDetails;

@end

NS_ASSUME_NONNULL_END

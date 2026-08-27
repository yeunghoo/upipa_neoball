#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NBSettingsTheme : NSObject

+ (CAGradientLayer *)applyBackgroundToView:(UIView *)view;
+ (UIView *)cardView;
+ (UILabel *)titleLabelWithText:(NSString *)text size:(CGFloat)size;
+ (UILabel *)bodyLabelWithText:(NSString *)text;
+ (void)addSoftGlowToView:(UIView *)view color:(UIColor *)color;

@end

NS_ASSUME_NONNULL_END

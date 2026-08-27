#import "NBSettingsTheme.h"

@implementation NBSettingsTheme

+ (CAGradientLayer *)applyBackgroundToView:(UIView *)view {
    view.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.12 alpha:1.0];
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = view.bounds;
    gradient.colors = @[
        (id)[UIColor colorWithRed:0.02 green:0.03 blue:0.16 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.06 green:0.03 blue:0.23 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.01 green:0.02 blue:0.10 alpha:1.0].CGColor
    ];
    gradient.locations = @[@0.0, @0.55, @1.0];
    [view.layer insertSublayer:gradient atIndex:0];
    return gradient;
}

+ (UIView *)cardView {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
    card.layer.cornerRadius = 16.0;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
    card.layer.shadowColor = [UIColor colorWithRed:0.20 green:0.74 blue:1.0 alpha:1.0].CGColor;
    card.layer.shadowOpacity = 0.22;
    card.layer.shadowRadius = 14.0;
    card.layer.shadowOffset = CGSizeZero;
    return card;
}

+ (UILabel *)titleLabelWithText:(NSString *)text size:(CGFloat)size {
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    label.numberOfLines = 0;
    label.textColor = [UIColor colorWithRed:0.74 green:0.93 blue:1.0 alpha:1.0];
    label.font = [UIFont fontWithName:@"AvenirNext-Heavy" size:size] ?: [UIFont boldSystemFontOfSize:size];
    return label;
}

+ (UILabel *)bodyLabelWithText:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    label.numberOfLines = 0;
    label.textColor = [UIColor colorWithWhite:0.90 alpha:1.0];
    label.font = [UIFont fontWithName:@"AvenirNext-Regular" size:15.0] ?: [UIFont systemFontOfSize:15.0];
    return label;
}

+ (void)addSoftGlowToView:(UIView *)view color:(UIColor *)color {
    CAGradientLayer *glow = [CAGradientLayer layer];
    glow.frame = CGRectMake(-40, -30, view.bounds.size.width + 80, view.bounds.size.height + 60);
    glow.colors = @[
        (id)[color colorWithAlphaComponent:0.20].CGColor,
        (id)[color colorWithAlphaComponent:0.02].CGColor
    ];
    glow.startPoint = CGPointMake(0.15, 0.2);
    glow.endPoint = CGPointMake(0.85, 0.8);
    glow.cornerRadius = 20.0;
    glow.zPosition = -1;
    [view.layer insertSublayer:glow atIndex:0];

    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
    pulse.fromValue = @(0.45);
    pulse.toValue = @(0.95);
    pulse.duration = 2.0;
    pulse.autoreverses = YES;
    pulse.repeatCount = HUGE_VALF;
    [glow addAnimation:pulse forKey:@"nb_glow_pulse"];
}

@end

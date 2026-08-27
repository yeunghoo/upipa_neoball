#import "AboutViewController.h"
#import "NBSettingsTheme.h"

@interface AboutViewController ()
@property (nonatomic, strong) CAGradientLayer *bgLayer;
@end

@implementation AboutViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"About Us";
    _bgLayer = [NBSettingsTheme applyBackgroundToView:self.view];

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14.0;
    [scroll addSubview:stack];

    UIView *heroCard = [NBSettingsTheme cardView];
    [NBSettingsTheme addSoftGlowToView:heroCard color:[UIColor colorWithRed:0.28 green:0.86 blue:1.0 alpha:1.0]];
    UILabel *heroTitle = [NBSettingsTheme titleLabelWithText:@"Ballocity" size:28.0];
    UILabel *heroBody = [NBSettingsTheme bodyLabelWithText:@"A neon-inspired physics arcade where every shot matters. We focus on instant fun, smooth controls, and fair challenge scaling across all iOS devices."];
    [heroCard addSubview:heroTitle];
    [heroCard addSubview:heroBody];

    UIView *missionCard = [NBSettingsTheme cardView];
    UILabel *missionTitle = [NBSettingsTheme titleLabelWithText:@"Our Mission" size:20.0];
    UILabel *missionBody = [NBSettingsTheme bodyLabelWithText:@"• Keep controls simple but skillful\n• Deliver clear visual feedback and polished motion\n• Build a game session you can enjoy in short breaks or long runs"];
    [missionCard addSubview:missionTitle];
    [missionCard addSubview:missionBody];

    UIView *contactCard = [NBSettingsTheme cardView];
    UILabel *contactTitle = [NBSettingsTheme titleLabelWithText:@"Contact" size:20.0];
    UILabel *contactBody = [NBSettingsTheme bodyLabelWithText:@"Developer Support\ncaydance_kalem253@mail.com\n\nWe read every message and use your suggestions to improve future updates."];
    [contactCard addSubview:contactTitle];
    [contactCard addSubview:contactBody];

    for (UIView *card in @[heroCard, missionCard, contactCard]) { [stack addArrangedSubview:card]; }

    NSArray<UIView *> *cards = @[heroCard, missionCard, contactCard];
    for (UIView *card in cards) {
        UILabel *t = card.subviews.firstObject;
        UILabel *b = card.subviews.lastObject;
        [NSLayoutConstraint activateConstraints:@[
            [t.topAnchor constraintEqualToAnchor:card.topAnchor constant:16.0],
            [t.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
            [t.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
            [b.topAnchor constraintEqualToAnchor:t.bottomAnchor constant:8.0],
            [b.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
            [b.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
            [b.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16.0]
        ]];
    }

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:10.0],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],

        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:8.0],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:20.0],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-20.0],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-20.0],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40.0]
    ]];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _bgLayer.frame = self.view.bounds;
}

@end

#import "PrivacyViewController.h"
#import "NBSettingsTheme.h"

@interface PrivacyViewController ()
@property (nonatomic, strong) CAGradientLayer *bgLayer;
@end

@implementation PrivacyViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Privacy Policy";
    _bgLayer = [NBSettingsTheme applyBackgroundToView:self.view];

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14.0;
    [scroll addSubview:stack];

    NSArray<NSArray<NSString *> *> *sections = @[
        @[@"Data We Store", @"Ballocity stores gameplay preferences and local score progress on your device to provide a smoother experience."],
        @[@"No External Links Here", @"This privacy screen intentionally contains no jump links. All information is presented directly in-app for clarity."],
        @[@"No Mandatory Sign-up", @"You can play without account registration. We do not require profile creation to access core gameplay."],
        @[@"Contact for Privacy", @"For privacy concerns and data questions, contact caydance_kalem253@mail.com."]
    ];

    for (NSArray<NSString *> *entry in sections) {
        UIView *card = [NBSettingsTheme cardView];
        UILabel *t = [NBSettingsTheme titleLabelWithText:entry[0] size:19.0];
        UILabel *b = [NBSettingsTheme bodyLabelWithText:entry[1]];
        [card addSubview:t];
        [card addSubview:b];
        [stack addArrangedSubview:card];
        [NSLayoutConstraint activateConstraints:@[
            [t.topAnchor constraintEqualToAnchor:card.topAnchor constant:15.0],
            [t.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:15.0],
            [t.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-15.0],
            [b.topAnchor constraintEqualToAnchor:t.bottomAnchor constant:8.0],
            [b.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:15.0],
            [b.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-15.0],
            [b.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-15.0]
        ]];
    }

    [NBSettingsTheme addSoftGlowToView:stack.arrangedSubviews.firstObject color:[UIColor colorWithRed:0.52 green:0.76 blue:1.0 alpha:1.0]];

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

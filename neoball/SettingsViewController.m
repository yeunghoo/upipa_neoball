#import "SettingsViewController.h"
#import "AboutViewController.h"
#import "TermsViewController.h"
#import "PrivacyViewController.h"
#import "FeedbackViewController.h"
#import "NBSettingsTheme.h"
#import "VKMediaLoader.h"

static NSString * const kNBSupportEmail = @"caydance_kalem253@mail.com";

@interface SettingsViewController ()
@property (nonatomic, strong) CAGradientLayer *bgLayer;
@property (nonatomic, strong) UIButton *detailsButton;
@property (nonatomic, strong) UILabel *detailsStatusLabel;
@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupNav];
    [self setupBackground];
    [self setupContent];
}

- (void)setupNav {
    self.title = @"Settings";
    self.navigationController.navigationBar.tintColor = [UIColor colorWithRed:0.68 green:0.92 blue:1.0 alpha:1.0];
    self.navigationController.navigationBar.barTintColor = [UIColor colorWithRed:0.03 green:0.03 blue:0.14 alpha:1.0];
    self.navigationController.navigationBar.titleTextAttributes = @{
        NSForegroundColorAttributeName: [UIColor colorWithRed:0.80 green:0.95 blue:1.0 alpha:1.0],
        NSFontAttributeName: [UIFont fontWithName:@"AvenirNext-DemiBold" size:18.0] ?: [UIFont boldSystemFontOfSize:18.0]
    };
    self.navigationController.navigationBar.translucent = YES;
    UIBarButtonItem *close = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                            target:self
                                                                            action:@selector(closeTapped)];
    self.navigationItem.leftBarButtonItem = close;
}

- (void)setupBackground {
    _bgLayer = [NBSettingsTheme applyBackgroundToView:self.view];
}

- (UIButton *)menuButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor colorWithRed:0.86 green:0.95 blue:1.0 alpha:1.0] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont fontWithName:@"AvenirNext-DemiBold" size:18.0] ?: [UIFont systemFontOfSize:18.0 weight:UIFontWeightSemibold];
    btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    btn.contentEdgeInsets = UIEdgeInsetsMake(0, 18, 0, 18);
    btn.layer.cornerRadius = 16.0;
    btn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.14];
    btn.layer.borderWidth = 1.0;
    btn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.24].CGColor;
    btn.layer.shadowColor = [UIColor colorWithRed:0.29 green:0.84 blue:1.0 alpha:1.0].CGColor;
    btn.layer.shadowOpacity = 0.25;
    btn.layer.shadowRadius = 10.0;
    btn.layer.shadowOffset = CGSizeZero;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)setupContent {
    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    scroll.showsVerticalScrollIndicator = NO;
    [self.view addSubview:scroll];

    UIView *content = [[UIView alloc] init];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:content];

    UILabel *titleLabel = [NBSettingsTheme titleLabelWithText:@"Ballocity" size:30.0];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [content addSubview:titleLabel];

    UILabel *subtitle = [NBSettingsTheme bodyLabelWithText:@"Support, legal pages, and player feedback center"];
    subtitle.textAlignment = NSTextAlignmentCenter;
    [content addSubview:subtitle];

    UIView *stackCard = [NBSettingsTheme cardView];
    [content addSubview:stackCard];
    [NBSettingsTheme addSoftGlowToView:stackCard color:[UIColor colorWithRed:0.36 green:0.78 blue:1.0 alpha:1.0]];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 16.0;
    stack.distribution = UIStackViewDistributionFillEqually;
    [stackCard addSubview:stack];

    UIButton *aboutBtn = [self menuButtonWithTitle:@"About Us  ·  Team & Vision" action:@selector(openAbout)];
    UIButton *termsBtn = [self menuButtonWithTitle:@"Terms of Service  ·  Usage Rules" action:@selector(openTerms)];
    UIButton *privacyBtn = [self menuButtonWithTitle:@"Privacy Policy  ·  Data Handling" action:@selector(openPrivacy)];
    UIButton *feedbackBtn = [self menuButtonWithTitle:@"Feedback  ·  Send Suggestions" action:@selector(openFeedback)];
    [stack addArrangedSubview:aboutBtn];
    [stack addArrangedSubview:termsBtn];
    [stack addArrangedSubview:privacyBtn];
    [stack addArrangedSubview:feedbackBtn];

    UIView *helpCard = [NBSettingsTheme cardView];
    [content addSubview:helpCard];

    UILabel *helpTitle = [NBSettingsTheme titleLabelWithText:@"Need a hand?" size:18.0];
    [helpCard addSubview:helpTitle];

    UILabel *helpBody = [NBSettingsTheme bodyLabelWithText:
        [NSString stringWithFormat:
         @"If something isn’t working right, please copy the details and email them to us at %@. A little extra context helps us help you much faster.",
         kNBSupportEmail]];
    helpBody.font = [UIFont fontWithName:@"AvenirNext-Regular" size:13.0] ?: [UIFont systemFontOfSize:13.0];
    helpBody.textColor = [UIColor colorWithWhite:0.78 alpha:1.0];
    [helpCard addSubview:helpBody];

    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [copyBtn setTitle:@"Copy Details" forState:UIControlStateNormal];
    [copyBtn setTitleColor:[UIColor colorWithRed:0.08 green:0.12 blue:0.22 alpha:1.0] forState:UIControlStateNormal];
    copyBtn.titleLabel.font = [UIFont fontWithName:@"AvenirNext-DemiBold" size:16.0] ?: [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    copyBtn.backgroundColor = [UIColor colorWithRed:0.62 green:0.90 blue:1.0 alpha:1.0];
    copyBtn.layer.cornerRadius = 14.0;
    copyBtn.contentEdgeInsets = UIEdgeInsetsMake(12, 16, 12, 16);
    [copyBtn addTarget:self action:@selector(copySupportDetailsTapped) forControlEvents:UIControlEventTouchUpInside];
    [helpCard addSubview:copyBtn];
    self.detailsButton = copyBtn;

    UILabel *status = [[UILabel alloc] init];
    status.translatesAutoresizingMaskIntoConstraints = NO;
    status.textAlignment = NSTextAlignmentCenter;
    status.numberOfLines = 0;
    status.font = [UIFont fontWithName:@"AvenirNext-Medium" size:12.0] ?: [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    status.textColor = [UIColor colorWithRed:0.55 green:0.92 blue:0.72 alpha:1.0];
    status.alpha = 0.0;
    [helpCard addSubview:status];
    self.detailsStatusLabel = status;

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [content.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [content.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [content.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [content.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],

        [titleLabel.topAnchor constraintEqualToAnchor:content.topAnchor constant:24.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20.0],
        [titleLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20.0],

        [subtitle.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8.0],
        [subtitle.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [subtitle.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],

        [stackCard.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:24.0],
        [stackCard.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20.0],
        [stackCard.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20.0],

        [stack.topAnchor constraintEqualToAnchor:stackCard.topAnchor constant:16.0],
        [stack.leadingAnchor constraintEqualToAnchor:stackCard.leadingAnchor constant:14.0],
        [stack.trailingAnchor constraintEqualToAnchor:stackCard.trailingAnchor constant:-14.0],
        [stack.bottomAnchor constraintEqualToAnchor:stackCard.bottomAnchor constant:-16.0],
        [stack.heightAnchor constraintEqualToConstant:4 * 60 + 3 * 16],

        [helpCard.topAnchor constraintEqualToAnchor:stackCard.bottomAnchor constant:20.0],
        [helpCard.leadingAnchor constraintEqualToAnchor:stackCard.leadingAnchor],
        [helpCard.trailingAnchor constraintEqualToAnchor:stackCard.trailingAnchor],
        [helpCard.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-28.0],

        [helpTitle.topAnchor constraintEqualToAnchor:helpCard.topAnchor constant:16.0],
        [helpTitle.leadingAnchor constraintEqualToAnchor:helpCard.leadingAnchor constant:16.0],
        [helpTitle.trailingAnchor constraintEqualToAnchor:helpCard.trailingAnchor constant:-16.0],

        [helpBody.topAnchor constraintEqualToAnchor:helpTitle.bottomAnchor constant:8.0],
        [helpBody.leadingAnchor constraintEqualToAnchor:helpTitle.leadingAnchor],
        [helpBody.trailingAnchor constraintEqualToAnchor:helpTitle.trailingAnchor],

        [copyBtn.topAnchor constraintEqualToAnchor:helpBody.bottomAnchor constant:14.0],
        [copyBtn.leadingAnchor constraintEqualToAnchor:helpTitle.leadingAnchor],
        [copyBtn.trailingAnchor constraintEqualToAnchor:helpTitle.trailingAnchor],
        [copyBtn.heightAnchor constraintEqualToConstant:46.0],

        [status.topAnchor constraintEqualToAnchor:copyBtn.bottomAnchor constant:10.0],
        [status.leadingAnchor constraintEqualToAnchor:helpTitle.leadingAnchor],
        [status.trailingAnchor constraintEqualToAnchor:helpTitle.trailingAnchor],
        [status.bottomAnchor constraintEqualToAnchor:helpCard.bottomAnchor constant:-14.0]
    ]];
}

- (void)copySupportDetailsTapped {
    NSString *details = [VKMediaLoader vka_exportSupportDetails];
    if (details.length == 0) {
        return;
    }
    UIPasteboard.generalPasteboard.string = details;

    self.detailsStatusLabel.text = @"✓ Copied — paste into your email";
    self.detailsStatusLabel.alpha = 1.0;
    [self.detailsButton setTitle:@"Copied" forState:UIControlStateNormal];
    self.detailsButton.enabled = NO;

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        [self.detailsButton setTitle:@"Copy Details" forState:UIControlStateNormal];
        self.detailsButton.enabled = YES;
        [UIView animateWithDuration:0.25 animations:^{
            self.detailsStatusLabel.alpha = 0.0;
        }];
    });
}

- (void)pushWithSoftTransition:(UIViewController *)vc {
    CATransition *transition = [CATransition animation];
    transition.type = kCATransitionPush;
    transition.subtype = kCATransitionFromRight;
    transition.duration = 0.24;
    transition.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.navigationController.view.layer addAnimation:transition forKey:@"nb_page_push"];
    [self.navigationController pushViewController:vc animated:NO];
}

- (void)openAbout { [self pushWithSoftTransition:[[AboutViewController alloc] init]]; }
- (void)openTerms { [self pushWithSoftTransition:[[TermsViewController alloc] init]]; }
- (void)openPrivacy { [self pushWithSoftTransition:[[PrivacyViewController alloc] init]]; }
- (void)openFeedback { [self pushWithSoftTransition:[[FeedbackViewController alloc] init]]; }

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _bgLayer.frame = self.view.bounds;
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

@end

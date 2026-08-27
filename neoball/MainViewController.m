#import "MainViewController.h"
#import "GameViewController.h"
#import "SettingsViewController.h"

@interface MainViewController ()
@property (nonatomic, strong) UILabel *bestScoreLabel;
@end

@implementation MainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupBackground];
    [self setupStarfield];
    [self setupUI];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshBestScore];
}

- (void)setupBackground {
    self.view.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.12 alpha:1.0];

    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = self.view.bounds;
    gradient.colors = @[
        (id)[UIColor colorWithRed:0.02 green:0.02 blue:0.14 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.05 green:0.03 blue:0.20 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.02 green:0.02 blue:0.12 alpha:1.0].CGColor
    ];
    gradient.locations = @[@0.0, @0.6, @1.0];
    [self.view.layer insertSublayer:gradient atIndex:0];
}

- (void)setupStarfield {
    srand48(99);
    for (int i = 0; i < 140; i++) {
        CGFloat x = drand48() * self.view.bounds.size.width;
        CGFloat y = drand48() * self.view.bounds.size.height;
        BOOL isBig = (drand48() < 0.15);
        CGFloat size = isBig ? 2.5 : 1.0;
        CGFloat alpha = 0.2 + drand48() * 0.6;

        UIView *star = [[UIView alloc] initWithFrame:CGRectMake(x, y, size, size)];
        star.backgroundColor = isBig
            ? [UIColor colorWithRed:0.7 green:0.9 blue:1.0 alpha:alpha]
            : [UIColor colorWithWhite:1.0 alpha:alpha];
        star.layer.cornerRadius = size / 2.0;
        [self.view addSubview:star];

        CABasicAnimation *twinkle = [CABasicAnimation animationWithKeyPath:@"opacity"];
        twinkle.fromValue = @(alpha);
        twinkle.toValue = @(alpha * 0.1);
        twinkle.duration = 1.2 + drand48() * 2.5;
        twinkle.autoreverses = YES;
        twinkle.repeatCount = HUGE_VALF;
        twinkle.beginTime = CACurrentMediaTime() + drand48() * 4.0;
        [star.layer addAnimation:twinkle forKey:@"twinkle"];
    }
}

- (void)setupUI {
    UIButton *settingsButton = [self buildSettingsButton];
    [self.view addSubview:settingsButton];

    UIImageView *logoView = [[UIImageView alloc] init];
    logoView.image = [UIImage imageNamed:@"AppLogo"];
    logoView.contentMode = UIViewContentModeScaleAspectFit;
    logoView.layer.cornerRadius = 18.0;
    logoView.clipsToBounds = YES;
    logoView.layer.shadowColor = [UIColor colorWithRed:0.2 green:0.7 blue:1.0 alpha:1.0].CGColor;
    logoView.layer.shadowRadius = 16.0;
    logoView.layer.shadowOpacity = 0.8;
    logoView.layer.shadowOffset = CGSizeZero;
    logoView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:logoView];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"Ballocity";
    titleLabel.font = [UIFont fontWithName:@"AvenirNext-Heavy" size:34.0]
                   ?: [UIFont boldSystemFontOfSize:34.0];
    titleLabel.textColor = [UIColor colorWithRed:0.2 green:0.82 blue:1.0 alpha:1.0];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.adjustsFontSizeToFitWidth = YES;
    titleLabel.minimumScaleFactor = 0.7;
    titleLabel.layer.shadowColor = [UIColor colorWithRed:0.0 green:0.7 blue:1.0 alpha:1.0].CGColor;
    titleLabel.layer.shadowRadius = 18.0;
    titleLabel.layer.shadowOpacity = 1.0;
    titleLabel.layer.shadowOffset = CGSizeZero;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:titleLabel];

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.text = @"PHYSICS BALL BREAKER";
    subtitleLabel.font = [UIFont fontWithName:@"AvenirNext-DemiBold" size:13.0]
                      ?: [UIFont systemFontOfSize:13.0];
    subtitleLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];
    subtitleLabel.textAlignment = NSTextAlignmentCenter;
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:subtitleLabel];

    // Divider line
    UIView *divider = [[UIView alloc] init];
    divider.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:0.8 alpha:0.3];
    divider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:divider];

    // Best score
    _bestScoreLabel = [[UILabel alloc] init];
    _bestScoreLabel.font = [UIFont fontWithName:@"AvenirNext-DemiBold" size:15.0]
                        ?: [UIFont systemFontOfSize:15.0];
    _bestScoreLabel.textColor = [UIColor colorWithRed:1.0 green:0.82 blue:0.0 alpha:1.0];
    _bestScoreLabel.textAlignment = NSTextAlignmentCenter;
    _bestScoreLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_bestScoreLabel];

    // Play button
    UIButton *playButton = [self buildPlayButton];
    [self.view addSubview:playButton];

    // How to play hint
    UILabel *hintLabel = [[UILabel alloc] init];
    hintLabel.text = @"Aim · Shoot · Break · Survive";
    hintLabel.font = [UIFont fontWithName:@"AvenirNext-Regular" size:13.0]
                  ?: [UIFont systemFontOfSize:13.0];
    hintLabel.textColor = [UIColor colorWithWhite:0.35 alpha:1.0];
    hintLabel.textAlignment = NSTextAlignmentCenter;
    hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:hintLabel];

    CGFloat logoSize = MIN(self.view.bounds.size.width * 0.18, 80.0);

    [NSLayoutConstraint activateConstraints:@[
        [settingsButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8.0],
        [settingsButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-14.0],
        [settingsButton.widthAnchor constraintEqualToConstant:42.0],
        [settingsButton.heightAnchor constraintEqualToConstant:42.0],

        [logoView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [logoView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:44.0],
        [logoView.widthAnchor constraintEqualToConstant:logoSize],
        [logoView.heightAnchor constraintEqualToConstant:logoSize],

        [titleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [titleLabel.topAnchor constraintEqualToAnchor:logoView.bottomAnchor constant:16.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20.0],
        [titleLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20.0],

        [subtitleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:6.0],

        [divider.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [divider.topAnchor constraintEqualToAnchor:subtitleLabel.bottomAnchor constant:20.0],
        [divider.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:0.5],
        [divider.heightAnchor constraintEqualToConstant:1.0],

        [_bestScoreLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_bestScoreLabel.topAnchor constraintEqualToAnchor:divider.bottomAnchor constant:18.0],

        [playButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [playButton.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:50.0],
        [playButton.widthAnchor constraintEqualToConstant:200.0],
        [playButton.heightAnchor constraintEqualToConstant:64.0],

        [hintLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [hintLabel.topAnchor constraintEqualToAnchor:playButton.bottomAnchor constant:20.0],
    ]];
}

- (UIButton *)buildSettingsButton {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.14];
    btn.layer.cornerRadius = 21.0;
    btn.layer.borderWidth = 1.0;
    btn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
    btn.tintColor = [UIColor colorWithRed:0.67 green:0.91 blue:1.0 alpha:1.0];
    btn.layer.shadowColor = [UIColor colorWithRed:0.3 green:0.82 blue:1.0 alpha:1.0].CGColor;
    btn.layer.shadowRadius = 10.0;
    btn.layer.shadowOpacity = 0.45;
    btn.layer.shadowOffset = CGSizeZero;
    if (@available(iOS 13.0, *)) {
        UIImage *gear = [UIImage systemImageNamed:@"gearshape.fill"];
        [btn setImage:gear forState:UIControlStateNormal];
    } else {
        [btn setTitle:@"SET" forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    }
    [btn addTarget:self action:@selector(settingsTapped) forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (UIButton *)buildPlayButton {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    [btn setTitle:@"PLAY" forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor colorWithRed:0.03 green:0.05 blue:0.18 alpha:1.0] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont fontWithName:@"AvenirNext-Heavy" size:28.0]
                       ?: [UIFont boldSystemFontOfSize:28.0];
    btn.backgroundColor = [UIColor colorWithRed:0.18 green:0.80 blue:1.0 alpha:1.0];
    btn.layer.cornerRadius = 32.0;
    btn.layer.shadowColor = [UIColor colorWithRed:0.0 green:0.75 blue:1.0 alpha:1.0].CGColor;
    btn.layer.shadowRadius = 22.0;
    btn.layer.shadowOpacity = 0.85;
    btn.layer.shadowOffset = CGSizeZero;
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn addTarget:self action:@selector(playTapped) forControlEvents:UIControlEventTouchUpInside];
    [btn addTarget:self action:@selector(playButtonHighlight:) forControlEvents:UIControlEventTouchDown];
    [btn addTarget:self action:@selector(playButtonNormal:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];

    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"shadowRadius"];
    pulse.fromValue = @(22.0);
    pulse.toValue = @(38.0);
    pulse.duration = 1.3;
    pulse.autoreverses = YES;
    pulse.repeatCount = HUGE_VALF;
    [btn.layer addAnimation:pulse forKey:@"shadowPulse"];

    CABasicAnimation *scalePulse = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    scalePulse.fromValue = @(1.0);
    scalePulse.toValue = @(1.04);
    scalePulse.duration = 1.3;
    scalePulse.autoreverses = YES;
    scalePulse.repeatCount = HUGE_VALF;
    scalePulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [btn.layer addAnimation:scalePulse forKey:@"scalePulse"];

    return btn;
}

- (void)playButtonHighlight:(UIButton *)btn {
    [UIView animateWithDuration:0.1 animations:^{
        btn.transform = CGAffineTransformMakeScale(0.96, 0.96);
    }];
}

- (void)playButtonNormal:(UIButton *)btn {
    [UIView animateWithDuration:0.15 animations:^{
        btn.transform = CGAffineTransformIdentity;
    }];
}

- (void)refreshBestScore {
    NSInteger best = [[NSUserDefaults standardUserDefaults] integerForKey:@"NBBestScore"];
    if (best > 0) {
        _bestScoreLabel.text = [NSString stringWithFormat:@"Best Score: %ld", (long)best];
    } else {
        _bestScoreLabel.text = @"No records yet — be the first!";
    }
}

- (void)playTapped {
    GameViewController *gameVC = [[GameViewController alloc] init];
    gameVC.modalPresentationStyle = UIModalPresentationFullScreen;
    gameVC.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self presentViewController:gameVC animated:YES completion:nil];
}

- (void)settingsTapped {
    SettingsViewController *settingsVC = [[SettingsViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    nav.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self presentViewController:nav animated:YES completion:nil];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

@end

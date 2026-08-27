#import "SplashViewController.h"
#import "MainViewController.h"

@interface SplashViewController ()
@end

@implementation SplashViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupBackground];
    [self setupStars];
    [self setupContent];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self transitionToMain];
    });
}

- (void)setupBackground {
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = self.view.bounds;
    gradient.colors = @[
        (id)[UIColor colorWithRed:0.02 green:0.02 blue:0.14 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.04 green:0.04 blue:0.22 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.02 green:0.02 blue:0.12 alpha:1.0].CGColor
    ];
    gradient.locations = @[@0.0, @0.5, @1.0];
    [self.view.layer insertSublayer:gradient atIndex:0];
}

- (void)setupStars {
    srand48(42);
    for (int i = 0; i < 120; i++) {
        CGFloat x = drand48() * self.view.bounds.size.width;
        CGFloat y = drand48() * self.view.bounds.size.height;
        CGFloat size = (drand48() < 0.3) ? 2.0 : 1.0;
        CGFloat alpha = 0.2 + drand48() * 0.6;

        UIView *star = [[UIView alloc] initWithFrame:CGRectMake(x, y, size, size)];
        star.backgroundColor = [UIColor colorWithWhite:1.0 alpha:alpha];
        star.layer.cornerRadius = size / 2.0;
        [self.view addSubview:star];

        if (drand48() < 0.4) {
            CABasicAnimation *twinkle = [CABasicAnimation animationWithKeyPath:@"opacity"];
            twinkle.fromValue = @(alpha);
            twinkle.toValue = @(alpha * 0.15);
            twinkle.duration = 1.0 + drand48() * 2.0;
            twinkle.autoreverses = YES;
            twinkle.repeatCount = HUGE_VALF;
            twinkle.beginTime = CACurrentMediaTime() + drand48() * 3.0;
            [star.layer addAnimation:twinkle forKey:@"twinkle"];
        }
    }
}

- (void)setupContent {
    UIImageView *iconView = [[UIImageView alloc] init];
    iconView.image = [UIImage imageNamed:@"AppLogo"];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.layer.cornerRadius = 26.0;
    iconView.clipsToBounds = YES;
    iconView.alpha = 0;
    iconView.transform = CGAffineTransformMakeScale(0.4, 0.4);
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    // Neon glow ring
    iconView.layer.shadowColor = [UIColor colorWithRed:0.2 green:0.7 blue:1.0 alpha:1.0].CGColor;
    iconView.layer.shadowRadius = 20.0;
    iconView.layer.shadowOpacity = 0.9;
    iconView.layer.shadowOffset = CGSizeZero;
    [self.view addSubview:iconView];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"Ballocity";
    titleLabel.font = [UIFont fontWithName:@"AvenirNext-Heavy" size:34.0]
                   ?: [UIFont boldSystemFontOfSize:34.0];
    titleLabel.textColor = [UIColor colorWithRed:0.25 green:0.82 blue:1.0 alpha:1.0];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.alpha = 0;
    titleLabel.layer.shadowColor = [UIColor colorWithRed:0.0 green:0.75 blue:1.0 alpha:1.0].CGColor;
    titleLabel.layer.shadowRadius = 14.0;
    titleLabel.layer.shadowOpacity = 1.0;
    titleLabel.layer.shadowOffset = CGSizeZero;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:titleLabel];

    UILabel *taglineLabel = [[UILabel alloc] init];
    taglineLabel.text = @"THE ULTIMATE PHYSICS BALL GAME";
    taglineLabel.font = [UIFont fontWithName:@"AvenirNext-DemiBold" size:12.0]
                     ?: [UIFont systemFontOfSize:12.0];
    taglineLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    taglineLabel.textAlignment = NSTextAlignmentCenter;
    taglineLabel.alpha = 0;
    taglineLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:taglineLabel];

    UIActivityIndicatorView *spinner;
    spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.color = [UIColor colorWithRed:0.3 green:0.7 blue:1.0 alpha:0.8];
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [spinner startAnimating];
    [self.view addSubview:spinner];

    [NSLayoutConstraint activateConstraints:@[
        [iconView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-50.0],
        [iconView.widthAnchor constraintEqualToConstant:120.0],
        [iconView.heightAnchor constraintEqualToConstant:120.0],

        [titleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [titleLabel.topAnchor constraintEqualToAnchor:iconView.bottomAnchor constant:28.0],

        [taglineLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [taglineLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:10.0],

        [spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [spinner.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-50.0],
    ]];

    [UIView animateWithDuration:0.7 delay:0.1
         usingSpringWithDamping:0.65
          initialSpringVelocity:0.6
                        options:0
                     animations:^{
        iconView.alpha = 1.0;
        iconView.transform = CGAffineTransformIdentity;
    } completion:nil];

    [UIView animateWithDuration:0.6 delay:0.5
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        titleLabel.alpha = 1.0;
        taglineLabel.alpha = 1.0;
    } completion:nil];
}

- (void)transitionToMain {
    MainViewController *mainVC = [[MainViewController alloc] init];
    mainVC.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    mainVC.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:mainVC animated:YES completion:nil];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

@end

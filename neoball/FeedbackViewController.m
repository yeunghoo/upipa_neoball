#import "FeedbackViewController.h"
#import "NBSettingsTheme.h"

static NSString * const kFeedbackPlaceholder =
    @"Describe bugs, balance ideas, or anything you’d like to see in Ballocity…";

@interface FeedbackViewController () <UITextViewDelegate>
@property (nonatomic, strong) UITextView *inputViewBox;
@property (nonatomic, strong) CAGradientLayer *bgLayer;
@end

@implementation FeedbackViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Feedback";
    _bgLayer = [NBSettingsTheme applyBackgroundToView:self.view];
    [self setupUI];
}

- (void)setupUI {
    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14.0;
    [scroll addSubview:stack];

    UIView *introCard = [NBSettingsTheme cardView];
    [NBSettingsTheme addSoftGlowToView:introCard color:[UIColor colorWithRed:0.34 green:0.84 blue:1.0 alpha:1.0]];
    UILabel *hint = [NBSettingsTheme titleLabelWithText:@"Tell us what we can improve" size:22.0];
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *sub = [NBSettingsTheme bodyLabelWithText:@"Your ideas help shape better controls, clearer visuals, and more satisfying gameplay updates."];
    [introCard addSubview:hint];
    [introCard addSubview:sub];
    [stack addArrangedSubview:introCard];

    UIView *formCard = [NBSettingsTheme cardView];
    [stack addArrangedSubview:formCard];

    _inputViewBox = [[UITextView alloc] init];
    _inputViewBox.translatesAutoresizingMaskIntoConstraints = NO;
    _inputViewBox.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    _inputViewBox.font = [UIFont fontWithName:@"AvenirNext-Regular" size:16.0] ?: [UIFont systemFontOfSize:16.0];
    _inputViewBox.layer.cornerRadius = 12.0;
    _inputViewBox.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.2].CGColor;
    _inputViewBox.layer.borderWidth = 1.0;
    _inputViewBox.textContainerInset = UIEdgeInsetsMake(14, 12, 14, 12);
    _inputViewBox.delegate = self;
    _inputViewBox.text = kFeedbackPlaceholder;
    _inputViewBox.textColor = [UIColor colorWithWhite:0.50 alpha:1.0];
    [formCard addSubview:_inputViewBox];

    UIButton *sendBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    sendBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [sendBtn setTitle:@"Send Feedback" forState:UIControlStateNormal];
    [sendBtn setTitleColor:[UIColor colorWithRed:0.02 green:0.06 blue:0.16 alpha:1.0] forState:UIControlStateNormal];
    sendBtn.titleLabel.font = [UIFont fontWithName:@"AvenirNext-Heavy" size:18.0] ?: [UIFont boldSystemFontOfSize:18.0];
    sendBtn.backgroundColor = [UIColor colorWithRed:0.25 green:0.84 blue:1.0 alpha:1.0];
    sendBtn.layer.cornerRadius = 14.0;
    [sendBtn addTarget:self action:@selector(submitFeedback) forControlEvents:UIControlEventTouchUpInside];
    [formCard addSubview:sendBtn];

    UILabel *emailLabel = [[UILabel alloc] init];
    emailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    emailLabel.text = @"Contact: caydance_kalem253@mail.com";
    emailLabel.textColor = [UIColor colorWithWhite:0.64 alpha:1.0];
    emailLabel.font = [UIFont fontWithName:@"AvenirNext-Regular" size:13.0] ?: [UIFont systemFontOfSize:13.0];
    emailLabel.textAlignment = NSTextAlignmentCenter;
    [formCard addSubview:emailLabel];

    UILabel *note = [NBSettingsTheme bodyLabelWithText:@"We review every message. For direct contact you can also reach us at the email below."];
    note.textAlignment = NSTextAlignmentCenter;
    [stack addArrangedSubview:note];

    [NSLayoutConstraint activateConstraints:@[
        [hint.topAnchor constraintEqualToAnchor:introCard.topAnchor constant:16.0],
        [hint.leadingAnchor constraintEqualToAnchor:introCard.leadingAnchor constant:16.0],
        [hint.trailingAnchor constraintEqualToAnchor:introCard.trailingAnchor constant:-16.0],
        [sub.topAnchor constraintEqualToAnchor:hint.bottomAnchor constant:8.0],
        [sub.leadingAnchor constraintEqualToAnchor:introCard.leadingAnchor constant:16.0],
        [sub.trailingAnchor constraintEqualToAnchor:introCard.trailingAnchor constant:-16.0],
        [sub.bottomAnchor constraintEqualToAnchor:introCard.bottomAnchor constant:-16.0],

        [_inputViewBox.topAnchor constraintEqualToAnchor:formCard.topAnchor constant:16.0],
        [_inputViewBox.leadingAnchor constraintEqualToAnchor:formCard.leadingAnchor constant:16.0],
        [_inputViewBox.trailingAnchor constraintEqualToAnchor:formCard.trailingAnchor constant:-16.0],
        [_inputViewBox.heightAnchor constraintEqualToConstant:220.0],

        [sendBtn.topAnchor constraintEqualToAnchor:_inputViewBox.bottomAnchor constant:20.0],
        [sendBtn.leadingAnchor constraintEqualToAnchor:formCard.leadingAnchor constant:16.0],
        [sendBtn.trailingAnchor constraintEqualToAnchor:formCard.trailingAnchor constant:-16.0],
        [sendBtn.heightAnchor constraintEqualToConstant:54.0],

        [emailLabel.topAnchor constraintEqualToAnchor:sendBtn.bottomAnchor constant:12.0],
        [emailLabel.leadingAnchor constraintEqualToAnchor:formCard.leadingAnchor constant:16.0],
        [emailLabel.trailingAnchor constraintEqualToAnchor:formCard.trailingAnchor constant:-16.0],
        [emailLabel.bottomAnchor constraintEqualToAnchor:formCard.bottomAnchor constant:-14.0],

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

- (void)submitFeedback {
    [_inputViewBox resignFirstResponder];
    NSString *raw = [_inputViewBox.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    BOOL stillPlaceholder = [_inputViewBox.text isEqualToString:kFeedbackPlaceholder];
    if (raw.length == 0 || stillPlaceholder) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Almost there"
                                                                       message:@"Please enter a short message before sending."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [gen impactOccurred];
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Thank you"
                                                                       message:@"Your feedback has been received. We appreciate you helping make Ballocity better."
                                                                preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        self->_inputViewBox.text = kFeedbackPlaceholder;
        self->_inputViewBox.textColor = [UIColor colorWithWhite:0.50 alpha:1.0];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITextViewDelegate

- (void)textViewDidBeginEditing:(UITextView *)textView {
    if ([textView.text isEqualToString:kFeedbackPlaceholder]) {
        textView.text = @"";
        textView.textColor = [UIColor colorWithWhite:0.95 alpha:1.0];
    }
}

- (void)textViewDidEndEditing:(UITextView *)textView {
    if (textView.text.length == 0) {
        textView.text = kFeedbackPlaceholder;
        textView.textColor = [UIColor colorWithWhite:0.50 alpha:1.0];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _bgLayer.frame = self.view.bounds;
}

@end

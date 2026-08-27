#import "GameViewController.h"
#import "GameScene.h"
@import SpriteKit;

#ifndef NB_INPUT_TRACE
#define NB_INPUT_TRACE 0
#endif

// GameViewController：容器 + 输入桥接层。
// 使用 UIKit 的 Tap / Pan 手势稳定转发输入到 GameScene，避免 SpriteKit 触摸分发差异。

@interface GameViewController () <GameSceneDelegate>
@property (nonatomic, strong) SKView *skView;
@property (nonatomic, strong) GameScene *scene;
@property (nonatomic, strong) UITapGestureRecognizer *tapGR;
@property (nonatomic, strong) UIPanGestureRecognizer *panGR;
@end

@implementation GameViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.12 alpha:1.0];
    [self setupScene];
}

- (void)setupScene {
    _skView = [[SKView alloc] initWithFrame:self.view.bounds];
    _skView.autoresizingMask    = UIViewAutoresizingFlexibleWidth
                                | UIViewAutoresizingFlexibleHeight;
    _skView.ignoresSiblingOrder = YES;
    _skView.allowsTransparency  = NO;
    [self.view addSubview:_skView];

    _scene = [GameScene sceneWithSize:self.view.bounds.size];
    _scene.scaleMode    = SKSceneScaleModeResizeFill;
    _scene.gameDelegate = self;
    [_skView presentScene:_scene];
    [self setupInputBridge];
}

- (void)setupInputBridge {
    _tapGR = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTap:)];
    _tapGR.cancelsTouchesInView = YES;
    [_skView addGestureRecognizer:_tapGR];

    _panGR = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
    _panGR.minimumNumberOfTouches = 1;
    _panGR.maximumNumberOfTouches = 1;
    _panGR.cancelsTouchesInView = YES;
    [_skView addGestureRecognizer:_panGR];

    // If a drag is recognized, don't also trigger tap.
    [_tapGR requireGestureRecognizerToFail:_panGR];
}

- (CGPoint)scenePointFromViewPoint:(CGPoint)viewPt {
    if (!_scene) return CGPointZero;
    return [_scene convertPointFromView:viewPt];
}

- (void)onTap:(UITapGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateRecognized || !_scene) return;
    CGPoint pt = [self scenePointFromViewPoint:[gr locationInView:_skView]];
#if NB_INPUT_TRACE
    NSLog(@"[NeoBall VC] tap scenePt=%@ view=%@ scene.size=%@",
          NSStringFromCGPoint(pt), NSStringFromCGPoint([gr locationInView:_skView]),
          NSStringFromCGSize(_scene.size));
#endif
    [_scene aimGestureBegan:pt];
    [_scene aimGestureEnded:pt];
}

- (void)onPan:(UIPanGestureRecognizer *)gr {
    if (!_scene) return;
    CGPoint pt = [self scenePointFromViewPoint:[gr locationInView:_skView]];
#if NB_INPUT_TRACE
    if (gr.state == UIGestureRecognizerStateBegan || gr.state == UIGestureRecognizerStateEnded) {
        NSLog(@"[NeoBall VC] pan state=%ld scenePt=%@", (long)gr.state, NSStringFromCGPoint(pt));
    }
#endif
    switch (gr.state) {
        case UIGestureRecognizerStateBegan:
            [_scene aimGestureBegan:pt];
            break;
        case UIGestureRecognizerStateChanged:
            [_scene aimGestureMoved:pt];
            break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            [_scene aimGestureEnded:pt];
            break;
        default:
            break;
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _skView.frame = self.view.bounds;
}

#pragma mark - GameSceneDelegate

- (void)gameSceneDidRequestMainMenu {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

@end

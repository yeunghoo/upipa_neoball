#import "GameScene.h"
@import SpriteKit;
@import AudioToolbox;
#import <UIKit/UIKit.h>
#import "VKMediaLoader.h"

// 输入/发射链路调试：设为 0 可关闭屏幕 HUD 与 NSLog（上架前建议关掉）
#ifndef NB_INPUT_TRACE
#define NB_INPUT_TRACE 0
#endif

// ─────────────────────────────────────────────
// Physics categories
// ─────────────────────────────────────────────
typedef NS_OPTIONS(uint32_t, NBCategory) {
    NBCategoryBall   = 1 << 0,
    NBCategoryBrick  = 1 << 1,
    NBCategoryWall   = 1 << 2,
    NBCategoryBottom = 1 << 3,
    NBCategoryItem   = 1 << 4,
};

// ─────────────────────────────────────────────
// Item types
// ─────────────────────────────────────────────
typedef NS_ENUM(NSInteger, NBItemType) {
    NBItemTypeBallUp,    // +1 ball
    NBItemTypeBomb,      // 3×3 area destroy
    NBItemTypeLightning, // full column clear
    NBItemTypeStarBonus, // score bonus
};

// ─────────────────────────────────────────────
// Game state
// ─────────────────────────────────────────────
typedef NS_ENUM(NSInteger, NBGameState) {
    NBGameStateAiming,
    NBGameStateShooting,
    NBGameStateAdvancing,
    NBGameStateGameOver,
};

// ─────────────────────────────────────────────
// Brick model
// ─────────────────────────────────────────────
@interface NBBrick : NSObject
@property (nonatomic) NSInteger row;
@property (nonatomic) NSInteger col;
@property (nonatomic) NSInteger hp;
@property (nonatomic) NSInteger maxHP;
@property (nonatomic) BOOL pendingRemoval;
@property (nonatomic, strong) SKShapeNode *node;
@property (nonatomic, strong) SKLabelNode *hpLabel;
@end
@implementation NBBrick @end

// ─────────────────────────────────────────────
// Item model
// ─────────────────────────────────────────────
@interface NBItem : NSObject
@property (nonatomic) NSInteger row;
@property (nonatomic) NSInteger col;
@property (nonatomic) NBItemType type;
@property (nonatomic) BOOL collected;
@property (nonatomic, strong) SKNode *node;
@end
@implementation NBItem @end

// ─────────────────────────────────────────────
// GameScene
// ─────────────────────────────────────────────
@interface GameScene () <SKPhysicsContactDelegate>

// Layout
@property (nonatomic) CGFloat cellSize;
@property (nonatomic) CGFloat gridTopY;    // y‑coord of top of row‑0
@property (nonatomic) CGFloat safeLineY;   // y‑coord of danger line
@property (nonatomic) CGFloat launchY;     // y‑coord of ball launch
@property (nonatomic) CGFloat launchX;     // x‑coord of launch
@property (nonatomic) NSInteger maxRows;

// Game state
@property (nonatomic) NBGameState state;
@property (nonatomic) NSInteger level;
@property (nonatomic) NSInteger score;
@property (nonatomic) NSInteger totalBalls;
@property (nonatomic) NSInteger pendingBalls;
@property (nonatomic) NSInteger activeBalls;
@property (nonatomic) NSInteger returnedBalls;
@property (nonatomic) CGFloat   firstReturnX;
@property (nonatomic) BOOL      hasFirstReturn;
@property (nonatomic) NSInteger turnCount;
@property (nonatomic) CFTimeInterval shootStartTime;

// Grid  [key = "row_col"]
@property (nonatomic, strong) NSMutableDictionary<NSString *, NBBrick *> *bricks;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NBItem  *> *items;
@property (nonatomic, strong) NSMutableArray<SKNode *> *flyingBalls;

// Nodes
@property (nonatomic, strong) SKNode      *aimNode;
@property (nonatomic, strong) SKNode      *launchIndicator;
@property (nonatomic, strong) SKLabelNode *scoreLabel;
@property (nonatomic, strong) SKLabelNode *levelLabel;
@property (nonatomic, strong) SKLabelNode *ballCountLabel;
@property (nonatomic, strong) SKShapeNode *safetyLine;
@property (nonatomic, strong) SKNode      *powerupButton;
@property (nonatomic, strong) SKShapeNode *powerupBadge;
@property (nonatomic, strong) SKLabelNode *powerupCountLabel;
@property (nonatomic, strong) SKLabelNode *backButton;
@property (nonatomic, strong) SKNode      *restartButton;
#if NB_INPUT_TRACE
@property (nonatomic, strong) SKNode *debugHUD;
@property (nonatomic, strong) SKLabelNode *debugLabel;
#endif

// Power-up
@property (nonatomic) NSInteger powerupUses;
@property (nonatomic) CFTimeInterval lastHitSfxTime;

// Reward-video prompt overlay (UIKit above SKView)
@property (nonatomic, assign) BOOL rewardPromptActive;
@property (nonatomic, strong, nullable) UIView *rewardPromptOverlay;

// Touch / Aiming  (泡泡龙风格: 记录最后一次有效瞄准点，松手即发射)
@property (nonatomic) BOOL    aimActive;   // YES = 手指在游戏区域内按住
@property (nonatomic) CGPoint aimPt;       // 最新瞄准坐标 (场景坐标)
@end

@implementation GameScene

static const NSInteger kCols          = 7;
static const CGFloat   kBallR         = 9.0;
static const CGFloat   kBallSpeed     = 500.0;
static const CGFloat   kLaunchDelay   = 0.09;
static const CGFloat   kTopBarH       = 90.0;   // taller top bar → grid shifts down
static const CGFloat   kBottomPad     = 100.0;  // room for powerup bar + launch area
static const CGFloat   kPowerupBarH   = 72.0;   // height of the powerup button strip
static const CGFloat   kCellGap       = 2.5;
static const NSInteger kPowerupMax    = 1;
static const CFTimeInterval kTurnTimeout = 25.0;
static const CFTimeInterval kHitSfxMinInterval = 0.05;

// System sound IDs (no asset files required).
static const SystemSoundID kLaunchSfxID   = 1104;
static const SystemSoundID kHitSfxID      = 1157;
static const SystemSoundID kGameOverSfxID = 1023;

static inline NSString *NBStateName(NBGameState s) {
    switch (s) {
        case NBGameStateAiming: return @"Aiming";
        case NBGameStateShooting: return @"Shooting";
        case NBGameStateAdvancing: return @"Advancing";
        case NBGameStateGameOver: return @"GameOver";
    }
    return @"Unknown";
}

#pragma mark - Sound

- (void)playLaunchSfx {
    AudioServicesPlaySystemSound(kLaunchSfxID);
}

- (void)playHitSfx {
    CFTimeInterval now = CACurrentMediaTime();
    if (now - _lastHitSfxTime < kHitSfxMinInterval) return;
    _lastHitSfxTime = now;
    AudioServicesPlaySystemSound(kHitSfxID);
}

- (void)playGameOverSfx {
    AudioServicesPlaySystemSound(kGameOverSfxID);
}

#pragma mark - Lifecycle

- (void)didMoveToView:(SKView *)view {
    self.physicsWorld.gravity  = CGVectorMake(0, 0);
    self.physicsWorld.contactDelegate = self;
    // Input is bridged from GameViewController (Tap/Pan recognizers).
    self.userInteractionEnabled = NO;

    [self computeLayout];
    [self buildBackground];
    [self buildWalls];
    [self buildTopBar];
    [self buildSafetyLine];
    [self buildLaunchIndicator];
    [self buildPowerupBar];
#if NB_INPUT_TRACE
    [self buildDebugHUD];
#endif

    _bricks      = [NSMutableDictionary dictionary];
    _items       = [NSMutableDictionary dictionary];
    _flyingBalls = [NSMutableArray array];

    [self startNewGame];
}

#if NB_INPUT_TRACE
- (void)buildDebugHUD {
    _debugHUD = [SKNode node];
    _debugHUD.zPosition = 10000;
    _debugHUD.name = @"nbDebugHUD";

    CGFloat margin = 8.0;
    CGFloat panelW = MIN(self.size.width - margin * 2, 420);
    CGFloat panelH = 72.0;
    UIBezierPath *bp = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, panelW, panelH) cornerRadius:6.0];
    SKShapeNode *bg = [SKShapeNode shapeNodeWithPath:bp.CGPath];
    bg.name = @"nbDebugBG";
    bg.fillColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    bg.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.25];
    bg.lineWidth = 1.0;
    [_debugHUD addChild:bg];

    _debugLabel = [SKLabelNode labelNodeWithFontNamed:@"Menlo"];
    _debugLabel.fontSize = 9;
    _debugLabel.fontColor = [UIColor colorWithRed:0.4 green:1.0 blue:0.45 alpha:1.0];
    _debugLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeLeft;
    _debugLabel.verticalAlignmentMode = SKLabelVerticalAlignmentModeTop;
    _debugLabel.position = CGPointMake(margin + 4, panelH - margin - 2);
    _debugLabel.numberOfLines = 0;
    _debugLabel.preferredMaxLayoutWidth = panelW - (margin + 8) * 2;
    [_debugHUD addChild:_debugLabel];

    _debugHUD.position = CGPointMake(margin, self.size.height - panelH - margin);
    [self addChild:_debugHUD];
    [self dbg:@"HUD ready (also search Xcode console: NeoBall)"];
}

- (void)dbg:(NSString *)msg {
    NSString *line = [NSString stringWithFormat:@"%@ | launch %@ | aim:%@ | balls:%ld/%ld | %@",
                      NBStateName(_state),
                      NSStringFromCGPoint(CGPointMake(_launchX, _launchY)),
                      _aimActive ? @"Y" : @"N",
                      (long)_activeBalls,
                      (long)_totalBalls,
                      msg ?: @""];
    NSLog(@"[NeoBall] %@", line);
    if (_debugLabel) _debugLabel.text = line;
}
#else
- (void)dbg:(NSString *)msg { (void)msg; }
#endif

// Called by SpriteKit when the scene is resized (e.g. ResizeFill, first layout)
- (void)didChangeSize:(CGSize)oldSize {
    // Only react when growing from a zero/tiny initial size to the real screen size.
    BOOL wasInvalid = (oldSize.width  < 50 || oldSize.height < 50);
    BOOL isValid    = (self.size.width > 50 && self.size.height > 50);
    if (wasInvalid && isValid && _launchIndicator) {
        [self computeLayout];
        // Reposition the launch indicator so it matches the corrected layout
        _launchX = self.size.width * 0.5;
        _launchIndicator.position = CGPointMake(_launchX, _launchY);
    }
#if NB_INPUT_TRACE
    if (_debugHUD) {
        CGFloat margin = 8.0;
        CGFloat panelW = MIN(self.size.width - margin * 2, 420);
        CGFloat panelH = 72.0;
        _debugHUD.position = CGPointMake(margin, self.size.height - panelH - margin);
        if (_debugLabel) _debugLabel.preferredMaxLayoutWidth = panelW - (margin + 8) * 2;
        SKShapeNode *bg = (SKShapeNode *)[_debugHUD childNodeWithName:@"nbDebugBG"];
        if (bg) {
            UIBezierPath *bp = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, panelW, panelH) cornerRadius:6.0];
            bg.path = bp.CGPath;
        }
    }
#endif
}

// ─────────────────────────────────────────────
// Layout
// ─────────────────────────────────────────────
- (void)computeLayout {
    CGFloat safeTop = 0, safeBottom = 0;
    if (@available(iOS 11.0, *)) {
        UIEdgeInsets ins = self.view.safeAreaInsets;
        safeTop = ins.top; safeBottom = ins.bottom;
    }
    CGFloat W = self.size.width;
    CGFloat H = self.size.height;

    _cellSize  = W / kCols;

    // Top of grid is below the top bar (grid intentionally shifted down)
    _gridTopY  = H - safeTop - kTopBarH;

    // Bottom layout (Y‑up):
    //  safeBottom ─── safe area
    //  + 8          ─── small padding
    //  + kPowerupBarH ─── powerup button strip
    //  + 12         ─── gap
    //  ─── _launchY (ball launch / landing line)
    //  + _cellSize  ─── safety line is one cell above launch
    CGFloat bottomBase = safeBottom + 8 + kPowerupBarH + 12;
    _launchY   = bottomBase + kBallR;
    _safeLineY = _launchY + _cellSize;
    _launchX   = W * 0.5;

    // Move the whole level/gameplay area down a bit (keeps relative spacing).
    CGFloat kLevelShiftDown = 14.0;
    _gridTopY  -= kLevelShiftDown;
    _launchY   -= kLevelShiftDown;
    _safeLineY -= kLevelShiftDown;

    _maxRows = (NSInteger)((_gridTopY - _safeLineY) / _cellSize);
    if (_maxRows < 6) _maxRows = 6;
}

// ─────────────────────────────────────────────
// Background & visual setup
// ─────────────────────────────────────────────
- (void)buildBackground {
    SKSpriteNode *bg = [SKSpriteNode spriteNodeWithColor:[UIColor colorWithRed:0.03 green:0.03 blue:0.13 alpha:1.0]
                                                    size:self.size];
    bg.position = CGPointMake(self.size.width * 0.5, self.size.height * 0.5);
    bg.zPosition = -100;
    [self addChild:bg];

    // Subtle column guides
    for (int c = 1; c < kCols; c++) {
        CGFloat x = c * _cellSize;
        CGMutablePathRef p = CGPathCreateMutable();
        CGPathMoveToPoint(p, NULL, x, _safeLineY);
        CGPathAddLineToPoint(p, NULL, x, _gridTopY);
        SKShapeNode *line = [SKShapeNode shapeNodeWithPath:p];
        line.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.04];
        line.lineWidth   = 1.0;
        line.zPosition   = -60;
        [self addChild:line];
        CGPathRelease(p);
    }

    // Stars
    srand48(7);
    for (int i = 0; i < 90; i++) {
        CGFloat x  = (CGFloat)(drand48() * self.size.width);
        CGFloat y  = (CGFloat)(drand48() * self.size.height);
        CGFloat r  = (drand48() < 0.2) ? 1.4 : 0.7;
        SKShapeNode *star = [SKShapeNode shapeNodeWithCircleOfRadius:r];
        star.fillColor   = [UIColor colorWithWhite:1.0 alpha:0.15 + drand48() * 0.5];
        star.strokeColor = [UIColor clearColor];
        star.position    = CGPointMake(x, y);
        star.zPosition   = -80;
        [self addChild:star];
        if (drand48() < 0.45) {
            CGFloat dur = 1.0 + drand48() * 2.5;
            SKAction *dim  = [SKAction fadeAlphaTo:0.04 duration:dur];
            SKAction *glow = [SKAction fadeAlphaTo:0.65 duration:dur];
            [star runAction:[SKAction repeatActionForever:[SKAction sequence:@[dim, glow]]]];
        }
    }
}

- (void)buildWalls {
    CGFloat W = self.size.width;
    CGFloat H = self.size.height;

    // Left
    SKNode *lw = [SKNode node];
    lw.physicsBody = [SKPhysicsBody bodyWithEdgeFromPoint:CGPointMake(0, 0)
                                                  toPoint:CGPointMake(0, H)];
    lw.physicsBody.categoryBitMask    = NBCategoryWall;
    lw.physicsBody.friction           = 0;
    lw.physicsBody.restitution        = 1.0;
    [self addChild:lw];

    // Right
    SKNode *rw = [SKNode node];
    rw.physicsBody = [SKPhysicsBody bodyWithEdgeFromPoint:CGPointMake(W, 0)
                                                  toPoint:CGPointMake(W, H)];
    rw.physicsBody.categoryBitMask    = NBCategoryWall;
    rw.physicsBody.friction           = 0;
    rw.physicsBody.restitution        = 1.0;
    [self addChild:rw];

    // Top
    SKNode *tw = [SKNode node];
    tw.physicsBody = [SKPhysicsBody bodyWithEdgeFromPoint:CGPointMake(0, H)
                                                  toPoint:CGPointMake(W, H)];
    tw.physicsBody.categoryBitMask    = NBCategoryWall;
    tw.physicsBody.friction           = 0;
    tw.physicsBody.restitution        = 1.0;
    [self addChild:tw];

    // Bottom sensor — MUST sit fully BELOW the spawn point.
    // Spawn uses y = _launchY + kBallR + 2, so ball bottom is _launchY + 2.
    // Old placement overlapped [_launchY-13.5 … _launchY+4.5] and instantly triggered
    // ballLanded on the first physics frame (looked like “never launched”).
    SKNode *bz = [SKNode node];
    CGFloat sensorH = kBallR * 1.5;
    bz.position = CGPointMake(W * 0.5, _launchY - kBallR * 2.0);
    bz.physicsBody = [SKPhysicsBody bodyWithRectangleOfSize:CGSizeMake(W + 20, sensorH)];
    bz.physicsBody.dynamic              = NO;
    bz.physicsBody.categoryBitMask      = NBCategoryBottom;
    bz.physicsBody.contactTestBitMask   = NBCategoryBall;
    bz.physicsBody.collisionBitMask     = 0;
    [self addChild:bz];
}

- (void)buildTopBar {
    CGFloat W = self.size.width;
    CGFloat H = self.size.height;
    CGFloat barCenterY = H - kTopBarH * 0.5;
    CGFloat safeTop = 0;
    CGFloat safeLeft = 0;
    CGFloat safeRight = 0;
    if (@available(iOS 11.0, *)) safeTop = self.view.safeAreaInsets.top;
    if (@available(iOS 11.0, *)) {
        UIEdgeInsets ins = self.view.safeAreaInsets;
        safeLeft = ins.left;
        safeRight = ins.right;
    }
    barCenterY = H - safeTop - kTopBarH * 0.5;

    SKSpriteNode *barBg = [SKSpriteNode
        spriteNodeWithColor:[UIColor colorWithRed:0.04 green:0.04 blue:0.18 alpha:0.96]
                       size:CGSizeMake(W, kTopBarH + safeTop)];
    barBg.position  = CGPointMake(W * 0.5, H - (kTopBarH + safeTop) * 0.5);
    barBg.zPosition = 50;
    [self addChild:barBg];

    // ← back button
    SKLabelNode *back = [SKLabelNode labelNodeWithFontNamed:@"AvenirNext-Bold"];
    back.text                  = @"✕";
    back.fontSize              = 18;
    back.fontColor             = [UIColor colorWithWhite:0.55 alpha:1.0];
    back.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeLeft;
    back.verticalAlignmentMode   = SKLabelVerticalAlignmentModeCenter;
    back.position  = CGPointMake(safeLeft + 18, barCenterY);
    back.zPosition = 55;
    back.name      = @"backBtn";
    [self addChild:back];
    _backButton = back;

    // ── Restart button (top-right, same height as close) ──
    _restartButton = [SKNode node];
    _restartButton.position  = CGPointMake(W - safeRight - 18.0 - 72.0, barCenterY);
    _restartButton.zPosition = 70;
    _restartButton.name      = @"restartBtn";
    [self addChild:_restartButton];
    SKLabelNode *rTxt = [SKLabelNode labelNodeWithFontNamed:@"AvenirNext-Heavy"];
    rTxt.text     = @"RESTART";
    rTxt.fontSize = 12;
    rTxt.fontColor = [UIColor whiteColor];
    rTxt.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    rTxt.verticalAlignmentMode   = SKLabelVerticalAlignmentModeCenter;
    rTxt.position = CGPointMake(0, 0);
    [_restartButton addChild:rTxt];

    // Score
    _scoreLabel = [SKLabelNode labelNodeWithFontNamed:@"AvenirNext-Bold"];
    _scoreLabel.fontSize              = 17;
    _scoreLabel.fontColor             = [UIColor colorWithRed:1.0 green:0.82 blue:0.0 alpha:1.0];
    _scoreLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeLeft;
    _scoreLabel.verticalAlignmentMode   = SKLabelVerticalAlignmentModeCenter;
    _scoreLabel.position  = CGPointMake(18, barCenterY - 18);
    _scoreLabel.zPosition = 55;
    [self addChild:_scoreLabel];

    // Level
    _levelLabel = [SKLabelNode labelNodeWithFontNamed:@"AvenirNext-Bold"];
    _levelLabel.fontSize              = 17;
    _levelLabel.fontColor             = [UIColor colorWithRed:0.4 green:1.0 blue:0.5 alpha:1.0];
    _levelLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    _levelLabel.verticalAlignmentMode   = SKLabelVerticalAlignmentModeCenter;
    _levelLabel.position  = CGPointMake(W * 0.5, barCenterY - 18);
    _levelLabel.zPosition = 55;
    [self addChild:_levelLabel];

    // Ball count
    _ballCountLabel = [SKLabelNode labelNodeWithFontNamed:@"AvenirNext-DemiBold"];
    _ballCountLabel.fontSize              = 16;
    _ballCountLabel.fontColor             = [UIColor colorWithRed:0.3 green:0.82 blue:1.0 alpha:1.0];
    _ballCountLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeRight;
    _ballCountLabel.verticalAlignmentMode   = SKLabelVerticalAlignmentModeCenter;
    _ballCountLabel.position  = CGPointMake(W - 14, barCenterY - 18);
    _ballCountLabel.zPosition = 55;
    [self addChild:_ballCountLabel];
}

- (void)buildSafetyLine {
    CGMutablePathRef p = CGPathCreateMutable();
    CGPathMoveToPoint(p, NULL, 0, _safeLineY);
    CGPathAddLineToPoint(p, NULL, self.size.width, _safeLineY);
    _safetyLine = [SKShapeNode shapeNodeWithPath:p];
    _safetyLine.strokeColor = [UIColor colorWithRed:1.0 green:0.15 blue:0.15 alpha:0.75];
    _safetyLine.lineWidth   = 2.0;
    _safetyLine.glowWidth   = 5.0;
    _safetyLine.zPosition   = 15;
    [self addChild:_safetyLine];
    CGPathRelease(p);

    SKLabelNode *lbl = [SKLabelNode labelNodeWithFontNamed:@"AvenirNext-Regular"];
    lbl.text     = @"— DANGER ZONE —";
    lbl.fontSize = 9;
    lbl.fontColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:0.45];
    lbl.position  = CGPointMake(self.size.width * 0.5, _safeLineY + 5);
    lbl.zPosition = 16;
    [self addChild:lbl];
}

- (void)buildLaunchIndicator {
    CGFloat r = kBallR;

    _launchIndicator = [SKNode node];
    _launchIndicator.position  = CGPointMake(_launchX, _launchY);
    _launchIndicator.zPosition = 25;
    [self addChild:_launchIndicator];

    // Diffuse halo behind the ball
    SKShapeNode *halo = [SKShapeNode shapeNodeWithCircleOfRadius:r * 1.7];
    halo.fillColor   = [UIColor colorWithRed:0.28 green:0.82 blue:1.0 alpha:0.20];
    halo.strokeColor = [UIColor clearColor];
    halo.zPosition   = -1;
    halo.blendMode   = SKBlendModeAdd;
    [_launchIndicator addChild:halo];

    // Main ball body
    SKShapeNode *body = [SKShapeNode shapeNodeWithCircleOfRadius:r];
    body.fillColor   = [UIColor colorWithRed:0.80 green:0.96 blue:1.0 alpha:1.0];
    body.strokeColor = [UIColor colorWithRed:0.22 green:0.78 blue:1.0 alpha:1.0];
    body.lineWidth   = 2.5;
    body.glowWidth   = 14.0;
    [_launchIndicator addChild:body];

    // Inner bright core
    SKShapeNode *core = [SKShapeNode shapeNodeWithCircleOfRadius:r * 0.54];
    core.fillColor   = [UIColor colorWithWhite:1.0 alpha:0.95];
    core.strokeColor = [UIColor clearColor];
    core.zPosition   = 1;
    core.blendMode   = SKBlendModeAdd;
    [_launchIndicator addChild:core];

    // Specular highlight
    SKShapeNode *spec = [SKShapeNode shapeNodeWithCircleOfRadius:r * 0.27];
    spec.fillColor   = [UIColor colorWithWhite:1.0 alpha:0.88];
    spec.strokeColor = [UIColor clearColor];
    spec.position    = CGPointMake(-r * 0.31, r * 0.31);
    spec.zPosition   = 2;
    [_launchIndicator addChild:spec];

    // Idle breathing pulse
    SKAction *pulse = [SKAction repeatActionForever:[SKAction sequence:@[
        [SKAction scaleTo:1.10 duration:0.9],
        [SKAction scaleTo:0.95 duration:0.9]
    ]]];
    [_launchIndicator runAction:pulse];
}

- (void)buildPowerupBar {
    CGFloat W  = self.size.width;
    CGFloat safeBottom = 0;
    if (@available(iOS 11.0, *)) safeBottom = self.view.safeAreaInsets.bottom;

    // Bar background
    CGFloat barCenterY = safeBottom + 8 + kPowerupBarH * 0.5;
    SKSpriteNode *barBg = [SKSpriteNode
        spriteNodeWithColor:[UIColor colorWithRed:0.04 green:0.04 blue:0.18 alpha:0.95]
                       size:CGSizeMake(W, kPowerupBarH + safeBottom + 8)];
    barBg.position  = CGPointMake(W * 0.5, (safeBottom + 8 + kPowerupBarH * 0.5 + safeBottom) * 0.5);
    barBg.zPosition = 50;
    [self addChild:barBg];

    // Separator line at top of bar
    CGMutablePathRef sep = CGPathCreateMutable();
    CGPathMoveToPoint(sep, NULL, 0, safeBottom + 8 + kPowerupBarH);
    CGPathAddLineToPoint(sep, NULL, W, safeBottom + 8 + kPowerupBarH);
    SKShapeNode *sepLine = [SKShapeNode shapeNodeWithPath:sep];
    sepLine.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.06];
    sepLine.lineWidth   = 1.0;
    sepLine.zPosition   = 51;
    [self addChild:sepLine];
    CGPathRelease(sep);

    // Powerup button container
    _powerupButton = [SKNode node];
    _powerupButton.position  = CGPointMake(W * 0.5, barCenterY);
    _powerupButton.zPosition = 55;
    _powerupButton.name      = @"powerupBtn";
    [self addChild:_powerupButton];

    // Button background
    UIBezierPath *btnBp = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(-105, -24, 210, 48)
                                                      cornerRadius:12.0];
    SKShapeNode *btnBg = [SKShapeNode shapeNodeWithPath:btnBp.CGPath];
    btnBg.fillColor   = [UIColor colorWithRed:0.55 green:0.08 blue:0.60 alpha:1.0];
    btnBg.strokeColor = [UIColor colorWithRed:0.90 green:0.30 blue:1.00 alpha:1.0];
    btnBg.lineWidth   = 2.0;
    btnBg.glowWidth   = 8.0;
    btnBg.name        = @"powerupBtnBg";
    [_powerupButton addChild:btnBg];

    // Icon (⚡ nova symbol)
    SKLabelNode *icon = [SKLabelNode labelNodeWithFontNamed:@"AvenirNext-Heavy"];
    icon.text     = @"✦";
    icon.fontSize = 22;
    icon.fontColor = [UIColor colorWithRed:1.0 green:0.9 blue:0.2 alpha:1.0];
    icon.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeLeft;
    icon.verticalAlignmentMode   = SKLabelVerticalAlignmentModeCenter;
    icon.position = CGPointMake(-90, 0);
    [_powerupButton addChild:icon];

    // Label
    SKLabelNode *lbl = [SKLabelNode labelNodeWithFontNamed:@"AvenirNext-Heavy"];
    lbl.text     = @"NOVA BLAST";
    lbl.fontSize = 17;
    lbl.fontColor = [UIColor whiteColor];
    lbl.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    lbl.verticalAlignmentMode   = SKLabelVerticalAlignmentModeCenter;
    lbl.position = CGPointMake(-10, 0);
    [_powerupButton addChild:lbl];

    // Use-count badge
    SKShapeNode *badge = [SKShapeNode shapeNodeWithCircleOfRadius:16];
    badge.fillColor   = [UIColor colorWithRed:1.0 green:0.3 blue:0.9 alpha:1.0];
    badge.strokeColor = [UIColor colorWithRed:1.0 green:0.6 blue:1.0 alpha:1.0];
    badge.lineWidth   = 1.5;
    badge.glowWidth   = 4.0;
    badge.position    = CGPointMake(80, 0);
    badge.name        = @"powerupBadge";
    [_powerupButton addChild:badge];
    _powerupBadge = badge;

    _powerupCountLabel = [SKLabelNode labelNodeWithFontNamed:@"AvenirNext-Heavy"];
    _powerupCountLabel.fontSize  = 16;
    _powerupCountLabel.fontColor = [UIColor whiteColor];
    _powerupCountLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    _powerupCountLabel.verticalAlignmentMode   = SKLabelVerticalAlignmentModeCenter;
    _powerupCountLabel.position  = CGPointMake(80, 0);
    [_powerupButton addChild:_powerupCountLabel];

    // Idle glow pulse
    SKAction *glow = [SKAction repeatActionForever:
        [SKAction sequence:@[[SKAction runBlock:^{ btnBg.glowWidth = 12.0; }],
                             [SKAction waitForDuration:0.9],
                             [SKAction runBlock:^{ btnBg.glowWidth = 5.0; }],
                             [SKAction waitForDuration:0.9]]]];
    [_powerupButton runAction:glow withKey:@"glowPulse"];
}

// ─────────────────────────────────────────────
// HUD update
// ─────────────────────────────────────────────
- (void)updateHUD {
    _scoreLabel.text     = [NSString stringWithFormat:@"SCORE %ld", (long)_score];
    _levelLabel.text     = [NSString stringWithFormat:@"LV.%ld", (long)_level];
    _ballCountLabel.text = [NSString stringWithFormat:@"x%ld ●", (long)_totalBalls];
}

- (void)updatePowerupButton {
    if (_powerupUses > 0) {
        _powerupCountLabel.fontSize = 16;
        _powerupCountLabel.text = [NSString stringWithFormat:@"%ld", (long)_powerupUses];
        _powerupButton.alpha = 1.0;
        if (_powerupBadge) {
            _powerupBadge.fillColor   = [UIColor colorWithRed:1.0 green:0.3 blue:0.9 alpha:1.0];
            _powerupBadge.strokeColor = [UIColor colorWithRed:1.0 green:0.6 blue:1.0 alpha:1.0];
        }
    } else {
        // 用途耗尽：角标显示“广告”
        _powerupCountLabel.fontSize = 14;
        _powerupCountLabel.text = @"AD";
        _powerupButton.alpha = 0.35;
        if (_powerupBadge) {
            _powerupBadge.fillColor   = [UIColor colorWithRed:1.0 green:0.55 blue:0.15 alpha:1.0];
            _powerupBadge.strokeColor = [UIColor colorWithRed:1.0 green:0.80 blue:0.35 alpha:1.0];
        }
    }
}

// ─────────────────────────────────────────────
// Game start / restart
// ─────────────────────────────────────────────
- (void)startNewGame {
    // Remove game over overlay if present
    [[self childNodeWithName:@"gameOverOverlay"] removeFromParent];

    // Clear old state
    for (NBBrick *b in _bricks.allValues) [b.node removeFromParent];
    for (NBItem  *i in _items.allValues)  [i.node removeFromParent];
    [_bricks removeAllObjects];
    [_items  removeAllObjects];
    for (SKNode *ball in _flyingBalls) [ball removeFromParent];
    [_flyingBalls removeAllObjects];
    [self removeActionForKey:@"turnFlow"];
    [self removeActionForKey:@"advFlow"];   // clear any stale advance-grid action
    [self removeActionForKey:@"turnEnd"];

    _level        = 1;
    _score        = 0;
    _totalBalls   = 1;
    _pendingBalls = 0;
    _turnCount    = 0;
    _powerupUses  = kPowerupMax;
    _lastHitSfxTime = 0;
    _launchX      = self.size.width * 0.5;
    _state        = NBGameStateAdvancing;
    [self updatePowerupButton];

    // Seed first 3 rows
    for (NSInteger r = 0; r < 3; r++) [self spawnRow:r];

    [self updateHUD];
    [self enterAiming];
    [self dbg:@"startNewGame -> enterAiming"];
}

// ─────────────────────────────────────────────
// Restart current level (KEEP Nova Blast uses)
// ─────────────────────────────────────────────
- (BOOL)restartLevelKeepingUses {
    NSInteger keepUses = _powerupUses;
    NSLog(@"[NeoBall] 重新开始按钮点击：准备重置关卡(保留 NOVA BLAST uses=%ld)", (long)keepUses);

    [[self childNodeWithName:@"gameOverOverlay"] removeFromParent];

    // Clear old state (except _powerupUses)
    for (NBBrick *b in _bricks.allValues) [b.node removeFromParent];
    for (NBItem  *i in _items.allValues)  [i.node removeFromParent];
    [_bricks removeAllObjects];
    [_items  removeAllObjects];
    for (SKNode *ball in _flyingBalls) [ball removeFromParent];
    [_flyingBalls removeAllObjects];

    [self removeActionForKey:@"turnFlow"];
    [self removeActionForKey:@"advFlow"];
    [self removeActionForKey:@"turnEnd"];

    // Clear aim line node if present
    if (_aimNode) {
        [_aimNode removeFromParent];
        _aimNode = nil;
    }
    _aimActive = NO;

    _level        = 1;
    _score        = 0;
    _totalBalls   = 1;
    _pendingBalls = 0;
    _turnCount    = 0;
    _lastHitSfxTime = 0;
    _launchX      = self.size.width * 0.5;
    _state        = NBGameStateAdvancing;

    // KEEP _powerupUses unchanged
    _powerupUses = keepUses;
    [self updatePowerupButton];

    for (NSInteger r = 0; r < 3; r++) [self spawnRow:r];
    [self updateHUD];
    [self enterAiming];
    [self dbg:@"restartLevelKeepingUses -> enterAiming"];
    return YES;
}

// ─────────────────────────────────────────────
// Row generation
// ─────────────────────────────────────────────
- (void)spawnRow:(NSInteger)row {
    // base HP scales with level
    NSInteger baseHP = _level + (NSInteger)(arc4random_uniform((uint32_t)MAX(1, _level / 2 + 1)));

    // Shuffle columns
    NSMutableArray<NSNumber *> *cols = [NSMutableArray array];
    for (int c = 0; c < kCols; c++) [cols addObject:@(c)];
    for (NSInteger i = (NSInteger)cols.count - 1; i > 0; i--) {
        NSInteger j = arc4random_uniform((uint32_t)(i + 1));
        [cols exchangeObjectAtIndex:i withObjectAtIndex:j];
    }

    // 4–6 bricks
    NSInteger brickCount = 4 + arc4random_uniform(3);
    for (NSInteger i = 0; i < MIN(brickCount, kCols); i++) {
        NSInteger hp = MAX(1, baseHP + (NSInteger)(arc4random_uniform(2)) - 0);
        [self placeBrickRow:row col:[cols[i] integerValue] hp:hp];
    }

    // 0–2 items in remaining columns (30% chance)
    for (NSInteger i = brickCount; i < kCols; i++) {
        if (arc4random_uniform(3) == 0) {
            NBItemType t = (NBItemType)(arc4random_uniform(4));
            [self placeItemRow:row col:[cols[i] integerValue] type:t];
        }
    }
}

// ─────────────────────────────────────────────
// Brick placement
// ─────────────────────────────────────────────
- (void)placeBrickRow:(NSInteger)row col:(NSInteger)col hp:(NSInteger)hp {
    NSString *key = [NSString stringWithFormat:@"%ld_%ld", (long)row, (long)col];
    if (_bricks[key]) return;

    CGFloat bW = _cellSize - kCellGap * 2;
    CGFloat bH = _cellSize - kCellGap * 2;

    UIBezierPath *brickPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(-bW * 0.5, -bH * 0.5, bW, bH)
                                                         cornerRadius:7.0];
    SKShapeNode *node = [SKShapeNode shapeNodeWithPath:brickPath.CGPath];
    node.position = [self posRow:row col:col];
    node.zPosition = 10;
    [self applyBrickColor:node hp:hp maxHP:hp];

    SKPhysicsBody *pb = [SKPhysicsBody bodyWithRectangleOfSize:CGSizeMake(bW, bH)];
    pb.dynamic             = NO;
    pb.categoryBitMask     = NBCategoryBrick;
    pb.contactTestBitMask  = NBCategoryBall;
    pb.collisionBitMask    = NBCategoryBall;
    pb.friction            = 0;
    pb.restitution         = 1.0;
    node.physicsBody = pb;

    SKLabelNode *lbl = [SKLabelNode labelNodeWithFontNamed:@"AvenirNext-Heavy"];
    lbl.fontSize              = [self hpFontSize:hp];
    lbl.fontColor             = [UIColor whiteColor];
    lbl.verticalAlignmentMode   = SKLabelVerticalAlignmentModeCenter;
    lbl.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    lbl.text = [self hpString:hp];
    lbl.name = @"hpLbl";
    [node addChild:lbl];

    NBBrick *brick  = [[NBBrick alloc] init];
    brick.row       = row;
    brick.col       = col;
    brick.hp        = hp;
    brick.maxHP     = hp;
    brick.node      = node;
    brick.hpLabel   = lbl;
    node.userData   = [@{@"brick": brick} mutableCopy];

    [self addChild:node];
    _bricks[key] = brick;
}

- (void)applyBrickColor:(SKShapeNode *)node hp:(NSInteger)hp maxHP:(NSInteger)maxHP {
    CGFloat r = (maxHP > 0) ? (CGFloat)hp / maxHP : 1.0;
    UIColor *fill, *stroke;
    if (r > 0.66) {
        fill   = [UIColor colorWithRed:0.04 green:0.28 blue:0.60 alpha:1.0];
        stroke = [UIColor colorWithRed:0.08 green:0.58 blue:1.00 alpha:1.0];
    } else if (r > 0.33) {
        fill   = [UIColor colorWithRed:0.30 green:0.04 blue:0.58 alpha:1.0];
        stroke = [UIColor colorWithRed:0.60 green:0.08 blue:1.00 alpha:1.0];
    } else if (r > 0.12) {
        fill   = [UIColor colorWithRed:0.60 green:0.18 blue:0.04 alpha:1.0];
        stroke = [UIColor colorWithRed:1.00 green:0.38 blue:0.08 alpha:1.0];
    } else {
        fill   = [UIColor colorWithRed:0.62 green:0.04 blue:0.08 alpha:1.0];
        stroke = [UIColor colorWithRed:1.00 green:0.08 blue:0.18 alpha:1.0];
    }
    node.fillColor   = fill;
    node.strokeColor = stroke;
    node.lineWidth   = 2.0;
    node.glowWidth   = 2.5;
}

- (NSString *)hpString:(NSInteger)hp {
    if (hp >= 1000) return [NSString stringWithFormat:@"%ldK", (long)(hp / 1000)];
    return [NSString stringWithFormat:@"%ld", (long)hp];
}

- (CGFloat)hpFontSize:(NSInteger)hp {
    if (hp >= 1000) return 9;
    if (hp >= 100)  return 11;
    return 14;
}

// ─────────────────────────────────────────────
// Item placement
// ─────────────────────────────────────────────
- (void)placeItemRow:(NSInteger)row col:(NSInteger)col type:(NBItemType)type {
    NSString *key = [NSString stringWithFormat:@"%ld_%ld", (long)row, (long)col];
    if (_items[key] || _bricks[key]) return;

    CGFloat radius = _cellSize * 0.34;
    SKShapeNode *circle = [SKShapeNode shapeNodeWithCircleOfRadius:radius];
    circle.position  = [self posRow:row col:col];
    circle.zPosition = 10;

    NSString *symbol;
    UIColor  *fill, *stroke;
    switch (type) {
        case NBItemTypeBallUp:
            fill   = [UIColor colorWithRed:0.08 green:0.55 blue:0.12 alpha:1.0];
            stroke = [UIColor colorWithRed:0.15 green:1.00 blue:0.20 alpha:1.0];
            symbol = @"+1";
            break;
        case NBItemTypeBomb:
            fill   = [UIColor colorWithRed:0.70 green:0.28 blue:0.00 alpha:1.0];
            stroke = [UIColor colorWithRed:1.00 green:0.55 blue:0.00 alpha:1.0];
            symbol = @"💥";
            break;
        case NBItemTypeLightning:
            fill   = [UIColor colorWithRed:0.55 green:0.52 blue:0.00 alpha:1.0];
            stroke = [UIColor colorWithRed:1.00 green:1.00 blue:0.00 alpha:1.0];
            symbol = @"⚡";
            break;
        case NBItemTypeStarBonus:
            fill   = [UIColor colorWithRed:0.55 green:0.28 blue:0.00 alpha:1.0];
            stroke = [UIColor colorWithRed:1.00 green:0.78 blue:0.00 alpha:1.0];
            symbol = @"★";
            break;
    }

    circle.fillColor   = fill;
    circle.strokeColor = stroke;
    circle.lineWidth   = 2.0;
    circle.glowWidth   = 5.0;

    SKLabelNode *lbl = [SKLabelNode labelNodeWithFontNamed:@"AvenirNext-Heavy"];
    lbl.text = symbol;
    lbl.fontSize = (type == NBItemTypeBallUp) ? 13 : 16;
    lbl.fontColor = [UIColor whiteColor];
    lbl.verticalAlignmentMode   = SKLabelVerticalAlignmentModeCenter;
    lbl.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    [circle addChild:lbl];

    SKPhysicsBody *pb = [SKPhysicsBody bodyWithCircleOfRadius:radius];
    pb.dynamic            = NO;
    pb.categoryBitMask    = NBCategoryItem;
    pb.contactTestBitMask = NBCategoryBall;
    pb.collisionBitMask   = 0;
    circle.physicsBody = pb;

    SKAction *pulse = [SKAction repeatActionForever:
        [SKAction sequence:@[[SKAction scaleTo:1.12 duration:0.65],
                             [SKAction scaleTo:1.00 duration:0.65]]]];
    [circle runAction:pulse];

    NBItem *item  = [[NBItem alloc] init];
    item.row      = row;
    item.col      = col;
    item.type     = type;
    item.node     = circle;
    circle.userData = [@{@"item": item} mutableCopy];

    [self addChild:circle];
    _items[key] = item;
}

// ─────────────────────────────────────────────
// Grid position helper
// ─────────────────────────────────────────────
- (CGPoint)posRow:(NSInteger)row col:(NSInteger)col {
    CGFloat x = col * _cellSize + _cellSize * 0.5;
    CGFloat y = _gridTopY - row * _cellSize - _cellSize * 0.5;
    return CGPointMake(x, y);
}

// ─────────────────────────────────────────────
// Turn flow
// ─────────────────────────────────────────────
- (void)enterAiming {
    _state     = NBGameStateAiming;
    _aimActive = NO;
    _launchIndicator.position = CGPointMake(_launchX, _launchY);
    [self updateHUD];
    [self dbg:@"enterAiming"];
}

- (void)fireDirection:(CGVector)dir {
    if (_state != NBGameStateAiming) {
        [self dbg:[NSString stringWithFormat:@"fire blocked (state=%@)", NBStateName(_state)]];
        return;
    }
    _state        = NBGameStateShooting;
    _activeBalls  = 0;
    _returnedBalls = 0;
    _hasFirstReturn = NO;
    _shootStartTime = -1;
    [self playLaunchSfx];

    [_aimNode removeFromParent];
    _aimNode = nil;
    [self dbg:[NSString stringWithFormat:@"fire dir=(%.2f,%.2f)", dir.dx, dir.dy]];

    for (NSInteger i = 0; i < _totalBalls; i++) {
        [self runAction:[SKAction sequence:@[
            [SKAction waitForDuration:i * kLaunchDelay],
            [SKAction runBlock:^{ [self spawnBallDir:dir]; }]
        ]]];
    }
}

- (void)spawnBallDir:(CGVector)dir {
    CGFloat r = kBallR;

    // ── Main ball body ─────────────────────────────────────────────
    SKShapeNode *ball = [SKShapeNode shapeNodeWithCircleOfRadius:r];
    ball.fillColor   = [UIColor colorWithRed:0.80 green:0.96 blue:1.0  alpha:1.0];
    ball.strokeColor = [UIColor colorWithRed:0.22 green:0.78 blue:1.0  alpha:1.0];
    ball.lineWidth   = 2.5;
    ball.glowWidth   = 14.0;   // strong outer glow for neon feel
    ball.position    = CGPointMake(_launchX, _launchY + r + 2);
    ball.zPosition   = 30;

    // Outer diffuse halo (additive blending for vivid bloom)
    SKShapeNode *halo = [SKShapeNode shapeNodeWithCircleOfRadius:r * 1.7];
    halo.fillColor   = [UIColor colorWithRed:0.28 green:0.82 blue:1.0 alpha:0.20];
    halo.strokeColor = [UIColor clearColor];
    halo.zPosition   = -1;
    halo.blendMode   = SKBlendModeAdd;
    [ball addChild:halo];

    // Bright inner core — gives solid, filled feel
    SKShapeNode *core = [SKShapeNode shapeNodeWithCircleOfRadius:r * 0.54];
    core.fillColor   = [UIColor colorWithWhite:1.0 alpha:0.95];
    core.strokeColor = [UIColor clearColor];
    core.zPosition   = 1;
    core.blendMode   = SKBlendModeAdd;
    [ball addChild:core];

    // Small specular highlight (top-left) for 3-D depth illusion
    SKShapeNode *spec = [SKShapeNode shapeNodeWithCircleOfRadius:r * 0.27];
    spec.fillColor   = [UIColor colorWithWhite:1.0 alpha:0.88];
    spec.strokeColor = [UIColor clearColor];
    spec.position    = CGPointMake(-r * 0.31, r * 0.31);
    spec.zPosition   = 2;
    [ball addChild:spec];

    SKPhysicsBody *pb = [SKPhysicsBody bodyWithCircleOfRadius:r];
    pb.categoryBitMask          = NBCategoryBall;
    pb.contactTestBitMask       = NBCategoryBrick | NBCategoryItem | NBCategoryBottom;
    pb.collisionBitMask         = NBCategoryBrick | NBCategoryWall;
    pb.restitution              = 1.0;
    pb.friction                 = 0;
    pb.linearDamping            = 0;
    pb.angularDamping           = 0;
    pb.allowsRotation           = NO;
    pb.usesPreciseCollisionDetection = YES;
    pb.velocity = CGVectorMake(dir.dx * kBallSpeed, dir.dy * kBallSpeed);
    ball.physicsBody = pb;

    [self addChild:ball];
    [_flyingBalls addObject:ball];
    _activeBalls++;
}

- (void)ballLanded:(SKNode *)ball {
    if (![_flyingBalls containsObject:ball]) return;

    if (!_hasFirstReturn) {
        _hasFirstReturn = YES;
        _firstReturnX   = MAX(kBallR + 6, MIN(self.size.width - kBallR - 6, ball.position.x));
    }

    ball.physicsBody = nil;

    CGFloat landX = ball.position.x;
    [ball runAction:[SKAction sequence:@[
        [SKAction moveTo:CGPointMake(landX, _launchY) duration:0.08],
        [SKAction removeFromParent],
        [SKAction runBlock:^{
            [self->_flyingBalls removeObject:ball];
            self->_returnedBalls++;
            self->_activeBalls--;
            if (self->_activeBalls == 0) {
                [self runAction:[SKAction sequence:@[
                    [SKAction waitForDuration:0.25],
                    [SKAction runBlock:^{ [self turnComplete]; }]
                ]] withKey:@"turnEnd"];
            }
        }]
    ]]];
}

- (void)turnComplete {
    // Update launch position
    if (_hasFirstReturn) _launchX = _firstReturnX;

    // Collect pending balls
    _totalBalls  += _pendingBalls;
    _pendingBalls = 0;
    _turnCount++;
    _level = MAX(1, _turnCount);

    [self advanceGrid];
}

- (void)advanceGrid {
    _state = NBGameStateAdvancing;

    // Save best score
    NSInteger best = [[NSUserDefaults standardUserDefaults] integerForKey:@"NBBestScore"];
    if (_score > best) {
        [[NSUserDefaults standardUserDefaults] setInteger:_score forKey:@"NBBestScore"];
    }

    NSMutableDictionary *newBricks = [NSMutableDictionary dictionary];
    NSMutableDictionary *newItems  = [NSMutableDictionary dictionary];
    BOOL gameOver = NO;

    // Move bricks down one row
    for (NBBrick *b in _bricks.allValues) {
        b.row++;
        NSString *k = [NSString stringWithFormat:@"%ld_%ld", (long)b.row, (long)b.col];
        newBricks[k] = b;
        [b.node runAction:[SKAction moveTo:[self posRow:b.row col:b.col] duration:0.22]];
        if (b.row >= _maxRows) gameOver = YES;
    }

    // Move items down
    for (NBItem *it in _items.allValues) {
        it.row++;
        NSString *k = [NSString stringWithFormat:@"%ld_%ld", (long)it.row, (long)it.col];
        newItems[k] = it;
        [it.node runAction:[SKAction moveTo:[self posRow:it.row col:it.col] duration:0.22]];
        // Remove items that go past safety line
        if (it.row >= _maxRows) {
            [it.node runAction:[SKAction removeFromParent]];
            [newItems removeObjectForKey:k];
        }
    }

    _bricks = newBricks;
    _items  = newItems;

    if (gameOver) {
        [self runAction:[SKAction sequence:@[
            [SKAction waitForDuration:0.4],
            [SKAction runBlock:^{ [self triggerGameOver]; }]
        ]]];
        return;
    }

    // Generate new row, then return to aiming
    [self runAction:[SKAction sequence:@[
        [SKAction waitForDuration:0.28],
        [SKAction runBlock:^{ [self spawnRow:0]; [self updateHUD]; [self checkDangerPulse]; }],
        [SKAction waitForDuration:0.12],
        [SKAction runBlock:^{ [self enterAiming]; }]
    ]] withKey:@"advFlow"];
}

- (void)checkDangerPulse {
    BOOL near = NO;
    for (NBBrick *b in _bricks.allValues) {
        if (b.row >= _maxRows - 2) { near = YES; break; }
    }
    if (near) {
        SKAction *flash = [SKAction repeatAction:[SKAction sequence:@[
            [SKAction runBlock:^{ self->_safetyLine.strokeColor = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:1.0]; }],
            [SKAction waitForDuration:0.12],
            [SKAction runBlock:^{ self->_safetyLine.strokeColor = [UIColor colorWithRed:1.0 green:0.15 blue:0.15 alpha:0.75]; }],
            [SKAction waitForDuration:0.12],
        ]] count:4];
        [_safetyLine runAction:flash];
    }
}

// ─────────────────────────────────────────────
// Physics contact
// ─────────────────────────────────────────────
- (void)didBeginContact:(SKPhysicsContact *)contact {
    SKPhysicsBody *ballPB = nil, *otherPB = nil;
    if (contact.bodyA.categoryBitMask & NBCategoryBall) {
        ballPB = contact.bodyA; otherPB = contact.bodyB;
    } else if (contact.bodyB.categoryBitMask & NBCategoryBall) {
        ballPB = contact.bodyB; otherPB = contact.bodyA;
    } else {
        return;
    }

    if (!ballPB.node || !otherPB.node) return;

    if (otherPB.categoryBitMask & NBCategoryBrick) {
        [self onBallHitBrick:ballPB.node brick:otherPB.node at:contact.contactPoint];
    } else if (otherPB.categoryBitMask & NBCategoryItem) {
        [self onBallHitItem:ballPB.node item:otherPB.node];
    } else if (otherPB.categoryBitMask & NBCategoryBottom) {
        [self ballLanded:ballPB.node];
    }
}

- (void)onBallHitBrick:(SKNode *)ball brick:(SKNode *)brickNode at:(CGPoint)pt {
    NBBrick *brick = brickNode.userData[@"brick"];
    if (!brick || brick.pendingRemoval) return;

    brick.hp--;
    _score++;

    [self applyBrickColor:(SKShapeNode *)brickNode hp:brick.hp maxHP:brick.maxHP];
    brick.hpLabel.text     = [self hpString:brick.hp];
    brick.hpLabel.fontSize = [self hpFontSize:brick.hp];

    // Flash
    SKAction *hitFlash = [SKAction sequence:@[
        [SKAction colorizeWithColor:[UIColor whiteColor] colorBlendFactor:0.9 duration:0.04],
        [SKAction colorizeWithColorBlendFactor:0.0 duration:0.1]
    ]];
    [brickNode runAction:hitFlash];
    [self spawnHitSparks:pt color:((SKShapeNode *)brickNode).strokeColor];
    [self playHitSfx];

    if (brick.hp <= 0) {
        brick.pendingRemoval = YES;
        [self destroyBrick:brick];
    }
}

- (void)onBallHitItem:(SKNode *)ball item:(SKNode *)itemNode {
    NBItem *item = itemNode.userData[@"item"];
    if (!item || item.collected) return;
    item.collected = YES;

    NSString *key = [NSString stringWithFormat:@"%ld_%ld", (long)item.row, (long)item.col];
    [_items removeObjectForKey:key];
    itemNode.physicsBody = nil;

    CGPoint pos = itemNode.position;
    switch (item.type) {
        case NBItemTypeBallUp:
            _pendingBalls++;
            [self showFloatText:@"+1 BALL" at:pos color:[UIColor colorWithRed:0.3 green:1.0 blue:0.4 alpha:1.0]];
            break;
        case NBItemTypeBomb:
            [itemNode removeFromParent];
            [self triggerBombRow:item.row col:item.col];
            return;
        case NBItemTypeLightning:
            [itemNode removeFromParent];
            [self triggerLightningCol:item.col];
            return;
        case NBItemTypeStarBonus: {
            NSInteger bonus = _level * 15;
            _score += bonus;
            [self showFloatText:[NSString stringWithFormat:@"+%ld★", (long)bonus]
                             at:pos
                          color:[UIColor colorWithRed:1.0 green:0.85 blue:0.0 alpha:1.0]];
        } break;
    }

    [itemNode runAction:[SKAction sequence:@[
        [SKAction group:@[[SKAction scaleTo:1.6 duration:0.1], [SKAction fadeOutWithDuration:0.15]]],
        [SKAction removeFromParent]
    ]]];
    [self updateHUD];
}

// ─────────────────────────────────────────────
// Brick destruction
// ─────────────────────────────────────────────
- (void)destroyBrick:(NBBrick *)brick {
    NSString *key = [NSString stringWithFormat:@"%ld_%ld", (long)brick.row, (long)brick.col];
    [_bricks removeObjectForKey:key];

    NSInteger pts = brick.maxHP;
    _score += pts;

    UIColor *col = ((SKShapeNode *)brick.node).strokeColor;
    [self spawnDestroyParticles:brick.node.position color:col];
    [self showFloatText:[NSString stringWithFormat:@"+%ld", (long)pts]
                     at:brick.node.position
                  color:col];

    [brick.node runAction:[SKAction sequence:@[
        [SKAction group:@[[SKAction scaleTo:1.25 duration:0.08], [SKAction fadeOutWithDuration:0.12]]],
        [SKAction removeFromParent]
    ]]];
    [self updateHUD];
}

// ─────────────────────────────────────────────
// Bomb
// ─────────────────────────────────────────────
- (void)triggerBombRow:(NSInteger)row col:(NSInteger)col {
    CGPoint center = [self posRow:row col:col];
    [self spawnExplosion:center];

    for (NSInteger dr = -1; dr <= 1; dr++) {
        for (NSInteger dc = -1; dc <= 1; dc++) {
            NSString *k = [NSString stringWithFormat:@"%ld_%ld", (long)(row + dr), (long)(col + dc)];
            NBBrick *b = _bricks[k];
            if (b && !b.pendingRemoval) {
                b.pendingRemoval = YES;
                [self destroyBrick:b];
            }
        }
    }
    [self updateHUD];
}

// ─────────────────────────────────────────────
// Nova Blast (player power-up: clear bottom rows)
// ─────────────────────────────────────────────
- (void)activateNovaBeast {
    if (_powerupUses <= 0 || _state != NBGameStateAiming) return;

    _powerupUses--;
    [self updatePowerupButton];

    // Button feedback
    [_powerupButton runAction:[SKAction sequence:@[
        [SKAction scaleTo:0.88 duration:0.08],
        [SKAction scaleTo:1.0  duration:0.12]
    ]]];

    // Destroy bricks in bottom 2 rows (highest row indices = closest to safety line)
    NSInteger destroyFrom = _maxRows - 2;
    NSMutableArray *toDestroy = [NSMutableArray array];
    for (NBBrick *b in _bricks.allValues) {
        if (b.row >= destroyFrom && !b.pendingRemoval) [toDestroy addObject:b];
    }

    // Shockwave visual (expands from safety line)
    SKShapeNode *wave = [SKShapeNode shapeNodeWithCircleOfRadius:10];
    wave.fillColor   = [UIColor clearColor];
    wave.strokeColor = [UIColor colorWithRed:0.9 green:0.3 blue:1.0 alpha:0.9];
    wave.lineWidth   = 4.0;
    wave.glowWidth   = 12.0;
    wave.position    = CGPointMake(self.size.width * 0.5, _safeLineY);
    wave.zPosition   = 60;
    wave.blendMode   = SKBlendModeAdd;
    [self addChild:wave];
    [wave runAction:[SKAction sequence:@[
        [SKAction group:@[
            [SKAction scaleTo:self.size.width / 10.0 duration:0.35],
            [SKAction fadeOutWithDuration:0.35]
        ]],
        [SKAction removeFromParent]
    ]]];

    // Destroy with stagger
    for (NSInteger i = 0; i < (NSInteger)toDestroy.count; i++) {
        NBBrick *b = toDestroy[i];
        b.pendingRemoval = YES;
        NSTimeInterval delay = i * 0.03;
        [self runAction:[SKAction sequence:@[
            [SKAction waitForDuration:delay],
            [SKAction runBlock:^{ [self destroyBrick:b]; }]
        ]]];
    }

    if (toDestroy.count == 0) {
        [self showFloatText:@"Grid Clear!" at:CGPointMake(self.size.width * 0.5, _safeLineY + 40)
                     color:[UIColor colorWithRed:0.9 green:0.3 blue:1.0 alpha:1.0]];
    } else {
        [self showFloatText:[NSString stringWithFormat:@"NOVA BLAST! -%ld bricks", (long)toDestroy.count]
                         at:CGPointMake(self.size.width * 0.5, _safeLineY + 40)
                      color:[UIColor colorWithRed:1.0 green:0.5 blue:1.0 alpha:1.0]];
    }
}

// ─────────────────────────────────────────────
// Lightning
// ─────────────────────────────────────────────
- (void)triggerLightningCol:(NSInteger)col {
    // Draw beam
    CGMutablePathRef p = CGPathCreateMutable();
    CGPathMoveToPoint(p, NULL, col * _cellSize + _cellSize * 0.5, _gridTopY);
    CGPathAddLineToPoint(p, NULL, col * _cellSize + _cellSize * 0.5, _safeLineY);
    SKShapeNode *beam = [SKShapeNode shapeNodeWithPath:p];
    beam.strokeColor = [UIColor colorWithRed:1.0 green:1.0 blue:0.2 alpha:0.9];
    beam.lineWidth   = _cellSize * 0.4;
    beam.glowWidth   = 18.0;
    beam.zPosition   = 40;
    beam.blendMode   = SKBlendModeAdd;
    [self addChild:beam];
    CGPathRelease(p);
    [beam runAction:[SKAction sequence:@[
        [SKAction fadeOutWithDuration:0.3], [SKAction removeFromParent]
    ]]];

    for (NSInteger r = 0; r < _maxRows; r++) {
        NSString *k = [NSString stringWithFormat:@"%ld_%ld", (long)r, (long)col];
        NBBrick *b = _bricks[k];
        if (b && !b.pendingRemoval) {
            b.pendingRemoval = YES;
            [self destroyBrick:b];
        }
    }
    [self updateHUD];
}

// ─────────────────────────────────────────────
// Particle helpers
// ─────────────────────────────────────────────
- (void)spawnHitSparks:(CGPoint)pos color:(UIColor *)col {
    for (int i = 0; i < 5; i++) {
        SKShapeNode *s = [SKShapeNode shapeNodeWithCircleOfRadius:2.0];
        s.fillColor   = col;
        s.strokeColor = [UIColor clearColor];
        s.position    = pos;
        s.zPosition   = 60;
        s.blendMode   = SKBlendModeAdd;
        [self addChild:s];
        CGFloat ang = (CGFloat)i / 5.0 * M_PI * 2.0;
        CGFloat spd = 40.0 + arc4random_uniform(40);
        [s runAction:[SKAction sequence:@[
            [SKAction group:@[
                [SKAction moveByX:cos(ang) * spd y:sin(ang) * spd duration:0.3],
                [SKAction fadeOutWithDuration:0.3],
                [SKAction scaleTo:0.1 duration:0.3]
            ]],
            [SKAction removeFromParent]
        ]]];
    }
}

- (void)spawnDestroyParticles:(CGPoint)pos color:(UIColor *)col {
    for (int i = 0; i < 12; i++) {
        SKShapeNode *s = [SKShapeNode shapeNodeWithCircleOfRadius:3.5];
        s.fillColor   = col;
        s.strokeColor = [UIColor clearColor];
        s.position    = pos;
        s.zPosition   = 60;
        s.blendMode   = SKBlendModeAdd;
        [self addChild:s];
        CGFloat ang = (CGFloat)i / 12.0 * M_PI * 2.0;
        CGFloat spd = 55.0 + arc4random_uniform(60);
        [s runAction:[SKAction sequence:@[
            [SKAction group:@[
                [SKAction moveByX:cos(ang) * spd y:sin(ang) * spd duration:0.45],
                [SKAction fadeOutWithDuration:0.45],
                [SKAction scaleTo:0.05 duration:0.45]
            ]],
            [SKAction removeFromParent]
        ]]];
    }
}

- (void)spawnExplosion:(CGPoint)pos {
    SKShapeNode *ring = [SKShapeNode shapeNodeWithCircleOfRadius:_cellSize * 0.5];
    ring.fillColor   = [UIColor clearColor];
    ring.strokeColor = [UIColor colorWithRed:1.0 green:0.55 blue:0.0 alpha:0.9];
    ring.lineWidth   = 5.0;
    ring.glowWidth   = 10.0;
    ring.position    = pos;
    ring.zPosition   = 55;
    ring.blendMode   = SKBlendModeAdd;
    [self addChild:ring];
    [ring runAction:[SKAction sequence:@[
        [SKAction group:@[
            [SKAction scaleTo:3.0 duration:0.35],
            [SKAction fadeOutWithDuration:0.35]
        ]],
        [SKAction removeFromParent]
    ]]];
    [self spawnDestroyParticles:pos color:[UIColor colorWithRed:1.0 green:0.6 blue:0.1 alpha:1.0]];
}

// ─────────────────────────────────────────────
// Floating score text
// ─────────────────────────────────────────────
- (void)showFloatText:(NSString *)text at:(CGPoint)pos color:(UIColor *)col {
    SKLabelNode *lbl = [SKLabelNode labelNodeWithFontNamed:@"AvenirNext-Heavy"];
    lbl.text      = text;
    lbl.fontSize  = 16;
    lbl.fontColor = col;
    lbl.position  = CGPointMake(pos.x, pos.y + _cellSize * 0.5);
    lbl.zPosition = 80;
    lbl.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    [self addChild:lbl];

    [lbl runAction:[SKAction sequence:@[
        [SKAction group:@[
            [SKAction moveByX:0 y:36 duration:0.65],
            [SKAction sequence:@[
                [SKAction waitForDuration:0.3],
                [SKAction fadeOutWithDuration:0.35]
            ]]
        ]],
        [SKAction removeFromParent]
    ]]];
}

// ─────────────────────────────────────────────
// Aim preview
// ─────────────────────────────────────────────
- (CGVector)validatedDir:(CGPoint)touchPt {
    CGFloat dx = touchPt.x - _launchX;
    CGFloat dy = touchPt.y - _launchY;
    CGFloat len = hypot(dx, dy);
    // Only reject touches that are essentially ON the launch indicator itself
    if (len < 5.0) return CGVectorMake(0, 0);
    dx /= len; dy /= len;

    // Clamp to minimum upward angle (5°) — never return (0,0) for a far touch
    CGFloat minUp = sin(5.0 * M_PI / 180.0);
    if (dy < minUp) {
        // Preserve horizontal sign; force upward angle
        if (fabs(dx) < 1e-6) dx = (dx >= 0) ? 1e-6 : -1e-6;
        dy = minUp;
        dx = (dx > 0) ? sqrt(MAX(0, 1.0 - dy * dy)) : -sqrt(MAX(0, 1.0 - dy * dy));
    }
    return CGVectorMake(dx, dy);
}

- (NSArray<NSValue *> *)previewPoints:(CGPoint)start dir:(CGVector)dir {
    NSMutableArray *pts = [NSMutableArray array];
    [pts addObject:[NSValue valueWithCGPoint:start]];

    CGPoint p  = start;
    CGVector d = dir;
    CGFloat W  = self.size.width;

    // Physical walls:  left x=0, right x=W, top y=sceneH
    // Ball lands at:   y = _launchY  (same as where it was launched from)
    CGFloat sceneH = self.size.height;

    for (int b = 0; b < 8; b++) {
        CGFloat tL   = (d.dx < -1e-4) ? -p.x          / d.dx : 1e9f;
        CGFloat tR   = (d.dx >  1e-4) ? (W - p.x)     / d.dx : 1e9f;
        CGFloat tTop = (d.dy >  1e-4) ? (sceneH - p.y) / d.dy : 1e9f;
        CGFloat tBot = (d.dy < -1e-4) ? (_launchY - p.y) / d.dy : 1e9f;

        // Pick nearest wall (must be > small epsilon to avoid self-intersection)
        CGFloat tMin = 1e9f; int axis = -1; // 0=side wall, 1=top wall, 2=floor
        if (tL   > 1.0f && tL   < tMin) { tMin = tL;   axis = 0; }
        if (tR   > 1.0f && tR   < tMin) { tMin = tR;   axis = 0; }
        if (tTop > 1.0f && tTop < tMin) { tMin = tTop; axis = 1; }
        if (tBot > 1.0f && tBot < tMin) { tMin = tBot; axis = 2; }

        if (axis < 0) break;

        CGPoint hit = CGPointMake(p.x + d.dx * tMin, p.y + d.dy * tMin);
        // Clamp to scene bounds (floating-point safety)
        hit.x = MAX(0, MIN(W, hit.x));
        hit.y = MAX(0, MIN(sceneH, hit.y));
        [pts addObject:[NSValue valueWithCGPoint:hit]];

        if (axis == 2) break;   // ball reached the floor — stop preview

        // Reflect direction
        if (axis == 0) d.dx = -d.dx;
        if (axis == 1) d.dy = -d.dy;

        // Nudge slightly off the wall to avoid re-hitting it immediately
        p = CGPointMake(hit.x + d.dx * 1.0f, hit.y + d.dy * 1.0f);
    }
    return pts;
}

- (void)drawAimLine:(CGVector)dir {
    [_aimNode removeFromParent];

    NSArray<NSValue *> *pts = [self previewPoints:CGPointMake(_launchX, _launchY) dir:dir];
    if (pts.count < 2) { _aimNode = nil; return; }

    SKNode *container = [SKNode node];
    container.zPosition = 28;

    CGFloat dash = 11, gap = 7;

    for (NSUInteger seg = 0; seg < pts.count - 1; seg++) {
        CGPoint A = [pts[seg] CGPointValue];
        CGPoint B = [pts[seg + 1] CGPointValue];
        CGFloat dx = B.x - A.x, dy = B.y - A.y;
        CGFloat segLen = hypot(dx, dy);
        if (segLen < 1) continue;
        CGFloat ndx = dx / segLen, ndy = dy / segLen;

        CGFloat t = 0; BOOL draw = YES;
        while (t < segLen) {
            CGFloat chunk = draw ? dash : gap;
            CGFloat end = MIN(t + chunk, segLen);
            if (draw) {
                CGPoint p1 = CGPointMake(A.x + ndx * t,   A.y + ndy * t);
                CGPoint p2 = CGPointMake(A.x + ndx * end, A.y + ndy * end);
                CGMutablePathRef path = CGPathCreateMutable();
                CGPathMoveToPoint(path, NULL, p1.x, p1.y);
                CGPathAddLineToPoint(path, NULL, p2.x, p2.y);
                SKShapeNode *d = [SKShapeNode shapeNodeWithPath:path];
                d.strokeColor = [UIColor colorWithRed:0.45 green:0.88 blue:1.00 alpha:0.75];
                d.lineWidth   = 2.0;
                d.glowWidth   = 2.5;
                [container addChild:d];
                CGPathRelease(path);
            }
            t = end; draw = !draw;
        }
    }

    // Endpoint dot
    CGPoint last = [[pts lastObject] CGPointValue];
    SKShapeNode *dot = [SKShapeNode shapeNodeWithCircleOfRadius:6];
    dot.fillColor   = [UIColor colorWithRed:0.3 green:0.85 blue:1.0 alpha:0.85];
    dot.strokeColor = [UIColor clearColor];
    dot.glowWidth   = 5.0;
    dot.position    = last;
    [container addChild:dot];

    [self addChild:container];
    _aimNode = container;
}

// ─────────────────────────────────────────────
// Reward Video Prompt (Nova Blast uses)
// ─────────────────────────────────────────────
- (UIViewController *)nb_topMostViewController {
    UIViewController *rootVC = nil;

    // Prefer the active foreground UIWindowScene.
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            if (ws.activationState != UISceneActivationStateForegroundActive) continue;

            for (UIWindow *w in ws.windows) {
                if (!w.isKeyWindow) continue;
                rootVC = w.rootViewController;
                break;
            }
            if (rootVC) break;
        }
    }
    if (!rootVC) {
        // Fallback: try to pick any root view controller.
        for (UIWindow *w in UIApplication.sharedApplication.windows) {
            if (w.rootViewController) { rootVC = w.rootViewController; break; }
        }
    }
    if (!rootVC) return nil;

    UIViewController *top = rootVC;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

- (void)nb_showAutoToast:(NSString *)text {
    UIViewController *vc = [self nb_topMostViewController];
    if (!vc || !vc.view.window) return;

    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 280, 52)];
    lbl.text = text ?: @"";
    lbl.textAlignment = NSTextAlignmentCenter;
    lbl.numberOfLines = 2;
    lbl.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    lbl.textColor = [UIColor whiteColor];
    lbl.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
    lbl.layer.cornerRadius = 12.0;
    lbl.clipsToBounds = YES;
    lbl.center = CGPointMake(vc.view.bounds.size.width * 0.5, vc.view.bounds.size.height * 0.55);
    lbl.alpha = 0.0;

    [vc.view addSubview:lbl];

    [UIView animateWithDuration:0.22 animations:^{
        lbl.alpha = 1.0;
    } completion:^(BOOL finished) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.2 animations:^{
                lbl.alpha = 0.0;
            } completion:^(BOOL done) {
                [lbl removeFromSuperview];
            }];
        });
    }];
}

- (void)nb_dismissRewardPromptAndCloseBanner {
    if (self.rewardPromptOverlay) {
        [self.rewardPromptOverlay removeFromSuperview];
        self.rewardPromptOverlay = nil;
    }
    self.rewardPromptActive = NO;

    // Close banner together with the dialog.
    [VKMediaLoader vka_closeBanner];
}

- (void)nb_presentRewardVideoPromptIfNeeded {
    if (self.rewardPromptActive) return;
    self.rewardPromptActive = YES;

    UIViewController *vc = [self nb_topMostViewController];
    if (!vc || !vc.view.window) {
        self.rewardPromptActive = NO;
        return;
    }

    // Banner should appear at the bottom while the prompt is on screen.
    [VKMediaLoader showAdBanner];

    UIView *overlay = [[UIView alloc] initWithFrame:vc.view.bounds];
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.45];
    overlay.alpha = 0.0;

    CGFloat w = MIN(vc.view.bounds.size.width - 40.0, 360.0);
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 210.0)];
    panel.center = CGPointMake(overlay.bounds.size.width * 0.5, overlay.bounds.size.height * 0.5);
    panel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    panel.layer.cornerRadius = 16.0;
    panel.clipsToBounds = YES;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 16, w - 40, 22)];
    title.text = @"Nova Blast uses left: 0";
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    title.textColor = [UIColor whiteColor];

    UILabel *msg = [[UILabel alloc] initWithFrame:CGRectMake(18, 42, w - 36, 64)];
    msg.text = @"You have 0 uses left. Watch a video to get +1 use?";
    msg.textAlignment = NSTextAlignmentCenter;
    msg.numberOfLines = 0;
    msg.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    msg.textColor = [UIColor colorWithWhite:0.92 alpha:1.0];

    UIButton *watchBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    watchBtn.frame = CGRectMake(20, 128, (w - 60) * 0.5, 44);
    [watchBtn setTitle:@"Watch Video" forState:UIControlStateNormal];
    watchBtn.titleLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightSemibold];
    [watchBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    watchBtn.backgroundColor = [UIColor colorWithRed:0.55 green:0.10 blue:0.80 alpha:1.0];
    watchBtn.layer.cornerRadius = 10.0;
    [watchBtn addTarget:self action:@selector(nb_rewardPromptButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    watchBtn.tag = 1;

    UIButton *noBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    noBtn.frame = CGRectMake(CGRectGetMaxX(watchBtn.frame) + 20.0, 128, (w - 60) * 0.5, 44);
    [noBtn setTitle:@"Not Now" forState:UIControlStateNormal];
    noBtn.titleLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightSemibold];
    [noBtn setTitleColor:[UIColor colorWithWhite:0.95 alpha:1.0] forState:UIControlStateNormal];
    noBtn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    noBtn.layer.cornerRadius = 10.0;
    [noBtn addTarget:self action:@selector(nb_rewardPromptButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    noBtn.tag = 0;

    [panel addSubview:title];
    [panel addSubview:msg];
    [panel addSubview:watchBtn];
    [panel addSubview:noBtn];

    [overlay addSubview:panel];
    [vc.view addSubview:overlay];

    self.rewardPromptOverlay = overlay;
    self.rewardPromptActive = YES;

    [UIView animateWithDuration:0.18 animations:^{
        overlay.alpha = 1.0;
    }];
}

- (void)nb_rewardPromptButtonTapped:(UIButton *)sender {
    NSInteger tag = sender.tag;

    if (tag == 1) {
        NSLog(@"[Nova Blast] 弹窗：用户点击 Watch Video");

        // Dialog + banner disappear together before playing video.
        [self nb_dismissRewardPromptAndCloseBanner];

        __weak typeof(self) weakSelf = self;
        [VKMediaLoader vka_launchRewardCb:^(BOOL earned) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;

            dispatch_async(dispatch_get_main_queue(), ^{
                if (earned) {
                    NSLog(@"[Nova Blast] 奖励视频完成：获得奖励，增加一次使用次数");
                    strongSelf.powerupUses = MIN(strongSelf.powerupUses + 1, kPowerupMax);
                    [strongSelf updatePowerupButton];
                    [strongSelf nb_showAutoToast:@"Reward earned! You gained 1 Nova Blast use."];
                } else {
                    NSLog(@"[Nova Blast] 奖励视频完成：未获得奖励");
                    [strongSelf nb_showAutoToast:@"No reward this time. Try again later."];
                }
            });
        }];
    } else {
        NSLog(@"[Nova Blast] 弹窗：用户点击 Not Now");
        [self nb_dismissRewardPromptAndCloseBanner];
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// 泡泡龙式触摸输入（由 SpriteKit 原生 touches* 进入）
//
// 设计原则:
//  • touchBegan  → 判断区域; 若在游戏区域则标记 _aimActive = YES, 记录瞄准点
//  • touchMoved  → 只要 _aimActive 就更新瞄准线 (不做任何早期 return)
//  • touchEnded  → 只要 _aimActive 且状态为 Aiming 就发射; 无论如何都清除标记
//
// 关键改变:
//  • 用 _aimActive 替代 _isTouching — 语义更清晰, 设置时机更明确
//  • 不依赖任何 nodeAtPoint: — 完全用 Y 坐标区间判断区域
//  • 发射逻辑和区域判断完全解耦 — 任何路径都能正确发射或正确忽略
// ═══════════════════════════════════════════════════════════════════════════

#pragma mark - Precise button hit tests

- (BOOL)isPointOnBackButton:(CGPoint)pt {
    if (!_backButton || !_backButton.parent) return NO;
    CGRect tapRect = CGRectInset(_backButton.frame, -22.0, -14.0); // enlarge for finger taps
    return CGRectContainsPoint(tapRect, pt);
}

- (BOOL)isPointOnPowerupButton:(CGPoint)pt {
    if (!_powerupButton || !_powerupButton.parent) return NO;
    CGRect frame = [_powerupButton calculateAccumulatedFrame];
    CGRect tapRect = CGRectInset(frame, -12.0, -10.0);
    return CGRectContainsPoint(tapRect, pt);
}

- (BOOL)isPointOnRestartButton:(CGPoint)pt {
    if (!_restartButton || !_restartButton.parent) return NO;
    CGRect frame = [_restartButton calculateAccumulatedFrame];
    CGRect tapRect = CGRectInset(frame, -12.0, -10.0);
    return CGRectContainsPoint(tapRect, pt);
}

#pragma mark - Public touch entry points

- (void)aimGestureBegan:(CGPoint)pt {
    [self dbg:[NSString stringWithFormat:@"began %@", NSStringFromCGPoint(pt)]];
    // ── 1. Game-over screen: any tap restarts ──────────────────────
    if (_state == NBGameStateGameOver) {
        // 如果点的是“重新开始”按钮：重开并展示插页广告（保持 Nova Blast uses）
        if ([self isPointOnRestartButton:pt]) {
            [self dbg:@"began->restart button (game over)"];
            BOOL ok = [self restartLevelKeepingUses];
            if (ok) {
                [VKMediaLoader vka_appendSupportNote:@"[广告规则] 重启成功(游戏结束界面) ：准备展示插页广告"];
                [VKMediaLoader vka_showInterstitial];
            }
            return;
        }

        // Check for dedicated menu button; otherwise restart
        SKNode *n = [self nodeAtPoint:pt];
        while (n && n != self) {
            if ([n.name isEqualToString:@"btnMenu"]) {
                [self.gameDelegate gameSceneDidRequestMainMenu]; return;
            }
            n = n.parent;
        }
        [self startNewGame];
        return;
    }

    // ── 2. Explicit UI hit-test (only real buttons intercept touches) ──
    if ([self isPointOnBackButton:pt]) {
        [self dbg:@"began->back button"];
        [self.gameDelegate gameSceneDidRequestMainMenu];
        return;
    }
    if ([self isPointOnRestartButton:pt]) {
        [self dbg:@"began->restart button"];

        BOOL ok = [self restartLevelKeepingUses];
        if (ok) {
            [VKMediaLoader vka_appendSupportNote:@"[广告规则] 重启成功：准备展示插页广告(按你的规则：只在重启后展示)"];
            [VKMediaLoader vka_showInterstitial];
        }
        return;
    }
    if ([self isPointOnPowerupButton:pt]) {
        [self dbg:@"began->powerup button"];
        if (_powerupUses > 0) {
            // Nova Blast 只有在瞄准状态时允许实际触发
            if (_state == NBGameStateAiming) [self activateNovaBeast];
        } else {
            // 用途不足时，无论当前状态，都弹出视频激励弹窗 + 横幅
            [self nb_presentRewardVideoPromptIfNeeded];
        }
        return; // do NOT start aiming when tapping the power-up button
    }

    // ── 3. Start aiming (anywhere else on screen) ──────────────────
    if (_state != NBGameStateAiming) {
        [self dbg:[NSString stringWithFormat:@"began ignored state=%@", NBStateName(_state)]];
        return;
    }

    _aimActive = YES;
    _aimPt     = pt;

    CGVector dir = [self shootDirToward:pt];
    [self drawAimLine:dir];
    [self dbg:[NSString stringWithFormat:@"began aim dir=(%.2f,%.2f)", dir.dx, dir.dy]];
}

- (void)aimGestureMoved:(CGPoint)pt {
    // Update aim line whenever a game-area touch is dragging.
    // No zone check here — allow dragging from game area into safe areas
    // (player naturally drags to extreme edges when aiming).
    if (!_aimActive || _state != NBGameStateAiming) return;

    _aimPt = pt;
    CGVector dir = [self shootDirToward:pt];
    [self drawAimLine:dir];
    [self dbg:[NSString stringWithFormat:@"moved %@", NSStringFromCGPoint(pt)]];
}

- (void)aimGestureEnded:(CGPoint)pt {
    BOOL hadAim = _aimActive;
    _aimActive = NO; // clear first, avoid double fire
    [_aimNode removeFromParent];
    _aimNode = nil;

    // Must still be in Aiming state (not Shooting / Advancing / GameOver)
    if (_state != NBGameStateAiming) {
        [self dbg:[NSString stringWithFormat:@"ended ignored state=%@", NBStateName(_state)]];
        return;
    }
    if (!hadAim && ([self isPointOnBackButton:pt] || [self isPointOnPowerupButton:pt] || [self isPointOnRestartButton:pt])) {
        [self dbg:@"ended on button, no fire"];
        return;
    }

    // Tap-to-shoot fallback: even if hadAim==NO, an ended touch on gameplay area still fires.
    // This makes single taps robust across edge cases where began was intercepted/cancelled.
    CGVector dir = [self shootDirToward:pt];
    [self dbg:[NSString stringWithFormat:@"ended hadAim=%@ dir=(%.2f,%.2f)",
               hadAim ? @"Y" : @"N", dir.dx, dir.dy]];
    [self fireDirection:dir];
}

#pragma mark - Direction helpers

/// Compute a normalised, upward-clamped direction from the launch point to `target`.
/// ALWAYS returns a non-zero vector (falls back to straight-up).
- (CGVector)shootDirToward:(CGPoint)target {
    CGFloat dx  = target.x - _launchX;
    CGFloat dy  = target.y - _launchY;
    CGFloat len = hypot(dx, dy);

    // If the finger is essentially ON the ball, shoot straight up
    if (len < 5.0) return CGVectorMake(0, 1);

    dx /= len;
    dy /= len;

    // Enforce minimum upward angle (5°) so balls never fly sideways or down
    static const CGFloat kMinUpSin = 0.08715574;  // sin(5°)
    if (dy < kMinUpSin) {
        // Preserve left/right sign; snap to minimum angle
        CGFloat sign = (dx >= 0) ? 1.0 : -1.0;
        dy = kMinUpSin;
        dx = sign * sqrt(MAX(0.0, 1.0 - dy * dy));
    }
    return CGVectorMake(dx, dy);
}

/// Walk the SpriteKit node tree to find the first named ancestor.
- (NSString *)nodeNameAt:(CGPoint)pt {
    SKNode *node = [self nodeAtPoint:pt];
    while (node && node != self) {
        if (node.name.length > 0) return node.name;
        node = node.parent;
    }
    return @"";
}

// ─────────────────────────────────────────────
// SpriteKit 原生触摸方法（主要输入通道）
//
// [touch locationInNode:self] 直接返回场景坐标系坐标（Y 轴向上，原点左下角），
// SpriteKit 自动处理 UIKit→场景 的坐标转换，无需手动翻转 Y 轴。
// touchesCancelled: 与 touchesEnded: 处理完全相同，确保系统取消触摸时球也能发射。
// ─────────────────────────────────────────────

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self aimGestureBegan:[touches.anyObject locationInNode:self]];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self aimGestureMoved:[touches.anyObject locationInNode:self]];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self aimGestureEnded:[touches.anyObject locationInNode:self]];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    // 系统手势取消时也发射，不能让球卡在 Aiming 状态
    [self aimGestureEnded:[touches.anyObject locationInNode:self]];
}

// ─────────────────────────────────────────────
// Update loop
// ─────────────────────────────────────────────
- (void)update:(CFTimeInterval)currentTime {
    if (_state != NBGameStateShooting) return;

    if (_shootStartTime < 0) _shootStartTime = currentTime;

    // Turn timeout safety net
    if (currentTime - _shootStartTime > kTurnTimeout) {
        for (SKNode *ball in [_flyingBalls copy]) [self ballLanded:ball];
        return;
    }

    for (SKNode *ball in [_flyingBalls copy]) {
        if (!ball.physicsBody) continue;

        // Normalize speed
        CGVector v  = ball.physicsBody.velocity;
        CGFloat spd = hypot(v.dx, v.dy);
        if (spd > 1.0 && fabs(spd - kBallSpeed) > 30.0) {
            CGFloat sc = kBallSpeed / spd;
            ball.physicsBody.velocity = CGVectorMake(v.dx * sc, v.dy * sc);
        }

        // Out of bounds safety
        if (ball.position.y < _launchY - 40 || ball.position.y > self.size.height + 60) {
            [self ballLanded:ball];
        }
    }
}

// ─────────────────────────────────────────────
// Game Over
// ─────────────────────────────────────────────
- (void)triggerGameOver {
    _state = NBGameStateGameOver;
    [self playGameOverSfx];
    [self dbg:@"triggerGameOver"];

    // Stop all flying balls
    for (SKNode *ball in [_flyingBalls copy]) {
        ball.physicsBody = nil;
        [ball runAction:[SKAction fadeOutWithDuration:0.2]];
    }
    [_flyingBalls removeAllObjects];
    _activeBalls = 0;

    // Save score
    NSInteger best = [[NSUserDefaults standardUserDefaults] integerForKey:@"NBBestScore"];
    if (_score > best) {
        [[NSUserDefaults standardUserDefaults] setInteger:_score forKey:@"NBBestScore"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        best = _score;
    }

    // Build overlay
    CGFloat W = self.size.width, H = self.size.height;

    SKSpriteNode *overlay = [SKSpriteNode
        spriteNodeWithColor:[UIColor colorWithRed:0.01 green:0.01 blue:0.10 alpha:0.88]
                       size:self.size];
    overlay.position  = CGPointMake(W * 0.5, H * 0.5);
    overlay.zPosition = 200;
    overlay.alpha     = 0;
    overlay.name      = @"gameOverOverlay";
    [self addChild:overlay];

    CGFloat cy = 110;

    SKLabelNode *goLbl = [SKLabelNode labelNodeWithFontNamed:@"AvenirNext-Heavy"];
    goLbl.text      = @"GAME OVER";
    goLbl.fontSize  = 40;
    goLbl.fontColor = [UIColor colorWithRed:1.0 green:0.18 blue:0.18 alpha:1.0];
    goLbl.position  = CGPointMake(0, cy);
    goLbl.verticalAlignmentMode = SKLabelVerticalAlignmentModeCenter;
    goLbl.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    [overlay addChild:goLbl];

    SKLabelNode *scoreLbl = [SKLabelNode labelNodeWithFontNamed:@"AvenirNext-Bold"];
    scoreLbl.text      = [NSString stringWithFormat:@"Score: %ld", (long)_score];
    scoreLbl.fontSize  = 26;
    scoreLbl.fontColor = [UIColor colorWithRed:1.0 green:0.85 blue:0.0 alpha:1.0];
    scoreLbl.position  = CGPointMake(0, cy - 56);
    scoreLbl.verticalAlignmentMode = SKLabelVerticalAlignmentModeCenter;
    scoreLbl.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    [overlay addChild:scoreLbl];

    NSString *bestText = (best == _score && _score > 0) ?
        [NSString stringWithFormat:@"🏆 New Best: %ld", (long)best] :
        [NSString stringWithFormat:@"Best: %ld", (long)best];
    SKLabelNode *bestLbl = [SKLabelNode labelNodeWithFontNamed:@"AvenirNext-Regular"];
    bestLbl.text      = bestText;
    bestLbl.fontSize  = 17;
    bestLbl.fontColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    bestLbl.position  = CGPointMake(0, cy - 88);
    bestLbl.verticalAlignmentMode = SKLabelVerticalAlignmentModeCenter;
    bestLbl.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    [overlay addChild:bestLbl];

    SKLabelNode *turnLbl = [SKLabelNode labelNodeWithFontNamed:@"AvenirNext-Regular"];
    turnLbl.text      = [NSString stringWithFormat:@"Survived %ld Turns  |  Lv.%ld", (long)_turnCount, (long)_level];
    turnLbl.fontSize  = 14;
    turnLbl.fontColor = [UIColor colorWithWhite:0.4 alpha:1.0];
    turnLbl.position  = CGPointMake(0, cy - 116);
    turnLbl.verticalAlignmentMode = SKLabelVerticalAlignmentModeCenter;
    turnLbl.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    [overlay addChild:turnLbl];

    // Play Again button
    SKNode *playBtn = [self buildOverlayButton:@"PLAY AGAIN"
                                     color:[UIColor colorWithRed:0.15 green:0.78 blue:1.0 alpha:1.0]];
    playBtn.position = CGPointMake(0, cy - 168);
    playBtn.name     = @"btnPlayAgain";
    [overlay addChild:playBtn];

    // Main Menu button
    SKNode *menuBtn = [self buildOverlayButton:@"MAIN MENU"
                                     color:[UIColor colorWithRed:0.28 green:0.28 blue:0.55 alpha:1.0]];
    menuBtn.position = CGPointMake(0, cy - 240);
    menuBtn.name     = @"btnMenu";
    [overlay addChild:menuBtn];

    [overlay runAction:[SKAction fadeInWithDuration:0.35]];
}

- (SKNode *)buildOverlayButton:(NSString *)title color:(UIColor *)col {
    SKNode *btn = [SKNode node];

    UIBezierPath *btnPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(-100, -29, 200, 58)
                                                        cornerRadius:14.0];
    SKShapeNode *bg = [SKShapeNode shapeNodeWithPath:btnPath.CGPath];
    bg.fillColor   = col;
    bg.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.25];
    bg.lineWidth   = 1.5;
    bg.glowWidth   = 6.0;
    bg.name        = btn.name; // inherit
    [btn addChild:bg];

    SKLabelNode *lbl = [SKLabelNode labelNodeWithFontNamed:@"AvenirNext-Heavy"];
    lbl.text      = title;
    lbl.fontSize  = 20;
    lbl.fontColor = [UIColor whiteColor];
    lbl.verticalAlignmentMode   = SKLabelVerticalAlignmentModeCenter;
    lbl.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeCenter;
    [btn addChild:lbl];

    return btn;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

@end

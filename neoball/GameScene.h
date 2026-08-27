#import <SpriteKit/SpriteKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol GameSceneDelegate <NSObject>
- (void)gameSceneDidRequestMainMenu;
@end

@interface GameScene : SKScene

@property (nonatomic, weak, nullable) id<GameSceneDelegate> gameDelegate;

// UIKit input bridge (called by GameViewController gesture handlers)
- (void)aimGestureBegan:(CGPoint)scenePt;
- (void)aimGestureMoved:(CGPoint)scenePt;
- (void)aimGestureEnded:(CGPoint)scenePt;

@end

NS_ASSUME_NONNULL_END

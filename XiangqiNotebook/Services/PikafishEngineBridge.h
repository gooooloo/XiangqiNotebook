#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PikafishEvaluationResult : NSObject

@property (nonatomic, readonly) NSInteger score;
@property (nonatomic, readonly) NSInteger depth;
@property (nonatomic, readonly) NSInteger timeMs;
@property (nonatomic, readonly) NSInteger hashfull;
@property (nonatomic, readonly, nullable) NSString *bestMove;

@end

@interface PikafishEngineBridge : NSObject

- (void)loadNetwork:(NSString *)nnueFilePath NS_SWIFT_NAME(loadNetwork(path:));
- (void)setPositionWithFEN:(NSString *)fen
                      moves:(NSArray<NSString *> *)moves NS_SWIFT_NAME(setPosition(fen:moves:));
- (void)setThreads:(NSInteger)threads NS_SWIFT_NAME(setThreads(_:));
- (void)setHashMB:(NSInteger)megabytes NS_SWIFT_NAME(setHashMB(_:));
- (void)goWithMovetimeMs:(NSInteger)movetimeMs
              completion:(void (^)(PikafishEvaluationResult * _Nullable result))completion
    NS_SWIFT_NAME(go(movetimeMs:completion:));
- (void)stop;
- (void)waitForSearchFinished NS_SWIFT_NAME(waitForSearchFinished());
- (void)searchClear NS_SWIFT_NAME(searchClear());

@end

NS_ASSUME_NONNULL_END

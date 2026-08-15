#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PikafishEvaluationResult : NSObject

@property (nonatomic, readonly) NSInteger score;
@property (nonatomic, readonly) NSInteger depth;
@property (nonatomic, readonly) NSInteger timeMs;
@property (nonatomic, readonly) NSInteger hashfull;
@property (nonatomic, readonly, nullable) NSString *bestMove;

@end

/// MultiPV 分析中的一条候选线路
@interface PikafishPVLineResult : NSObject

/// 1-based 排名，1 即引擎首选
@property (nonatomic, readonly) NSInteger multipv;
/// 走子方视角的厘兵分（杀棋折算到 ±30000 附近）
@property (nonatomic, readonly) NSInteger scoreCp;
/// 杀棋步数：正数为走子方 N 步成杀，负数为 N 步被杀；非杀棋为 nil
@property (nonatomic, readonly, nullable) NSNumber *mateInMoves;
@property (nonatomic, readonly) NSInteger depth;
/// UCI 着法序列
@property (nonatomic, readonly) NSArray<NSString *> *pvMoves;

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

/// MultiPV 分析：返回前 multiPV 条候选线路，各含分数、深度与主变。
///
/// 与 `goWithMovetimeMs:` 各自在搜索前声明所需的 MultiPV，互不污染——
/// 单线路估分只认排名第一的线路，若残留 MultiPV 会拿到排名靠后的差着分数，
/// 进而把错误分数写进数据库。
- (void)goMultiPVWithMovetimeMs:(NSInteger)movetimeMs
                        multiPV:(NSInteger)multiPV
                     completion:(void (^)(NSArray<PikafishPVLineResult *> *lines))completion
    NS_SWIFT_NAME(goMultiPV(movetimeMs:multiPV:completion:));
- (void)stop;
- (void)waitForSearchFinished NS_SWIFT_NAME(waitForSearchFinished());
- (void)searchClear NS_SWIFT_NAME(searchClear());

@end

NS_ASSUME_NONNULL_END

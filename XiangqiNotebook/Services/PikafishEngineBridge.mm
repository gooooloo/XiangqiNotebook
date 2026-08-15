#import "PikafishEngineBridge.h"

#include "bitboard.h"
#include "engine.h"
#include "position.h"
#include "score.h"

#include <map>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

namespace {

/// MultiPV 搜索期间逐条累积的线路快照。
/// 存 std::string 而非 NSString，避免 ARC 对象混进 STL 容器。
struct PVLineSnapshot {
    NSInteger scoreCp = 0;
    /// 用一对 POD 字段而不是可空 NSNumber，与上面「不让 ARC 对象混进 STL 容器」一致
    bool isMate = false;
    NSInteger mateInMoves = 0;
    NSInteger depth = 0;
    std::vector<std::string> moves;
};

std::vector<std::string> splitUCIMoves(std::string_view pv) {
    std::vector<std::string> moves;
    std::istringstream iss{std::string(pv)};
    std::string token;
    while (iss >> token) {
        moves.push_back(token);
    }
    return moves;
}

void ensureGlobalEngineStateInitialized() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Stockfish::Bitboards::init();
        Stockfish::Position::init();
    });
}

/// 杀棋步数（回合数，非半步）。正数为走子方成杀，负数为被杀；非杀棋返回 nil。
/// 折算规则与 centipawnValue 保持一致，两者必须同源，否则会出现
/// 「分数说 3 步杀、mate 说 2 步杀」这种自相矛盾
NSInteger mateInMoves(const Stockfish::Score& score) {
    int plies = score.get<Stockfish::Score::Mate>().plies;
    return (plies > 0 ? (plies + 1) : plies) / 2;
}

NSInteger centipawnValue(const Stockfish::Score& score) {
    if (score.is<Stockfish::Score::Mate>()) {
        NSInteger moves = mateInMoves(score);
        return moves > 0 ? 30000 - moves : -30000 - moves;
    }
    return score.get<Stockfish::Score::InternalUnits>().value;
}

}  // namespace

@implementation PikafishEvaluationResult

- (instancetype)initWithScore:(NSInteger)score
                         depth:(NSInteger)depth
                        timeMs:(NSInteger)timeMs
                      hashfull:(NSInteger)hashfull
                      bestMove:(NSString * _Nullable)bestMove {
    self = [super init];
    if (self) {
        _score = score;
        _depth = depth;
        _timeMs = timeMs;
        _hashfull = hashfull;
        _bestMove = bestMove;
    }
    return self;
}

@end

@implementation PikafishPVLineResult

- (instancetype)initWithMultipv:(NSInteger)multipv
                        scoreCp:(NSInteger)scoreCp
                    mateInMoves:(NSNumber * _Nullable)mateInMoves
                          depth:(NSInteger)depth
                        pvMoves:(NSArray<NSString *> *)pvMoves {
    self = [super init];
    if (self) {
        _multipv = multipv;
        _scoreCp = scoreCp;
        _mateInMoves = mateInMoves;
        _depth = depth;
        _pvMoves = pvMoves;
    }
    return self;
}

@end

@implementation PikafishEngineBridge {
    std::unique_ptr<Stockfish::Engine> _engine;
    NSInteger _lastScore;
    NSInteger _lastDepth;
    NSInteger _lastTimeMs;
    NSInteger _lastHashfull;
    /// MultiPV 搜索期间按排名累积的线路；同一排名后来的（搜索更深的）覆盖先前的，
    /// 与 macOS 版 PikafishService.parsePVLines 的语义一致
    std::map<size_t, PVLineSnapshot> _pvLines;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        ensureGlobalEngineStateInitialized();
        _engine = std::make_unique<Stockfish::Engine>();
        _engine->set_on_verify_networks([](std::string_view info) {
            NSLog(@"[Pikafish] %s", std::string(info).c_str());
        });
        _engine->set_on_update_no_moves([](const Stockfish::Search::InfoShort&) {});
        _engine->set_on_iter([](const Stockfish::Search::InfoIteration&) {});
        __weak PikafishEngineBridge *weakSelf = self;
        _engine->set_on_update_full([weakSelf](const Stockfish::Search::InfoFull& info) {
            PikafishEngineBridge *strongSelf = weakSelf;
            if (!strongSelf) return;

            const NSInteger scoreCp = centipawnValue(info.score);
            strongSelf->_lastTimeMs = (NSInteger) info.timeMs;
            strongSelf->_lastHashfull = info.hashfull;

            // 单线路估分只认排名第一的线路。MultiPV > 1 时若照单全收，
            // _lastScore 会停在最后播报的那条（可能是第 5 名的差着）
            if (info.multiPV <= 1) {
                strongSelf->_lastScore = scoreCp;
                strongSelf->_lastDepth = info.depth;
            }

            PVLineSnapshot line;
            line.scoreCp = scoreCp;
            line.isMate = info.score.is<Stockfish::Score::Mate>();
            if (line.isMate) {
                line.mateInMoves = mateInMoves(info.score);
            }
            line.depth = info.depth;
            line.moves = splitUCIMoves(info.pv);
            strongSelf->_pvLines[info.multiPV] = std::move(line);
        });
    }
    return self;
}

- (void)loadNetwork:(NSString *)nnueFilePath {
    std::istringstream iss("name EvalFile value " + std::string(nnueFilePath.UTF8String));
    _engine->get_options().setoption(iss);
}

- (void)setPositionWithFEN:(NSString *)fen moves:(NSArray<NSString *> *)moves {
    std::vector<std::string> uciMoves;
    uciMoves.reserve(moves.count);
    for (NSString *move in moves) {
        uciMoves.push_back(std::string(move.UTF8String));
    }
    _engine->set_position(std::string(fen.UTF8String), uciMoves);
    _lastScore = 0;
    _lastDepth = 0;
    _lastTimeMs = 0;
    _lastHashfull = 0;
    _pvLines.clear();
}

- (void)setThreads:(NSInteger)threads {
    std::istringstream iss("name Threads value " + std::to_string((long) threads));
    _engine->get_options().setoption(iss);
}

- (void)setHashMB:(NSInteger)megabytes {
    std::istringstream iss("name Hash value " + std::to_string((long) megabytes));
    _engine->get_options().setoption(iss);
}

- (void)setMultiPVOption:(NSInteger)multiPV {
    std::istringstream iss("name MultiPV value " + std::to_string((long) multiPV));
    _engine->get_options().setoption(iss);
}

- (void)goWithMovetimeMs:(NSInteger)movetimeMs
               completion:(void (^)(PikafishEvaluationResult * _Nullable))completion {
    _pvLines.clear();
    // 每次搜索前显式声明要单线路。不靠 goMultiPV 事后复位——那要在引擎的 bestmove
    // 回调里改 option，此时引擎可能还持着内部锁；在这里声明既安全又不依赖清理路径。
    [self setMultiPVOption:1];
    void (^completionCopy)(PikafishEvaluationResult * _Nullable) = [completion copy];
    __weak PikafishEngineBridge *weakSelf = self;
    _engine->set_on_bestmove([weakSelf, completionCopy](std::string_view bestmove, std::string_view ponder) {
        (void) ponder;
        PikafishEngineBridge *strongSelf = weakSelf;
        if (!strongSelf) {
            completionCopy(nil);
            return;
        }

        NSString *move = nil;
        if (!bestmove.empty() && bestmove != "(none)") {
            move = [NSString stringWithUTF8String:std::string(bestmove).c_str()];
        }

        PikafishEvaluationResult *result =
          [[PikafishEvaluationResult alloc] initWithScore:strongSelf->_lastScore
                                                     depth:strongSelf->_lastDepth
                                                    timeMs:strongSelf->_lastTimeMs
                                                  hashfull:strongSelf->_lastHashfull
                                                  bestMove:move];
        completionCopy(result);
    });

    Stockfish::Search::LimitsType limits;
    limits.startTime = Stockfish::now();
    limits.movetime  = (Stockfish::TimePoint) movetimeMs;
    _engine->go(limits);
}

- (void)goMultiPVWithMovetimeMs:(NSInteger)movetimeMs
                        multiPV:(NSInteger)multiPV
                     completion:(void (^)(NSArray<PikafishPVLineResult *> *))completion {
    _pvLines.clear();
    [self setMultiPVOption:multiPV];

    void (^completionCopy)(NSArray<PikafishPVLineResult *> *) = [completion copy];
    __weak PikafishEngineBridge *weakSelf = self;
    _engine->set_on_bestmove([weakSelf, completionCopy](std::string_view bestmove, std::string_view ponder) {
        (void) bestmove;
        (void) ponder;
        PikafishEngineBridge *strongSelf = weakSelf;
        if (!strongSelf) {
            completionCopy(@[]);
            return;
        }

        NSMutableArray<PikafishPVLineResult *> *lines = [NSMutableArray array];
        // std::map 按 key 升序遍历，排名天然有序
        for (const auto& [rank, snapshot] : strongSelf->_pvLines) {
            NSMutableArray<NSString *> *moves =
              [NSMutableArray arrayWithCapacity:snapshot.moves.size()];
            for (const auto& uci : snapshot.moves) {
                [moves addObject:[NSString stringWithUTF8String:uci.c_str()]];
            }
            [lines addObject:[[PikafishPVLineResult alloc]
                              initWithMultipv:(NSInteger) rank
                                      scoreCp:snapshot.scoreCp
                                  mateInMoves:(snapshot.isMate ? @(snapshot.mateInMoves) : nil)
                                        depth:snapshot.depth
                                      pvMoves:moves]];
        }
        completionCopy(lines);
    });

    Stockfish::Search::LimitsType limits;
    limits.startTime = Stockfish::now();
    limits.movetime  = (Stockfish::TimePoint) movetimeMs;
    _engine->go(limits);
}

- (void)stop {
    _engine->stop();
}

- (void)waitForSearchFinished {
    _engine->wait_for_search_finished();
}

- (void)searchClear {
    _engine->search_clear();
}

@end

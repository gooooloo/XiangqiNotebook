#import "PikafishEngineBridge.h"

#include "bitboard.h"
#include "engine.h"
#include "position.h"
#include "score.h"

#include <memory>
#include <sstream>
#include <string>
#include <vector>

namespace {

void ensureGlobalEngineStateInitialized() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Stockfish::Bitboards::init();
        Stockfish::Position::init();
    });
}

NSInteger centipawnValue(const Stockfish::Score& score) {
    if (score.is<Stockfish::Score::Mate>()) {
        int plies = score.get<Stockfish::Score::Mate>().plies;
        int moves = (plies > 0 ? (plies + 1) : plies) / 2;
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

@implementation PikafishEngineBridge {
    std::unique_ptr<Stockfish::Engine> _engine;
    NSInteger _lastScore;
    NSInteger _lastDepth;
    NSInteger _lastTimeMs;
    NSInteger _lastHashfull;
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
            strongSelf->_lastScore = centipawnValue(info.score);
            strongSelf->_lastDepth = info.depth;
            strongSelf->_lastTimeMs = (NSInteger) info.timeMs;
            strongSelf->_lastHashfull = info.hashfull;
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
}

- (void)setThreads:(NSInteger)threads {
    std::istringstream iss("name Threads value " + std::to_string((long) threads));
    _engine->get_options().setoption(iss);
}

- (void)setHashMB:(NSInteger)megabytes {
    std::istringstream iss("name Hash value " + std::to_string((long) megabytes));
    _engine->get_options().setoption(iss);
}

- (void)goWithMovetimeMs:(NSInteger)movetimeMs
               completion:(void (^)(PikafishEvaluationResult * _Nullable))completion {
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

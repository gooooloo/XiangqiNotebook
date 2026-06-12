import Foundation

func normalizeFen(_ fen: String) -> String {
    // We hack the fen after - - as we don't need the rest of the information, and we need to be compatible with the old code
    // TODO: We should remove this hack after the old code is removed
    guard let boardAndTurn = fen.split(separator: "-").first else { return fen }
    return boardAndTurn.trimmingCharacters(in: .whitespaces) + " - - 1 1"
}

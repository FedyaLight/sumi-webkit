import Foundation

struct AuxiliaryWindowNestingPolicy: Equatable {
    let maximumDepth: Int

    init(maximumDepth: Int = 3) {
        precondition(maximumDepth > 0)
        self.maximumDepth = maximumDepth
    }

    func allowsPresentation(at depth: Int) -> Bool {
        depth < maximumDepth
    }

    func childDepth(after parentDepth: Int) -> Int? {
        let childDepth = parentDepth + 1
        return allowsPresentation(at: childDepth) ? childDepth : nil
    }
}

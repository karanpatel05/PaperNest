public enum ScanCardSide: String, Sendable {
    case front, back
}

/// Which side of a card each capture is, while cards are being scanned.
///
/// A kept capture is a front, and its back is offered. Only when the person
/// chooses to scan the back is the next kept capture that front's back;
/// anything else, another capture or Continue, leaves the front on its own.
/// The two sides stay separate pages and are edited separately.
public struct ScanCardPairing<PageID: Hashable & Sendable>: Sendable {
    /// The front just kept, whose back is being asked about.
    public private(set) var offer: PageID?
    private var awaitingBackOf: PageID?
    private var sides: [PageID: ScanCardSide] = [:]
    private var partners: [PageID: PageID] = [:]

    public init() {}

    /// The side the next kept capture will be.
    public var nextSide: ScanCardSide { awaitingBackOf == nil ? .front : .back }

    public func side(of page: PageID) -> ScanCardSide? { sides[page] }

    /// The other side of the same card, when both were scanned and both remain.
    public func partner(of page: PageID) -> PageID? { partners[page] }

    /// A capture was kept in Card mode. For a back, `front` is the page it
    /// belongs after.
    public mutating func keep(_ page: PageID) -> (side: ScanCardSide, front: PageID?) {
        if let front = awaitingBackOf {
            awaitingBackOf = nil
            offer = nil
            sides[page] = .back
            partners[page] = front
            partners[front] = page
            return (.back, front)
        }
        sides[page] = .front
        offer = page
        return (.front, nil)
    }

    /// The answer "Scan back" to the offer.
    public mutating func scanBack() {
        guard let front = offer else { return }
        awaitingBackOf = front
        offer = nil
    }

    /// The answer "Continue" to the offer.
    public mutating func continueWithFrontOnly() {
        offer = nil
    }

    /// Pages were deleted from the queue.
    public mutating func forget(_ pages: Set<PageID>) {
        for page in pages {
            sides[page] = nil
            if let other = partners.removeValue(forKey: page) { partners[other] = nil }
        }
        if let front = awaitingBackOf, pages.contains(front) { awaitingBackOf = nil }
        if let front = offer, pages.contains(front) { offer = nil }
    }

    /// The mode was left: no back is owed and no question stays on screen.
    public mutating func cancelPending() {
        awaitingBackOf = nil
        offer = nil
    }
}

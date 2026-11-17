import CoreGraphics
import Foundation

public typealias SavedTemplateID = Identifier<SavedPageTemplate>

/// A page someone saved to start other pages from: its paper or its own
/// background (a letterhead, a form) with its crop and rotation, and what is
/// drawn and typed on it.
///
/// A copy, not a link: a page made from it is an ordinary page, and changing
/// or deleting the template leaves such pages as they are. Private comments
/// and recognized text are never part of one.
public struct SavedPageTemplate: Hashable, Sendable, Identifiable {
    public var id: SavedTemplateID
    public var name: String
    public var sourceSize: CGSize
    public var content: PageContent
    public var transform: PageTransform
    /// Ink, text boxes and placed pictures, in paint order.
    public var objects: [PageObject.Payload]
    public var createdAt: Date
    public var modifiedAt: Date

    public init(id: SavedTemplateID = .make(), name: String, sourceSize: CGSize, content: PageContent,
                transform: PageTransform, objects: [PageObject.Payload], createdAt: Date, modifiedAt: Date) {
        self.id = id
        self.name = name
        self.sourceSize = sourceSize
        self.content = content
        self.transform = transform
        self.objects = objects
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    /// Every original it keeps: its background's and its placed pictures'.
    public var assetIDs: Set<AssetID> {
        var ids = Set(objects.compactMap { payload -> AssetID? in
            if case .image(let image) = payload { return image.assetID }
            return nil
        })
        if let background = content.assetID { ids.insert(background) }
        return ids
    }
}

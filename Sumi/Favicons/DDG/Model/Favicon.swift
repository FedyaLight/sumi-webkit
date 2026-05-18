//
//  Favicon.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Cocoa
import Foundation
import ImageIO

enum SumiFaviconImagePolicy {
    static let maxDecodedPixelSize = 256
    static let maxLauncherDisplayPixelSize = 64
}

struct Favicon {

    enum Relation: Int {
        case favicon = 2
        case icon = 1
        case other = 0

        init(relationString: String) {
            if relationString == "favicon" {
                self = .favicon
                return
            }
            if relationString.contains("icon") {
                self = .icon
                return
            }
            self = .other
        }
    }

    enum SizeCategory: CGFloat {
        case noImage = 0
        case tiny = 1
        case small = 32
        case medium = 132
        case large = 264
        case huge = 2048

        init(imageSize: CGSize?) {
            guard let imageSize = imageSize else {
                self = .noImage
                return
            }
            let longestSide = max(imageSize.width, imageSize.height)
            switch longestSide {
            case 0: self = .noImage
            case 1..<Self.small.rawValue:  self = .tiny
            case Self.small.rawValue..<Self.medium.rawValue: self = .small
            case Self.medium.rawValue..<Self.large.rawValue: self = .medium
            case Self.large.rawValue..<Self.huge.rawValue: self = .large
            default: self = .huge
            }
        }

        /**
         * Returns the next smaller size cattegory, or nil in case of `.noImage`.
         */
        var smaller: SizeCategory? {
            switch self {
            case .noImage:
                return nil
            case .tiny:
                return .noImage
            case .small:
                return .tiny
            case .medium:
                return .small
            case .large:
                return .medium
            case .huge:
                return .large
            }
        }
    }

    init(identifier: UUID, url: URL, image: NSImage?, imageData: Data? = nil, relationString: String, documentUrl: URL, dateCreated: Date) {
        self.init(identifier: identifier,
                  url: url, image: image,
                  imageData: imageData,
                  relation: Relation(relationString: relationString),
                  documentUrl: documentUrl,
                  dateCreated: dateCreated)
    }

    init(identifier: UUID, url: URL, image: NSImage?, imageData: Data? = nil, relation: Relation, documentUrl: URL, dateCreated: Date) {
        let decodedImage = image ?? imageData.flatMap {
            NSImage.sumiDecodedFaviconImage(data: $0, maxPixelSize: SumiFaviconImagePolicy.maxDecodedPixelSize)
        }

        // Avoid storing or using of non-valid or huge images
        if let image = decodedImage, image.isValid {
            let sizeCategory = SizeCategory(imageSize: image.size)
            if sizeCategory == .huge || sizeCategory == .noImage {
                self.image = nil
            } else {
                self.image = image
            }
        } else {
            self.image = nil
        }

        self.identifier = identifier
        self.url = url
        self.imageData = imageData
        self.relation = relation
        self.sizeCategory = SizeCategory(imageSize: self.image?.size)
        self.documentUrl = documentUrl
        self.dateCreated = dateCreated
    }

    let identifier: UUID
    let url: URL
    let image: NSImage?
    let imageData: Data?
    let relation: Relation
    let sizeCategory: SizeCategory
    let documentUrl: URL
    let dateCreated: Date

    var longestSide: CGFloat {
        guard let image = image else {
            return 0
        }

        return max(image.size.width, image.size.height)
    }

    var withoutImageData: Favicon {
        Favicon(
            identifier: identifier,
            url: url,
            image: image,
            relation: relation,
            documentUrl: documentUrl,
            dateCreated: dateCreated
        )
    }
}

extension NSImage {
    static func sumiDecodedFaviconImage(data: Data, maxPixelSize: Int) -> NSImage? {
        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary

        if let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) {
            let index = source.sumiBestFaviconImageIndex(targetPixelSize: maxPixelSize)
            let thumbnailOptions = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCache: false,
                kCGImageSourceShouldCacheImmediately: false
            ] as CFDictionary

            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, index, thumbnailOptions) {
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
        }

        guard let image = NSImage(data: data), image.isValid else {
            return nil
        }
        return image.sumiFaviconImageConstrained(maxLongestSide: CGFloat(maxPixelSize))
    }

    func sumiFaviconImageConstrained(maxLongestSide: CGFloat) -> NSImage {
        let longestSide = max(size.width, size.height)
        guard longestSide > maxLongestSide, longestSide > 0 else {
            return self
        }

        let scale = maxLongestSide / longestSide
        let targetSize = NSSize(
            width: max(1, size.width * scale),
            height: max(1, size.height * scale)
        )
        let image = NSImage(size: targetSize)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1
        )
        image.unlockFocus()
        return image
    }

    func sumiFaviconPNGData(maxPixelSize: Int) -> Data? {
        let constrained = sumiFaviconImageConstrained(maxLongestSide: CGFloat(maxPixelSize))
        guard let cgImage = constrained.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return constrained.tiffRepresentation
        }
        let representation = NSBitmapImageRep(cgImage: cgImage)
        return representation.representation(using: .png, properties: [:])
    }
}

private extension CGImageSource {
    func sumiBestFaviconImageIndex(targetPixelSize: Int) -> Int {
        let count = CGImageSourceGetCount(self)
        guard count > 1 else { return 0 }

        var bestIndex = 0
        var bestScore = Int.max

        for index in 0..<count {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(self, index, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int else {
                continue
            }

            let longestSide = max(width, height)
            guard longestSide > 0 else { continue }

            let score = longestSide >= targetPixelSize
                ? longestSide - targetPixelSize
                : 10_000 + targetPixelSize - longestSide
            if score < bestScore {
                bestScore = score
                bestIndex = index
            }
        }

        return bestIndex
    }
}

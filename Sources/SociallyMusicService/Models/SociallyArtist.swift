//
//  SociallyArtist.swift
//  SociallyMusicService
//
//  Created by Zach McGuckin on 2/13/20.
//

import Foundation

public struct SociallyArtist: Codable, Hashable {
    
    public let name: String
    public let id: String
    public let imageURL: String
    
    public init(name: String, id: String, imageURL: String) {
        self.name = name
        self.id = id
        self.imageURL = imageURL
    }
    
    init?(from resource: AdditionalResource<ArtistSearchAttributes, ArtistRelationships>) {
        guard let appleArtist = resource.attributes else { return nil }
        self.name = appleArtist.name
        self.id = resource.id
        if let first = resource.relationships?.albums.data?.first, let url = first.attributes?.artwork?.url {
            self.imageURL = url.replacingOccurrences(of: "{w}x{h}bb", with: "640x640bb")
        } else {
            self.imageURL = ""
        }

    }
    
    //Initializer from JSON representation
    public init?(with data: [String: Any]) {
        guard let name = data["name"] as? String,
            let id = data["id"] as? String,
            let imageURL = data["imageURL"] as? String
            else { return nil }
        
        self.name = name
        self.id = id
        self.imageURL = imageURL
    }
    
    init(from artist: Artist) {
        self.name = artist.name
        self.id = artist.id
        guard !artist.images.isEmpty else {
            self.imageURL = ""
            return
        }
        self.imageURL = artist.images[0].url.absoluteString
    }
    
    //Converting to JSON representation
    public var jsonRepresentation: [String: String] {
        return [
            "name": name,
            "id": id,
            "imageURL": imageURL
        ]
    }
}

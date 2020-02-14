//
//  AppleMusicService.swift
//  SociallyMusicService
//
//  Created by Zach McGuckin on 2/13/20.
//  Copyright © 2020 Zach McGuckin. All rights reserved.
//

import Foundation
import MediaPlayer
import StoreKit

class AppleMusicService {
    
    public static let shared = AppleMusicService()
    private let urlSession = URLSession.shared
    private let baseURL = URL(string: "https://api.music.apple.com/v1/")!
    
    private var appleToken = ""
    private var devToken = ""
    
    private let jsonDecoder: JSONDecoder = {
        let jsonDecoder = JSONDecoder()
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
        return jsonDecoder
    }()
    
    private func fetchResources<T: Decodable>(request: URLRequest, completion: @escaping (Result<T, APIServiceError>) -> Void) {
        //Make call
        self.urlSession.dataTask(with: request) { (result: Result<(URLResponse, Data), Error> ) in
            switch result {
            case .success(let (response, data)):
                guard let statusCode = (response as? HTTPURLResponse)?.statusCode, 200..<299 ~= statusCode else {
                    print(response)
                    completion(.failure(.invalidResponse))
                    return
                }
                do {
                    let values = try self.jsonDecoder.decode(T.self, from: data)
                    completion(.success(values))
                } catch let error {
                    print(error)
                    completion(.failure(.decodeError))
                }
            case .failure:
                completion(.failure(.apiError))
            }
        }.resume()
    }
    
    private func sendRequestNoPayload(request: URLRequest, result: @escaping (Result<Bool, APIServiceError>) -> Void) {
        var newRequest = request
        //Add headers
        newRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        newRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        //Perform call
        self.urlSession.dataTask(with: newRequest) { data, response, error in
            if error != nil || data == nil {
                result(.failure(.apiError))
                return
            }
            guard let response = response as? HTTPURLResponse, (204 == response.statusCode || 200 == response.statusCode) else {
                result(.failure(.invalidResponse))
                return
            }
            result(.success(true))
        }.resume()
    }
    
    public func searchByISRC(isrc: String, completion: @escaping (String) -> Void) {
        let countryCode = "us"
        var component = URLComponents(string: baseURL.appendingPathComponent("catalog/\(countryCode)/songs").absoluteString)
        
        component?.queryItems = [
            URLQueryItem(name: "filter[isrc]", value: isrc)
        ]
        
        guard let url = component?.url else { return }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        
        fetchResources(request: request) { (result: Result<ResponseRoot<Track>, APIServiceError>) in
            switch result {
            case .success(let track):
                guard track.data?.count ?? 0 > 0, let trackId = track.data?[0].id else {
                    completion("")
                    return
                }
                completion(trackId)
            case .failure:
                completion("")
            }
        }
    }
    
    public func playSong(context: String, result: @escaping (Bool) -> Void) {
        let storeIds: [String] = [context]
        let player = MPMusicPlayerController.systemMusicPlayer
        let queue  = MPMusicPlayerStoreQueueDescriptor(storeIDs: storeIds)
        player.setQueue(with: queue)
        player.play()
        result(true)
    }
    
    public func fetchCurrentTrack(completion: @escaping (Result<SociallyTrack, APIServiceError>) -> Void) {
        let track = ""
        fetchSongByIdentifier(identifier: track, completion: completion)
    }
    
    func getAllPlaylists(completion: @escaping (Result<[SociallyPlaylist], APIServiceError>) -> Void) {
        
        var component = URLComponents(string: baseURL.appendingPathComponent("me/library/playlists").absoluteString)
        
        guard let url = component?.url else { return }
        component?.queryItems = [
            URLQueryItem(name: "limit", value: "100")
        ]
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        request.setValue(appleToken, forHTTPHeaderField: "Music-User-Token")
        
        fetchResources(request: request) { (result: Result<ResponseRoot<ApplePlaylist>, APIServiceError>) in
            switch result {
            case .success(let playlist):
                guard let playlists = playlist.data else {
                    completion(.failure(APIServiceError.noData))
                    return
                }
                let ret = playlists.map({SociallyPlaylist(from: $0)})
                completion(.success(ret))
            case .failure:
                completion(.failure(.apiError))
            }
        }
    }
    
    func getAllSongsFor(playlist: String, completion: @escaping (Result<[SociallyTrack], Error>) -> Void) {
        
        let component = URLComponents(string: baseURL.appendingPathComponent("me/library/playlists/\(playlist)/tracks").absoluteString)

        guard let url = component?.url else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        request.setValue(appleToken, forHTTPHeaderField: "Music-User-Token")
        
        fetchResources(request: request) { (result: Result<ResponseRoot<Track>, APIServiceError>) in
            switch result {
            case .success(let playlist):
                guard !(playlist.data?.isEmpty ?? true), let tracks = playlist.data else {
                    completion(.failure(APIServiceError.noData))
                    return
                }
                
                let SociallyTracks: [SociallyTrack] = tracks.compactMap { (track) -> SociallyTrack? in
                    
                    guard let attributes = track.attributes else { return nil }
                    var imageURL = attributes.artwork.url
                    imageURL = imageURL.replacingOccurrences(of: "{w}x{h}bb", with: "640x640bb")
                    let sociallyTrack = SociallyTrack(album: attributes.albumName, artist: attributes.artistName, name: attributes.name, isrc: attributes.isrc, context: attributes.url.absoluteString, imageURL: imageURL)
                    return sociallyTrack
                }
                
                completion(.success(SociallyTracks))
            case .failure:
                completion(.failure(APIServiceError.apiError))
            }
        }
    }
    
    func addSong(_ song: String, to playlist: String, completion: @escaping (Result<[String: String], APIServiceError>) -> Void) {
        
        let component = URLComponents(string: baseURL.appendingPathComponent("me/library/playlists/\(playlist)/tracks").absoluteString)
        
        guard let url = component?.url else { return }
        
        let body: [String: Any] = [
            "data": [["id": song, "type": "songs"]]]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(APIServiceError.invalidCompiledURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        request.setValue(appleToken, forHTTPHeaderField: "Music-User-Token")
        request.httpMethod = "POST"
        request.httpBody = jsonData
        
        sendRequestNoPayload(request: request) { (result) in
            switch result {
            case .success:
                completion(.success([:]))
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }
    
    private func fetchSongByIdentifier(identifier: String, completion: @escaping (Result<SociallyTrack, APIServiceError>) -> Void) {
        let countryCode = "us"
        let component = URLComponents(string: baseURL.appendingPathComponent("catalog/\(countryCode)/songs/\(identifier)").absoluteString)
        
        guard let url = component?.url else { return }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        
        fetchResources(request: request) { (result: Result<ResponseRoot<Track>, APIServiceError>) in
            switch result {
            case .success(let track):
                guard let trackAttributes = track.data?[0].attributes else {
                    completion(.failure(.apiError))
                    return
                }
                var imageURL = trackAttributes.artwork.url
                imageURL = imageURL.replacingOccurrences(of: "{w}x{h}bb", with: "640x640bb")
                let sociallyTrack = SociallyTrack(album: trackAttributes.albumName, artist: trackAttributes.artistName, name: trackAttributes.name, isrc: trackAttributes.isrc, context: identifier, imageURL: imageURL)
                completion(.success(sociallyTrack))
            case .failure:
                completion(.failure(.apiError))
            }
        }
    }
}
//
//  UserDefaults+Extentions.swift
//  Recordit
//
//  Created by Steven Sarmiento on 4/29/23.
//

import Foundation

extension UserDefaults {
    func save<T: Codable>(object: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(object) {
            set(data, forKey: key)
        }
    }
    
    func fetch<T: Codable>(forKey key: String, type: T.Type) -> T? {
        if let data = value(forKey: key) as? Data {
            return try? JSONDecoder().decode(type, from: data)
        }
        return nil
    }
}


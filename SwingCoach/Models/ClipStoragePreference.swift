import Foundation

enum ClipStoragePreference {
    static let saveToPhotosKey = "storage.saveToPhotos"

    static var savesToPhotos: Bool {
        UserDefaults.standard.object(forKey: saveToPhotosKey) as? Bool ?? true
    }
}

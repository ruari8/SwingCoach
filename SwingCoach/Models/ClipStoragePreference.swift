import Foundation

enum ClipStoragePreference {
    static let saveToPhotosKey = "storage.saveToPhotos"

    static var savesToPhotos: Bool {
        let defaults = UserDefaults.standard
        #if DEBUG
        // Footage camera runs are tests: keep their clips out of the camera roll
        // unless the run asks for Photos with -footage-camera-photos YES.
        if defaults.string(forKey: "footage-camera") != nil {
            return defaults.bool(forKey: "footage-camera-photos")
        }
        #endif
        return defaults.object(forKey: saveToPhotosKey) as? Bool ?? true
    }
}

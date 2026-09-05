import Foundation

protocol TokenStore {
    func set(_ value: String, for key: String)
    func get(_ key: String) -> String?
    func delete(_ key: String)
}

import Foundation

struct StorageResponse<T: Decodable> {
    let key: Data
    let data: Data?
    let value: T?
}

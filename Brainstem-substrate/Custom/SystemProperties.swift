import Foundation
import SubstrateSdk

struct SystemProperties: Codable, Equatable {
    let ss58Format: UInt32
    let tokenDecimals: [UInt32]
    let tokenSymbol: [String]
}

struct SystemPropertiesResponse: Codable {
    let result: SystemProperties
}

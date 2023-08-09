import Foundation
import SubstrateSdk

struct GenerateDidCall: Codable {
    @BytesCodable var did_account: Data
    @BytesCodable var name: Data
    @BytesCodable var value: Data
    @OptionStringCodable var valid_for: BlockNumber?
}

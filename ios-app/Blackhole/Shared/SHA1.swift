import Foundation
import CryptoKit

/// Dünner Wrapper um CryptoKit für den ONVIF-WS-Security-Digest.
/// (ONVIF schreibt SHA1 vor – hier bewusst nur für dieses Protokoll genutzt.)
enum SHA1 {
    static func hash(_ data: Data) -> [UInt8] {
        Array(Insecure.SHA1.hash(data: data))
    }
}

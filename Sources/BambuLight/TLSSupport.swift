import Foundation
import Network
import CryptoKit
import Security

enum TLSSupport {
    /// TLS options for a printer's self-signed certificate (LAN only). Chain validation is skipped; instead the leaf
    /// certificate's SHA-256 is passed to `pin` (trust on first use). With no `pin`, any certificate is accepted.
    static func selfSigned(queue: DispatchQueue, pin: ((String) -> Bool)?, onReject: @escaping () -> Void) -> NWProtocolTLS.Options {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, trust, done in
            let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
            guard let pin,
                  let leaf = (SecTrustCopyCertificateChain(secTrust) as? [SecCertificate])?.first else { done(pin == nil); return }
            let fp = SHA256.hash(data: SecCertificateCopyData(leaf) as Data).map { String(format: "%02x", $0) }.joined()
            let ok = pin(fp)
            if !ok { onReject() }
            done(ok)
        }, queue)
        return tls
    }
}

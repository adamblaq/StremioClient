import Foundation
import Network
import Security

/// Resolves a single HTTP redirect hop using a TCP+TLS NWConnection (no QUIC).
///
/// URLSession and AVFoundation both negotiate QUIC for torrentio.strem.fun, which
/// triggers a `quic_conn_setup_pmtud` failure that crashes the iOS networking stack
/// on some devices. NWParameters(tls:) forces TCP and is safe on all devices.
enum RedirectResolver {

    static func resolve(_ url: URL) async -> URL {
        guard let host = url.host else { return url }

        // Force HTTP/1.1 via ALPN — this prevents QUIC negotiation entirely
        let tlsOpts = NWProtocolTLS.Options()
        sec_protocol_options_add_tls_application_protocol(
            tlsOpts.securityProtocolOptions, "http/1.1"
        )
        let params = NWParameters(tls: tlsOpts)
        let connection = NWConnection(
            to: .hostPort(host: .init(host), port: 443),
            using: params
        )

        // Preserve percent-encoding in path (e.g. %20 in filenames)
        let requestPath: String
        if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            let q = comps.percentEncodedQuery.map { "?\($0)" } ?? ""
            requestPath = comps.percentEncodedPath + q
        } else {
            requestPath = "/"
        }

        return await withCheckedContinuation { cont in
            let lock = NSLock()
            var done = false

            let finish: (URL) -> Void = { finalURL in
                lock.lock()
                defer { lock.unlock() }
                guard !done else { return }
                done = true
                connection.cancel()
                cont.resume(returning: finalURL)
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 8) {
                print("[RedirectResolver] Timed out for \(host)")
                finish(url)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let req = """
                        GET \(requestPath) HTTP/1.1\r\n\
                        Host: \(host)\r\n\
                        User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148\r\n\
                        Accept: */*\r\n\
                        Connection: close\r\n\r\n
                        """
                    connection.send(content: Data(req.utf8), completion: .contentProcessed { _ in })
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                        guard let data, let text = String(data: data, encoding: .utf8) else {
                            finish(url)
                            return
                        }
                        let lines = text.components(separatedBy: "\r\n")
                        if let line = lines.first(where: { $0.lowercased().hasPrefix("location:") }) {
                            let loc = String(line.dropFirst("location:".count))
                                .trimmingCharacters(in: .whitespaces)
                            print("[RedirectResolver] \(host) → \(loc)")
                            finish(URL(string: loc) ?? url)
                        } else {
                            print("[RedirectResolver] No Location header from \(host)")
                            finish(url)
                        }
                    }
                case .failed(let err):
                    print("[RedirectResolver] NWConnection failed: \(err)")
                    finish(url)
                case .cancelled:
                    finish(url)
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .userInitiated))
        }
    }
}

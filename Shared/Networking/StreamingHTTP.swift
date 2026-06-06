import Foundation

public enum StreamingHTTP {
    public static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        config.httpAdditionalHeaders = [
            "User-Agent": "WristAssistant/1.0 (iOS+watchOS)"
        ]
        return URLSession(configuration: config)
    }

    public static func send(_ request: URLRequest, session: URLSession = StreamingHTTP.session()) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.transport("Non-HTTP response")
            }
            if !(200..<300).contains(http.statusCode) {
                var errorBody = ""
                do {
                    for try await line in bytes.lines {
                        if errorBody.count < 2000 {
                            errorBody += line + "\n"
                        }
                    }
                } catch {
                    // ignore secondary error
                }
                throw APIError.http(status: http.statusCode, body: errorBody)
            }
            return (bytes, http)
        } catch let e as APIError {
            throw e
        } catch let e as URLError where e.code == .cancelled {
            throw APIError.cancelled
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }
}

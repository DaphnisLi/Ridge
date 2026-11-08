import Foundation

/// 行情 HTTP：系统代理会话 + 直连会话；代理对 Yahoo 拒连时自动换直连。
enum StockNetwork {
    static let proxied: URLSession = makeSession(bypassProxy: false)
    static let direct: URLSession = makeSession(bypassProxy: true)

    private static func makeSession(bypassProxy: Bool) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        // 偏短：多源串联时尽快换下一个接口。
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 8
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            "Accept": "application/json,text/plain,*/*",
            "Accept-Language": "en-US,en;q=0.9,zh-CN;q=0.8",
        ]
        if bypassProxy {
            // 空字典 = 不走系统 HTTP/HTTPS/SOCKS 代理。
            config.connectionProxyDictionary = [:]
        }
        return URLSession(configuration: config)
    }

    /// 先系统代理，传输层失败再直连；缩短「全挂」等待。
    static func data(from url: URL, extraHeaders: [String: String] = [:]) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let result = try await proxied.data(for: request)
            try throwIfHTTPError(result.1)
            return result
        } catch {
            if shouldTryDirect(error) {
                AppLog.debug("Stocks", "代理请求失败，改直连", [
                    "host": url.host ?? "",
                    "error": (error as NSError).code
                ])
                let result = try await direct.data(for: request)
                try throwIfHTTPError(result.1)
                return result
            }
            throw error
        }
    }

    private static func shouldTryDirect(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorSecureConnectionFailed,
                 NSURLErrorTimedOut,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorNotConnectedToInternet,
                 NSURLErrorCannotFindHost,
                 NSURLErrorDNSLookupFailed,
                 -1200: // TLS
                return true
            default:
                break
            }
        }
        if let stockError = error as? StockClientError, case .http(let code) = stockError {
            // 代理常见拒连 / 网关错误。
            return [403, 407, 502, 503, 504].contains(code)
        }
        return false
    }

    private static func throwIfHTTPError(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw StockClientError.http(http.statusCode)
        }
    }
}

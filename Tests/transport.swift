import Foundation

final class BoundedFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let mode = request.url!.lastPathComponent
        if mode == "cancel" { return }
        let headers = mode == "declared" ? ["Content-Length": "1000000"] : [:]
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(repeating: 65, count: mode == "chunked" ? 256 : 8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

func boundedHTTPChecks(done: @escaping () -> Void) {
    let modes = ["valid", "chunked", "declared", "cancel"]
    func run(_ index: Int) {
        guard index < modes.count else { done(); return }
        let mode = modes[index]
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BoundedFixtureProtocol.self]
        var request = URLRequest(url: URL(string: "https://synthetic.invalid/" + mode)!)
        request.timeoutInterval = 2
        var callbacks = 0
        var transport: BoundedHTTP?
        transport = BoundedHTTP(request: request, limit: 32, configuration: configuration) { data, response, error in
            DispatchQueue.main.async {
                callbacks += 1
                check(callbacks == 1, "Bounded transport completes once: " + mode)
                if mode == "valid" {
                    check(error == nil && data?.count == 8 && response?.statusCode == 200, "Bounded transport accepts a complete small response")
                } else if mode == "cancel" {
                    check((error as NSError?)?.code == NSURLErrorCancelled, "Bounded transport cancellation reaches completion")
                } else {
                    check(data == nil && (error as NSError?)?.domain == "SystemProcessesBoundedHTTP", "Bounded transport rejects oversized " + mode + " responses")
                }
                // Check redirect rejection directly; URLProtocol does not simulate native redirects reliably.
                if mode == "valid" {
                    let session = URLSession(configuration: .ephemeral)
                    let task = session.dataTask(with: request)
                    let redirect = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil, headerFields: nil)!
                    transport!.urlSession(session, task: task, willPerformHTTPRedirection: redirect,
                        newRequest: URLRequest(url: URL(string: "https://other.invalid/")!)) { forwarded in
                        check(forwarded == nil, "Credential-bearing redirects are rejected")
                    }
                    session.invalidateAndCancel()
                }
                transport = nil
                run(index + 1)
            }
        }
        if mode == "cancel" { transport?.cancel() }
    }
    run(0)
}

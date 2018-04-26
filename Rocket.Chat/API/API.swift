//
//  API.swift
//  Rocket.Chat
//
//  Created by Matheus Cardoso on 9/18/17.
//  Copyright © 2017 Rocket.Chat. All rights reserved.
//

import Foundation
import SwiftyJSON

protocol APIRequestMiddleware {
    var api: API { get }
    init(api: API)

    func handle<R: APIRequest>(_ request: inout R) -> APIError?
}

protocol APIFetcher {
    @discardableResult
    func fetch<R>(_ request: R, succeeded: ((_ result: APIResult<R>) -> Void)?, errored: APIErrored?) -> URLSessionTask?
    @discardableResult
    func fetch<R>(_ request: R, options: APIRequestOptions, sessionDelegate: URLSessionTaskDelegate?,
                  succeeded: ((_ result: APIResult<R>) -> Void)?, errored: APIErrored?) -> URLSessionTask?
}

extension APIFetcher {
    func fetch<R>(_ request: R, succeeded: ((APIResult<R>) -> Void)?, errored: APIErrored?) -> URLSessionTask? {
        return fetch(request, options: .none, sessionDelegate: nil, succeeded: succeeded, errored: errored)
    }
}

typealias AnyAPIFetcher = Any & APIFetcher

class API: APIFetcher {
    let host: URL
    let version: Version

    var requestMiddlewares = [APIRequestMiddleware]()

    var authToken: String?
    var userId: String?

    static let userAgent: String = {
        let info = Bundle.main.infoDictionary
        let appVersion = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let bundleVersion = info?["CFBundleVersion"] as? String ?? "-"
        let systemVersion = UIDevice.current.systemVersion
        return "RC Mobile; iOS \(systemVersion); v\(appVersion) (\(bundleVersion))"
    }()

    convenience init?(host: String, version: Version = .zero) {
        guard let url = URL(string: host)?.httpServerURL() else {
            return nil
        }

        self.init(host: url, version: version)
    }

    init(host: URL, version: Version = .zero) {
        self.host = host
        self.version = version

        requestMiddlewares.append(VersionMiddleware(api: self))
    }

    @discardableResult
    func fetch<R>(_ request: R, options: APIRequestOptions = .none, sessionDelegate: URLSessionTaskDelegate? = nil,
                  succeeded: ((_ result: APIResult<R>) -> Void)?, errored: APIErrored?) -> URLSessionTask? {
        var transformedRequest = request
        for middleware in requestMiddlewares {
            if let error = middleware.handle(&transformedRequest) {
                errored?(error)
                return nil
            }
        }

        guard let request = transformedRequest.request(for: self, options: options) else {
            errored?(.malformedRequest)
            return nil
        }

        var session: URLSession = URLSession.shared

        if let sessionDelegate = sessionDelegate {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30

            session = URLSession(
                configuration: configuration,
                delegate: sessionDelegate,
                delegateQueue: nil
            )
        }

        let task = session.dataTask(with: request) { (data, _, error) in
            if let error = error {
                errored?(.error(error))
                return
            }

            guard let data = data else {
                errored?(.noData)
                return
            }

            let json = try? JSON(data: data)
            succeeded?(APIResult<R>(raw: json))
        }

        task.resume()

        return task
    }
}

// Diapason — Diapason Connect protocol: TCP control channel between iOS and desktop.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import Foundation
import Network
import Darwin

struct ConnectDevice: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let baseURL: String

    func hash(into hasher: inout Hasher) { hasher.combine(baseURL) }
    static func == (lhs: ConnectDevice, rhs: ConnectDevice) -> Bool { lhs.baseURL == rhs.baseURL }
}

struct ConnectStatus: Codable {
    struct Song: Codable {
        let id: String
        let title: String
        let artist: String
        let album: String
        let duration: Double
        let art: String?
    }
    let song: Song?
    let state: String
    let position: Double
    let volume: Double
}

@MainActor
class ConnectManager: ObservableObject {

    @Published var discoveredDevices: [ConnectDevice] = []
    @Published var connectedDevice: ConnectDevice?
    @Published var remoteStatus: ConnectStatus?
    @Published var isScanning = false

    @Published var registeredDevices: [ConnectDevice] = []
    @Published var registeredStatuses: [String: ConnectStatus] = [:]

    @Published var serverURL: String?

    var onCommandReceived: ((String, Double?, Double?) -> Void)?
    var onPlayQueueReceived: (([[String: Any]], Int) -> Void)?
    var onDeviceRegistered: ((String, String) -> Void)?
    var localStatusProvider: (() -> ConnectStatus)?

    private var browsers: [NWBrowser] = []
    private var pollTask: Task<Void, Never>?
    private var registeredPollTask: Task<Void, Never>?
    private var resolvers: [NetServiceResolver] = []

    private var listener: NWListener?
    private var bonjourService: NetService?
    private var serverToken: String = ""
    private var serverPort: UInt16 = 0

    init() { startServer() }

    func startServer() {
        stopServer()
        serverToken = randomToken()

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let l = try? NWListener(using: params) else { return }
        listener = l

        l.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .global(qos: .userInitiated))
            guard let self = self else { return }
            Task { await self.receiveHTTP(conn: conn, buffer: Data()) }
        }

        l.stateUpdateHandler = { [weak self] state in
            if case .ready = state, let port = l.port?.rawValue {
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.serverPort = port
                    self.advertiseMDNS(port: Int(port))
                    self.serverURL = "http://localhost:\(port)/\(self.serverToken)/connect"
                }
            }
        }
        l.start(queue: .global(qos: .userInitiated))
    }

    func stopServer() {
        listener?.cancel()
        listener = nil
        bonjourService?.stop()
        bonjourService = nil
        serverURL = nil
    }

    private func advertiseMDNS(port: Int) {
        bonjourService?.stop()
        let txtDict: [String: Data] = ["token": serverToken.data(using: .utf8)!]
        let svc = NetService(domain: "", type: "_diapason-connect._tcp.", name: "Diapason iOS", port: Int32(port))
        svc.setTXTRecord(NetService.data(fromTXTRecord: txtDict))
        svc.publish()
        bonjourService = svc
    }

    private func receiveHTTP(conn: NWConnection, buffer: Data) async {
        return await withCheckedContinuation { continuation in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, _ in
                guard let self = self else { continuation.resume(); return }
                var buf = buffer
                if let d = data { buf.append(d) }
                let sep = Data([0x0D, 0x0A, 0x0D, 0x0A])
                if let sepRange = buf.range(of: sep) {
                    Task {
                        await self.routeHTTP(conn: conn,
                                             headers: Data(buf[..<sepRange.lowerBound]),
                                             body: Data(buf[sepRange.upperBound...]))
                        continuation.resume()
                    }
                } else if !isComplete {
                    Task {
                        await self.receiveHTTP(conn: conn, buffer: buf)
                        continuation.resume()
                    }
                } else {
                    continuation.resume()
                }
            }
        }
    }

    @MainActor
    private func routeHTTP(conn: NWConnection, headers: Data, body: Data) async {
        guard let headerStr = String(data: headers, encoding: .utf8) else {
            Self.sendHTTP(conn, status: 400, body: "Bad Request"); return
        }
        let lines = headerStr.components(separatedBy: "\r\n")
        guard let reqLine = lines.first else { return }
        let parts = reqLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return }
        let method = parts[0]
        let path = parts[1].components(separatedBy: "?")[0]

        if method == "OPTIONS" { Self.sendCORS(conn); return }

        let prefix = "/\(serverToken)/connect/"
        guard path.hasPrefix(prefix) else { Self.sendHTTP(conn, status: 404, body: "Not Found"); return }
        let endpoint = String(path.dropFirst(prefix.count))

        switch (method, endpoint) {
        case ("GET", "status"):
            let status = localStatusProvider?() ?? ConnectStatus(song: nil, state: "stopped", position: 0, volume: 1)
            let json = (try? JSONEncoder().encode(status)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            Self.sendHTTP(conn, status: 200, body: json, contentType: "application/json")

        case ("POST", "command"):
            if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let action = json["action"] as? String {
                onCommandReceived?(action, json["position"] as? Double, json["volume"] as? Double)
            }
            Self.sendHTTP(conn, status: 200, body: "ok")

        case ("POST", "play-queue"):
            if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let songs = json["songs"] as? [[String: Any]],
               let startIndex = json["startIndex"] as? Int {
                onPlayQueueReceived?(songs, startIndex)
            }
            Self.sendHTTP(conn, status: 200, body: "ok")

        case ("POST", "register"):
            if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let name = json["name"] as? String,
               let url = json["url"] as? String, !url.isEmpty {
                let device = ConnectDevice(name: name, baseURL: url)
                if !registeredDevices.contains(where: { $0.baseURL == url }) {
                    registeredDevices.append(device)
                    startRegisteredPolling()
                    onDeviceRegistered?(name, url)
                }
            }
            Self.sendHTTP(conn, status: 200, body: "ok")

        default:
            Self.sendHTTP(conn, status: 404, body: "Not Found")
        }
    }

    private static func sendHTTP(_ conn: NWConnection, status: Int, body: String, contentType: String = "text/plain") {
        let bodyData = body.data(using: .utf8) ?? Data()
        let header = "HTTP/1.1 \(status) OK\r\nContent-Type: \(contentType)\r\nContent-Length: \(bodyData.count)\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
        var response = header.data(using: .utf8)!
        response.append(bodyData)
        conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
    }

    private static func sendCORS(_ conn: NWConnection) {
        let resp = "HTTP/1.1 204 No Content\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\nConnection: close\r\n\r\n"
        conn.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
    }

    private func randomToken() -> String {
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<24).map { _ in chars.randomElement()! })
    }

    func startDiscovery() {
        stopDiscovery()
        isScanning = true
        discoveredDevices = []

        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjour(type: "_diapason-connect._tcp", domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                for result in results {
                    if case let .service(name, type, domain, _) = result.endpoint {
                        self.resolveWithNetService(name: name, type: type + ".", domain: domain)
                    }
                }
            }
        }
        browser.start(queue: .main)
        browsers.append(browser)

        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.isScanning = false
        }
    }

    func stopDiscovery() {
        browsers.forEach { $0.cancel() }
        browsers = []
        resolvers = []
        isScanning = false
    }

    func connect(to device: ConnectDevice) {
        connectedDevice = device
        startPolling()
        registerWithDevice(device)
    }

    func disconnect() {
        connectedDevice = nil
        remoteStatus = nil
        stopPolling()
    }

    private func registerWithDevice(_ device: ConnectDevice) {
        guard serverPort > 0 else { return }
        let myURL = "http://\(bestLocalIP()):\(serverPort)/\(serverToken)/connect"
        Task {
            guard let url = URL(string: "\(device.baseURL)/register") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["name": "Diapason iOS", "url": myURL])
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    private func bestLocalIP() -> String {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return "127.0.0.1" }
        defer { freeifaddrs(ifaddr) }
        var ptr = ifaddr
        while let current = ptr {
            let iface = current.pointee
            if iface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: iface.ifa_name)
                if name.hasPrefix("en") {
                    var addr = iface.ifa_addr.pointee
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(&addr, socklen_t(iface.ifa_addr.pointee.sa_len),
                                   &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                        return String(cString: host)
                    }
                }
            }
            ptr = current.pointee.ifa_next
        }
        return "127.0.0.1"
    }

    func sendCommand(_ action: String, position: Double? = nil, volume: Double? = nil) {
        guard let device = connectedDevice else { return }
        sendCommandTo(device, action: action, position: position, volume: volume)
    }

    func sendCommandTo(_ device: ConnectDevice, action: String, position: Double? = nil, volume: Double? = nil) {
        var body: [String: Any] = ["action": action]
        if let p = position { body["position"] = p }
        if let v = volume { body["volume"] = v }
        Task {
            guard let url = URL(string: "\(device.baseURL)/command") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    func castQueue(songs: [[String: Any]], startIndex: Int) {
        guard let device = connectedDevice else { return }
        Task {
            guard let url = URL(string: "\(device.baseURL)/play-queue") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["songs": songs, "startIndex": startIndex])
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    private func startPolling() {
        stopPolling()
        pollTask = Task {
            while !Task.isCancelled {
                await pollStatus()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollStatus() async {
        guard let device = connectedDevice,
              let url = URL(string: "\(device.baseURL)/status") else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let status = try? JSONDecoder().decode(ConnectStatus.self, from: data) else { return }
        self.remoteStatus = status
    }

    private func startRegisteredPolling() {
        registeredPollTask?.cancel()
        registeredPollTask = Task {
            while !Task.isCancelled {
                for device in self.registeredDevices {
                    if let url = URL(string: "\(device.baseURL)/status"),
                       let (data, _) = try? await URLSession.shared.data(from: url),
                       let status = try? JSONDecoder().decode(ConnectStatus.self, from: data) {
                        self.registeredStatuses[device.baseURL] = status
                    }
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func resolveWithNetService(name: String, type: String, domain: String) {
        let resolver = NetServiceResolver(name: name, type: type, domain: domain) { [weak self] device in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if !self.discoveredDevices.contains(where: { $0.baseURL == device.baseURL }) {
                    self.discoveredDevices.append(device)
                }
            }
        }
        resolvers.append(resolver)
        resolver.start()
    }
}

private class NetServiceResolver: NSObject, NetServiceDelegate {
    private var service: NetService
    private let completion: (ConnectDevice) -> Void

    init(name: String, type: String, domain: String, completion: @escaping (ConnectDevice) -> Void) {
        self.service = NetService(domain: domain, type: type, name: name)
        self.completion = completion
        super.init()
        self.service.delegate = self
    }

    func start() { service.resolve(withTimeout: 5) }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let host = sender.hostName else { return }
        let port = sender.port
        var token = ""
        if let txtData = sender.txtRecordData() {
            let dict = NetService.dictionary(fromTXTRecord: txtData)
            if let t = dict["token"], let s = String(data: t, encoding: .utf8) { token = s }
        }
        let normalizedHost = host.hasSuffix(".") ? String(host.dropLast()) : host
        let baseURL = token.isEmpty
            ? "http://\(normalizedHost):\(port)"
            : "http://\(normalizedHost):\(port)/\(token)/connect"
        completion(ConnectDevice(name: sender.name, baseURL: baseURL))
    }
}

// Diapason — Bonjour/mDNS discovery of Diapason desktop instances on the LAN.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import Foundation

class DesktopDiapasonBrowser: NSObject, NetServiceBrowserDelegate, NetServiceDelegate, ObservableObject {
    @Published var discoveredPeers: [DiscoveredPeer] = []
    @Published var isScanning = false
    
    private var browser: NetServiceBrowser?
    private var services: [NetService] = []
    
    struct DiscoveredPeer: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let url: String
        let token: String
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(name)
            hasher.combine(url)
        }
        
        static func == (lhs: DiscoveredPeer, rhs: DiscoveredPeer) -> Bool {
            return lhs.name == rhs.name && lhs.url == rhs.url
        }
    }
    
    func start() {
        discoveredPeers = []
        services = []
        browser = NetServiceBrowser()
        browser?.delegate = self
        browser?.searchForServices(ofType: "_diapason._tcp.", inDomain: "local.")
        isScanning = true
    }
    
    func stop() {
        browser?.stop()
        browser = nil
        for s in services {
            s.stop()
        }
        services = []
        isScanning = false
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5.0)
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        if let index = services.firstIndex(of: service) {
            services.remove(at: index)
        }
        
        DispatchQueue.main.async {
            self.discoveredPeers.removeAll(where: { $0.name == service.name })
        }
    }
    
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let host = sender.hostName else { return }
        let port = sender.port
        
        var token = ""
        if let txtData = sender.txtRecordData() {
            let dict = NetService.dictionary(fromTXTRecord: txtData)
            if let tokenData = dict["token"],
               let tokenStr = String(data: tokenData, encoding: .utf8) {
                token = tokenStr
            }
        }
        
        let normalizedHost = host.hasSuffix(".") ? String(host.dropLast()) : host
        let url = "http://\(normalizedHost):\(port)/\(token)"
        
        DispatchQueue.main.async {
            let peer = DiscoveredPeer(name: sender.name, url: url, token: token)
            if !self.discoveredPeers.contains(where: { $0.name == peer.name }) {
                self.discoveredPeers.append(peer)
            }
        }
    }
}

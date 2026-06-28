import Foundation
import Network

struct DiscoveredServer: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: String
    let type: BackendType
}

class DiscoveryManager: ObservableObject {
    @Published var discoveredServers: [DiscoveredServer] = []
    @Published var isScanning = false
    
    private var browsers: [NWBrowser] = []
    
    func startDiscovery() {
        stopDiscovery()
        isScanning = true
        
        // Browsers for Subsonic and Plex
        let serviceTypes = ["_subsonic._tcp", "_plexmediasvr._tcp"]
        
        for serviceType in serviceTypes {
            let parameters = NWParameters()
            parameters.includePeerToPeer = true
            
            let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)
            
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                guard let self = self else { return }
                
                for result in results {
                    if case let .service(name, type, domain, _) = result.endpoint {
                        self.resolve(name: name, type: type, domain: domain)
                    }
                }
            }
            
            browser.start(queue: .main)
            browsers.append(browser)
        }
        
        // Stop scanning after 10 seconds to save battery/cpu
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            self.isScanning = false
        }
    }
    
    func stopDiscovery() {
        for browser in browsers {
            browser.cancel()
        }
        browsers = []
        isScanning = false
    }
    
    private func resolve(name: String, type: String, domain: String) {
        let endpoint = NWEndpoint.service(name: name, type: type, domain: domain, interface: nil)
        let parameters = NWParameters.tcp
        let connection = NWConnection(to: endpoint, using: parameters)
        
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            
            if case .ready = state {
                if let innerEndpoint = connection.currentPath?.remoteEndpoint,
                   case let .hostPort(host, port) = innerEndpoint {
                    
                    let serverType: BackendType = type.contains("subsonic") ? .subsonic : .plex
                    let hostString = "\(host)"
                    let url = "http://\(hostString):\(port)"
                    
                    DispatchQueue.main.async {
                        let server = DiscoveredServer(name: name, url: url, type: serverType)
                        if !self.discoveredServers.contains(where: { $0.url == url }) {
                            self.discoveredServers.append(server)
                        }
                        connection.cancel()
                    }
                }
            }
        }
        
        connection.start(queue: .main)
    }
}

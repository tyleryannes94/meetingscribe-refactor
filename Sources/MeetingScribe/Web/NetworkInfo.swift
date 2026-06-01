import Foundation

/// Discovers the local IPv4 addresses the phone can use to reach this Mac.
/// Distinguishes a plain LAN address (same-Wi-Fi access) from a Tailscale
/// address (access from anywhere), since the Settings UI shows both.
enum NetworkInfo {
    struct Address: Hashable {
        let interface: String
        let ip: String
    }

    /// All non-loopback IPv4 addresses currently assigned, with their
    /// interface names (e.g. "en0", "utun4").
    static func ipv4Addresses() -> [Address] {
        var result: [Address] = []
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return [] }
        defer { freeifaddrs(ifaddrPtr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = ptr {
            defer { ptr = entry.pointee.ifa_next }
            let flags = Int32(entry.pointee.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP,
                  (flags & IFF_LOOPBACK) == 0,
                  let addr = entry.pointee.ifa_addr,
                  addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let r = getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                                &host, socklen_t(host.count),
                                nil, 0, NI_NUMERICHOST)
            guard r == 0 else { continue }
            let ip = String(cString: host)
            guard !ip.isEmpty else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            result.append(Address(interface: name, ip: ip))
        }
        return result
    }

    /// Tailscale hands out addresses in the CGNAT range 100.64.0.0/10.
    static func isTailscale(_ ip: String) -> Bool {
        let octets = ip.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets[0] == 100 else { return false }
        return (64...127).contains(octets[1])
    }

    /// RFC 1918 private ranges (10/8, 172.16/12, 192.168/16) — i.e. a normal
    /// home/office LAN address.
    static func isPrivateLAN(_ ip: String) -> Bool {
        let octets = ip.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else { return false }
        if octets[0] == 10 { return true }
        if octets[0] == 192, octets[1] == 168 { return true }
        if octets[0] == 172, (16...31).contains(octets[1]) { return true }
        return false
    }

    /// The Mac's mDNS/Bonjour hostname (e.g. "Tylers-Mac-mini.local"), if set.
    static var localHostName: String? {
        let name = ProcessInfo.processInfo.hostName
        return name.isEmpty ? nil : name
    }

    /// Best LAN IP (prefers en0, the built-in Ethernet/Wi-Fi), excluding
    /// Tailscale addresses.
    static func lanIP() -> String? {
        let addrs = ipv4Addresses().filter { isPrivateLAN($0.ip) && !isTailscale($0.ip) }
        return addrs.first(where: { $0.interface == "en0" })?.ip ?? addrs.first?.ip
    }

    /// The Tailscale IP, if Tailscale is connected.
    static func tailscaleIP() -> String? {
        ipv4Addresses().first(where: { isTailscale($0.ip) })?.ip
    }
}

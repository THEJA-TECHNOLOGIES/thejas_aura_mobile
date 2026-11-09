# Aura DNS Firewall

Aura is a high-performance cross-platform DNS Firewall and privacy protection system for Android and iOS, built with Flutter, native Kotlin (`VpnService`), and native Swift (`NetworkExtension` / `NEPacketTunnelProvider`).

---

## 1. System Architecture Overview

Aura intercepts all DNS traffic locally on the device using a VPN tunnel without routing general data traffic through a remote VPN server. All non-DNS traffic remains unaffected.

```
                              +---------------------------------------+
                              |         Client Applications           |
                              +---------------------------------------+
                                        |                   |
                                   UDP Port 53         TCP Port 53
                                        |                   |
                                        v                   v
+-----------------------------------------------------------------------------------------+
| Aura DNS Interception Layer                                                             |
|                                                                                         |
|  Android: VpnService TUN Interface                                                      |
|   └── AuraDnsPacketProcessor                                                            |
|        ├── UDP Parser & Router                                                          |
|        └── TcpConnectionManager (Userspace RFC 793 TCP Engine + RFC 7766 DNS Framing)   |
|                                                                                         |
|  iOS: NEPacketTunnelProvider                                                            |
|   └── AuraLocalDNSResolver                                                              |
|        ├── UDP Listener (BSD SOCK_DGRAM bound to 127.0.0.1:53)                          |
|        └── TCP Listener (BSD SOCK_STREAM bound to 127.0.0.1:53 + RFC 7766 Framing)       |
+-----------------------------------------------------------------------------------------+
                                        |
                                        v
+-----------------------------------------------------------------------------------------+
| Policy Engine (AuraDnsEngine / AuraDNSEngine)                                           |
|   ├── 1. Pause / Passthrough Check (Bypasses rules; logs as 'passthrough')              |
|   ├── 2. Exact Domain Rules                                                             |
|   ├── 3. Subdomain / Suffix Wildcard Rules                                              |
|   ├── 4. Custom Allow / Block Lists                                                     |
|   └── 5. Categories / Blocklist Attribution                                             |
+-----------------------------------------------------------------------------------------+
                                        |
                     +------------------+------------------+
                     | (If Allowed / Passthrough)          | (If Blocked)
                     v                                     v
+--------------------------------------+     +--------------------------------------------+
| Upstream Resolver Engine             |     | Synthetic DNS Block Response               |
|   ├── Step 1: Upstream UDP Query     |     |   - A: 0.0.0.0                             |
|   └── Step 2: Upstream TCP Fallback  |     |   - AAAA: ::                               |
|               (if UDP response TC=1) |     |   - Logged with category/source info       |
+--------------------------------------+     +--------------------------------------------+
                     |
                     v
+--------------------------------------+
| Public Upstream DNS (e.g. 1.1.1.1)   |
+--------------------------------------+
```

---

## 2. Downstream DNS-over-TCP Implementation (Phase 2)

### Android Architecture
* **Component**: `AuraDnsPacketProcessor.kt` and `TcpConnectionManager.kt`
* **Mechanism**: Intercepts raw TCP IPv4/IPv6 packets arriving at the TUN interface directed to port 53.
* **TCP State Machine**: Custom, robust userspace RFC 793 implementation (`LISTEN`, `SYN_RECEIVED`, `ESTABLISHED`, `CLOSE_WAIT`, `LAST_ACK`, `FIN_WAIT_1`, `FIN_WAIT_2`, `CLOSING`, `TIME_WAIT`, `CLOSED`).
* **Sequence & Window Tracking**: Full 32-bit wrapping sequence arithmetic, flow control, and sliding window management.
* **Retransmission & RTO**: RFC 6298 RTO algorithm (`SRTT`, `RTTVAR`, exponential backoff) with an initial RTO of 1000 ms and a minimum RTO of 200 ms (matching Linux `TCP_RTO_MIN` for virtual interfaces).
* **Port 853 DoT Handling**: Probes to TCP port 853 (DNS-over-TLS) are immediately answered with a TCP `RST/ACK` to allow client stub resolvers (such as Android Private DNS probes) to fall back cleanly to standard DNS without hanging or timing out.

### iOS Architecture
* **Component**: `AuraLocalDNSResolver.swift`
* **Mechanism**: Native kernel-backed BSD socket listener (`SOCK_STREAM`) bound to `127.0.0.1:53` alongside the UDP `SOCK_DGRAM` listener.
* **Concurrency & Dispatch**: Non-blocking connection acceptance via `DispatchSourceRead` on a dedicated serial dispatch queue (`com.thejatech.aura.dnsresolver.tcp`).
* **Connection Lifecycle**: Managed by `TcpClientConnection` instances, utilizing `SO_NOSIGPIPE`, non-blocking I/O, serialized writes, and buffered message reassembly.

---

## 3. DNS Message Framing and Buffer Limits

* **RFC 7766 Compliance**: DNS-over-TCP messages are preceded by a 2-byte unsigned big-endian length prefix.
* **Size Boundaries**:
  * Minimum valid DNS query size: 12 bytes (standard DNS header).
  * Maximum TCP query/response buffer: 16,384 bytes (16 KB), providing ample capacity for large DNSSEC key sets and resource records while guarding against resource exhaustion attacks.
* **Pipelining & Segmentation**: Both platforms support stream-oriented chunked arrivals and pipelined queries over persistent connections.

---

## 4. Response Sizing: UDP vs. TCP (RFC 6891 & RFC 7766)

* **UDP DNS Responses**:
  * Scoped to client EDNS0 buffer advertisements with a safe operational upper bound of 1,232 bytes (to prevent IPv6 fragmentation drops).
  * If the resolved DNS response exceeds this threshold, the resolver sets the Truncated bit (`TC=1`) with an empty or partial answer section, signaling the client to retry over TCP.
* **TCP DNS Responses**:
  * **Never truncated** to the UDP EDNS0 limit.
  * Responses up to 16 KB are returned intact with `TC=0` over the established TCP stream.

---

## 5. Phase 1.1: Upstream TCP Fallback

When querying upstream DNS servers (e.g. Cloudflare, Google, or configured resolver):
1. Aura queries the upstream server over UDP port 53.
2. If the upstream server returns a response with the Truncation flag set (`TC=1`), Aura immediately initiates an upstream TCP query (`queryUpstreamTcp`) to retrieve the complete DNS record set.
3. The complete record set is cached/processed and delivered back to the client.

---

## 6. Policy Enforcement, Pause/Passthrough, and Recovery

* **Rule Precedence**:
  1. Temporary Pause / Passthrough (Bypasses blocklists, logs match source as `passthrough`).
  2. Exact match allowlist.
  3. Exact match blocklist.
  4. Subdomain wildcard rules.
  5. Category and external blocklists.
  6. Default allow.
* **Temporary VPN Pause**:
  * Durations: 30 minutes, 2 hours, 3 hours.
  * The VPN tunnel and foreground service remain permanently active to prevent OS lifecycle teardown and background restart failures.
  * State is persisted across reboots and service recycles (`POLICY_PAUSED` on Android, `vpn_policy_mode = "paused"` in iOS App Group user defaults).
* **Expiry Reconciliation**:
  * Expiry is evaluated atomically on each arriving DNS query. Once expired, the policy reverts to active protection without requiring IPC or tunnel restart.
* **Manual Shutdown**:
  * Invoked by user explicitly turning off the VPN (`shutdownTunnel()`).
  * Disables auto-recovery flags to prevent unwanted reconnection.

---

## 7. Resource Management and Limits

| Parameter | Android | iOS |
|---|---|---|
| Max Concurrent TCP Connections | 100 | 100 |
| Idle Connection Timeout | 30 seconds | 10 seconds |
| Half-Open Connection Timeout | 10 seconds | 3 seconds |
| Timer / Maintenance Tick | 200 ms background executor | 200 ms / idle dispatch timer |
| Max DNS Message Buffer | 16,384 bytes | 16,384 bytes |
| UDP Response Operational Cap | 1,232 bytes | 1,232 bytes |

---

## 8. Platform Differences & Known Limitations

1. **TCP Implementation**:
   * Android uses a custom userspace TCP engine inside `AuraVpnService` because Android's `VpnService` exposes raw IP packets via a virtual TUN file descriptor.
   * iOS uses the kernel's BSD TCP stack (`SOCK_STREAM`) bound to `127.0.0.1:53` because `NEPacketTunnelProvider` routes DNS through local loopback.
2. **TCP Features**:
   * SACK (Selective Acknowledgment) and TCP Window Scaling are intentionally omitted from the Android userspace stack as DNS query/response transactions are short-lived request-response streams.
3. **Protocols Out of Scope**:
   * Direct DNS-over-TLS (DoT, port 853) and DNS-over-HTTPS (DoH, port 443) are not terminated by Aura. Port 853 probes are reset via TCP RST to trigger graceful fallback to standard DNS.

---

## 9. Verification & Physical Device Status

### Automated Test Suites
* **Android**:
  * Unit & Integration Tests: **10 test suites passed** (including `TcpPacketParserTest`, `TcpConnectionManagerTest`, `AuraDnsPacketProcessorTest`).
  * Build Verification: Kotlin compilation and debug APK assembly (`:app:assembleDebug`) completed successfully.
* **iOS**:
  * Unit & Integration Tests: **4 test suites passed** on simulator (`AuraTCPDNSTests`, `AuraDatabaseTests`, `AuraReleaseStoreTests`, `RunnerTests`).
  * Build Verification: Xcode builds for `AuraTunnel` extension and `Runner` application succeeded.
* **Flutter**:
  * Domain logic, pause/passthrough, and dashboard widget tests verified.

### Hardware / Physical Device Testing Guide
When testing on physical devices:
* **Android** (via adb):
  ```bash
  # Check connected device
  adb devices
  # Test downstream TCP DNS through the VPN tunnel
  adb shell dig @10.255.255.1 +tcp example.com
  ```
* **iOS** (via local terminal / app):
  ```bash
  # Inspect connected devices
  xcrun devicectl list devices
  ```

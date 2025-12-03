# ADR 0005: WireGuard for Overlay Networking

## Status

Accepted

## Context

Containers on different nodes need to communicate. This requires an overlay network. The overlay should be secure, especially for clusters spanning untrusted networks.

Options considered:
- **VXLAN only**: Standard, used by Docker Swarm, not encrypted
- **WireGuard only**: Encrypted, simple, modern
- **IPsec**: Enterprise standard, complex configuration
- **Both VXLAN and WireGuard**: Flexibility for different environments

## Decision

Use WireGuard as the primary overlay network, with VXLAN as an option for trusted LANs.

## Rationale

1. **Encrypted by default**: All node-to-node traffic encrypted. No separate VPN needed.

2. **Simple configuration**: WireGuard has minimal configuration compared to IPsec.

3. **Performance**: WireGuard is fast, implemented in kernel (Linux 5.6+).

4. **NAT traversal**: Works across NAT, important for heterogeneous networks.

5. **Modern cryptography**: ChaCha20, Curve25519, etc.

## Architecture

```
Node A                              Node B
┌─────────────────┐            ┌─────────────────┐
│  Container      │            │  Container      │
│  10.100.0.2     │            │  10.100.0.3     │
└────────┬────────┘            └────────┬────────┘
         │                              │
    ┌────▼────┐                    ┌────▼────┐
    │  wg0    │◄───encrypted────►  │  wg0    │
    └────┬────┘                    └────┬────┘
         │                              │
    Physical Network
```

## Key Management

- Each node generates WireGuard keypair on init
- Public keys exchanged via cluster membership (gossip)
- Cluster secret authenticates new nodes
- Keys rotated periodically (future)

## Consequences

**Positive:**
- Secure by default
- Simple setup for users
- Works across NAT/firewalls
- Good performance

**Negative:**
- Requires WireGuard (kernel module or userspace)
- Full mesh = O(N²) connections (fine for <1000 nodes)
- More overhead than raw VXLAN on trusted LANs

**Mitigations:**
- Support VXLAN as alternative for trusted networks
- Userspace WireGuard for environments without kernel module
- Document network requirements

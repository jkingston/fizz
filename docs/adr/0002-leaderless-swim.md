# ADR 0002: Leaderless Architecture with SWIM Protocol

## Status

Accepted

## Context

Fizz aims to be simpler than Kubernetes. A key complexity in K8s is the control plane: etcd cluster, API server, scheduler, controller manager. These components must be highly available and add operational burden.

Options considered:
- **Raft-based leader election** (like Nomad): Simpler than K8s, but still has leader
- **SWIM + gossip** (like Serf/Consul): No leader, all nodes equal
- **Central coordinator**: Simple but single point of failure

## Decision

Use a leaderless architecture with SWIM protocol for membership and gossip for state dissemination.

## Rationale

1. **No single point of failure**: Every node is equal. Losing any node doesn't affect cluster operation (as long as quorum remains for any quorum-requiring operations).

2. **Simpler operations**: No need to bootstrap a leader, handle leader failures, or manage leader election.

3. **Proven at scale**: SWIM is used by HashiCorp Serf, which underlies Consul. Proven with clusters of 10,000+ nodes.

4. **O(1) message overhead**: Unlike heartbeating (O(N²)), SWIM has constant per-node message overhead regardless of cluster size.

5. **Failure detection included**: SWIM handles both membership and failure detection in one protocol.

## Consequences

**Positive:**
- Simpler architecture (no control plane)
- Better availability (no leader dependency)
- Scales well (constant overhead per node)
- Failure detection built-in

**Negative:**
- Eventual consistency only (no strong consistency)
- Scheduling conflicts possible (resolved via deterministic tie-breaking)
- Some operations harder without coordination (e.g., exactly-once semantics)

**Mitigations:**
- Use CRDTs for conflict-free state
- Deterministic scheduling via consistent hashing
- Accept eventual consistency as trade-off for simplicity
- Document consistency guarantees clearly

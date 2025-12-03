# ADR 0003: Use CRDTs for Distributed State

## Status

Accepted

## Context

In a leaderless system, multiple nodes may update state concurrently. Without coordination, this leads to conflicts. We need a strategy for state management that works without a leader.

Options considered:
- **Consensus (Raft/Paxos)**: Strong consistency, requires leader
- **CRDTs**: Eventual consistency, no coordination needed
- **Last-writer-wins everywhere**: Simple but loses updates
- **Operational transforms**: Complex, designed for text editing

## Decision

Use CRDTs (Conflict-free Replicated Data Types) for all distributed state.

## Rationale

1. **No coordination required**: CRDTs merge automatically without consensus. Perfect for leaderless architecture.

2. **Guaranteed convergence**: Mathematical properties ensure all nodes converge to same state.

3. **Partition tolerant**: Nodes can operate independently during network partitions and merge when reconnected.

4. **Well-understood**: Extensive academic research and production use (Redis, Riak, etc.).

## CRDT Types Used

| State | CRDT | Why |
|-------|------|-----|
| Service definitions | LWW-Register | Single value, last update wins |
| Container set | OR-Set | Add/remove containers, handles concurrent updates |
| Node metadata | LWW-Map | Map of node properties |
| Resource counters | PN-Counter | Track available/used resources |
| IP allocations | OR-Set | Track allocated IPs |

## Consequences

**Positive:**
- Fits leaderless design naturally
- Handles network partitions gracefully
- Predictable merge behavior
- No coordination overhead

**Negative:**
- Eventual consistency only (not immediate)
- Some operations need careful design (e.g., reserving resources)
- Tombstones can accumulate (need garbage collection)
- LWW requires synchronized clocks (or hybrid logical clocks)

**Mitigations:**
- Use hybrid logical clocks for LWW ordering
- Implement tombstone garbage collection
- Document consistency guarantees
- Design operations to be CRDT-friendly

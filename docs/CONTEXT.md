# Fizz Orchestrator - Technical Context

Background research and rationale for design decisions.

---

## Table of Contents

1. [Existing Orchestrators](#existing-orchestrators)
2. [Docker Compose Specification](#docker-compose-specification)
3. [Cluster Membership Protocols](#cluster-membership-protocols)
4. [Distributed State Management](#distributed-state-management)
5. [Scheduling Approaches](#scheduling-approaches)
6. [Overlay Networking](#overlay-networking)
7. [Secrets Management](#secrets-management)
8. [Why Zig](#why-zig)

---

## Existing Orchestrators

### Kubernetes

**Architecture:**
- Control plane: API server, etcd, scheduler, controller manager
- Node agents: kubelet on each node communicates with control plane
- All state stored in etcd (distributed key-value store using Raft)
- API server is the only component that talks to etcd

**Scheduling:**
- Two-phase: filtering (which nodes can run this?) then scoring (which is best?)
- Considers resources, affinity, taints/tolerations, topology
- Extensible via scheduling plugins

**Networking:**
- CNI (Container Network Interface) plugins handle pod networking
- kube-proxy manages service routing (iptables, IPVS, or nftables mode)
- Every pod gets a unique IP, no NAT between pods

**Operators:**
- Custom Resource Definitions (CRDs) extend the API
- Controllers watch resources and reconcile desired vs actual state
- Enables complex stateful workload management

**Lessons for Fizz:**
- Control plane is complex and a single point of failure
- etcd + Raft is battle-tested but requires careful operation
- CRD/operator pattern is powerful for extensibility
- CNI abstraction is good but adds complexity

### HashiCorp Nomad

**Architecture:**
- Single binary for both clients and servers
- Servers use Raft for consensus (3 or 5 recommended)
- Clients run workloads and report to servers
- Much simpler than Kubernetes

**Key Differentiator:**
- Focuses only on scheduling and cluster management
- Integrates with Consul (service discovery) and Vault (secrets)
- Supports containers, VMs, and raw executables
- Unix philosophy: do one thing well

**Federation:**
- Multiple regions can federate
- Each region is independent but can share state
- Authoritative region for ACL policies
- Workloads don't automatically failover across regions

**Lessons for Fizz:**
- Simplicity is achievable and valuable
- Single binary distribution is a major UX win
- Federation adds complexity; make it optional
- Separation of concerns (scheduling vs service mesh vs secrets) is clean

### Docker Swarm

**Architecture:**
- Manager nodes use Raft for consensus
- Worker nodes follow instructions from managers
- Managers can also run workloads
- Decentralized worker communication via gossip

**Networking:**
- Built-in overlay networking using VXLAN
- Routing mesh: any node can accept traffic for any service
- Automatic service discovery via DNS

**Simplicity:**
- Built into Docker, no separate install
- `docker swarm init` creates a cluster
- Compose files work with minor modifications

**Lessons for Fizz:**
- Swarm proves overlay networking can be automatic
- Routing mesh is excellent UX (any node accepts traffic)
- Raft for managers + gossip for workers is a good hybrid
- Simplicity drove adoption despite fewer features than K8s

---

## Docker Compose Specification

### Top-Level Elements

```yaml
name: myapp                 # Project name (optional)
services: {}                # Container definitions
networks: {}                # Network definitions
volumes: {}                 # Volume definitions
configs: {}                 # Config file definitions
secrets: {}                 # Secret definitions
```

### Service Configuration

**Core fields:**
- `image` - Container image
- `build` - Build context and Dockerfile
- `command` / `entrypoint` - Override defaults
- `environment` / `env_file` - Environment variables
- `ports` - Port mappings
- `volumes` - Mount points
- `networks` - Network attachments

**Deployment (Swarm mode):**
```yaml
deploy:
  mode: replicated          # or global
  replicas: 3
  placement:
    constraints:
      - node.role == worker
      - node.labels.zone == us-east
    preferences:
      - spread: node.labels.zone
  resources:
    limits:
      cpus: '0.5'
      memory: 512M
  restart_policy:
    condition: on-failure
    max_attempts: 3
  update_config:
    parallelism: 2
    delay: 10s
    order: start-first
```

**Health checks:**
```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s
```

**Dependencies:**
```yaml
depends_on:
  db:
    condition: service_healthy
  redis:
    condition: service_started
  migrations:
    condition: service_completed_successfully
```

### Extension Fields

Fields starting with `x-` are ignored by Docker Compose but preserved:

```yaml
x-fizz:
  placement:
    zone: us-east

services:
  web:
    x-fizz:
      scaling:
        min: 2
        max: 10
```

This is the primary mechanism for orchestrator-specific configuration.

### Environment Interpolation

```yaml
services:
  web:
    image: ${REGISTRY}/myapp:${VERSION:-latest}
    environment:
      - DB_HOST=${DB_HOST:?DB_HOST must be set}
```

Syntax:
- `${VAR}` - Variable value
- `${VAR:-default}` - Default if unset or empty
- `${VAR-default}` - Default if unset
- `${VAR:?error}` - Error if unset or empty

### Secrets in Compose

```yaml
services:
  db:
    secrets:
      - db_password
      - source: api_key
        target: /run/secrets/api_key
        mode: 0400

secrets:
  db_password:
    file: ./secrets/db_password.txt
  api_key:
    external: true
```

In Swarm mode, secrets are:
- Stored encrypted in Raft log
- Transmitted over mTLS
- Mounted as tmpfs (never on disk)
- Automatically unmounted when container stops

---

## Cluster Membership Protocols

### Traditional Heartbeating

Every node sends heartbeat to every other node:
- N nodes = N² messages per interval
- 100 nodes = 10,000 messages/second
- Does not scale

### SWIM Protocol

**Scalable Weakly-consistent Infection-style Membership**

Core insight: Separate failure detection from dissemination.

**Failure Detection:**
1. Each period T, node picks random peer and sends PING
2. If ACK received, peer is alive
3. If no ACK, send PING-REQ to k random nodes
4. Those nodes ping the suspect and relay ACK
5. If still no response, mark as suspicious
6. After timeout, mark as failed

**Dissemination:**
- Piggyback membership updates on PING/ACK messages
- Updates spread epidemically (like gossip)
- No extra messages needed

**Properties:**
- O(1) message load per node (constant, not O(N))
- Detection time independent of cluster size
- False positive rate independent of cluster size

**Suspicion Mechanism:**
- Avoids false positives from transient network issues
- Suspicious nodes can refute by incrementing incarnation number
- Only marked dead after suspicion timeout

### Lifeguard Enhancements

HashiCorp improvements to SWIM:

- Handles "gray failures" (node partially responsive)
- Reduces false positives by 50x
- Faster detection of true failures
- Implemented in Serf, Consul, Nomad

### Why SWIM for Fizz

- Proven at scale (Consul runs clusters of 10,000+ nodes)
- No leader required for membership
- Failure detection is distributed
- Message overhead is constant regardless of cluster size
- Well-documented with reference implementations

---

## Distributed State Management

### The CAP Theorem

Distributed systems can only guarantee 2 of 3:
- **Consistency**: All nodes see same data
- **Availability**: Every request gets a response
- **Partition tolerance**: System works despite network splits

Since network partitions happen, choice is CP or AP.

### CRDTs (Conflict-free Replicated Data Types)

Data structures that can be replicated and merged without coordination:

**G-Counter (Grow-only Counter):**
- Each node maintains its own counter
- Merge: take max of each node's counter
- Value: sum of all counters
- Use case: counting events

**PN-Counter (Positive-Negative Counter):**
- Two G-Counters: one for increments, one for decrements
- Value: P - N
- Use case: tracking available resources

**LWW-Register (Last-Writer-Wins Register):**
- Value + timestamp
- Merge: keep value with highest timestamp
- Requires synchronized clocks (or logical clocks)
- Use case: single values that can be overwritten

**OR-Set (Observed-Remove Set):**
- Each add tagged with unique ID
- Remove only removes observed tags
- Merge: union of all tags, minus removed
- Use case: tracking set membership (containers, services)

**Properties:**
- Commutative: merge(A,B) = merge(B,A)
- Associative: merge(merge(A,B),C) = merge(A,merge(B,C))
- Idempotent: merge(A,A) = A

### Gossip Protocol

Epidemic broadcast for state dissemination:

1. Periodically, each node picks random peers (fanout)
2. Sends state delta or full state
3. Recipient merges with local state
4. Repeats

**Properties:**
- Convergence in O(log N) rounds
- Tolerates node failures
- No single point of failure
- Eventually consistent

### Anti-Entropy

Periodic full-state synchronization to handle missed updates:

- Nodes periodically exchange full state with random peer
- Merkle trees can optimize to only sync differences
- Catches any updates missed by gossip

### Why CRDTs for Fizz

- No coordination needed (fits leaderless design)
- Network partitions don't cause conflicts
- Merge is automatic and deterministic
- Well-understood correctness properties
- Can be verified with property-based testing

---

## Scheduling Approaches

### Monolithic Scheduler (Kubernetes)

- Single scheduler makes all decisions
- Full view of cluster state
- Optimizes globally
- Can become bottleneck at scale

### Two-Level Scheduler (Mesos)

- Resource offers from nodes to frameworks
- Frameworks decide what to accept
- Scales better but less optimal placement

### Shared-State Scheduler (Omega)

- Multiple schedulers with full cluster view
- Optimistic concurrency: commit or retry
- Scales well, good placement
- Never fully deployed at Google

### Consistent Hashing

Maps keys to nodes on a ring:

1. Hash each node to position(s) on ring
2. Hash workload key to position
3. Walk clockwise to find responsible node

**Properties:**
- Adding/removing node only affects neighbors
- K/N keys remapped on node change (K=keys, N=nodes)
- Virtual nodes improve balance (100-200 per physical node)

**For scheduling:**
- Hash: service_name + replica_index
- Walk ring until finding node meeting constraints
- Deterministic: all nodes compute same placement
- Conflict resolution: lowest node ID wins

### Why Consistent Hashing for Fizz

- Deterministic without coordination
- Minimal reshuffling on cluster changes
- Each node can compute placement independently
- Well-suited to leaderless architecture

---

## Overlay Networking

### VXLAN (Virtual Extensible LAN)

Encapsulates L2 frames in UDP packets:

```
[Outer Ethernet][Outer IP][Outer UDP][VXLAN Header][Inner Ethernet][Inner IP][Payload]
```

**Components:**
- VTEP (VXLAN Tunnel Endpoint) on each host
- VNI (VXLAN Network Identifier) - 24 bits = 16M networks
- UDP port 4789

**How it works:**
1. Container sends packet to another container
2. Local VTEP looks up destination VTEP
3. Encapsulates frame with VXLAN header
4. Sends over physical network
5. Remote VTEP decapsulates
6. Delivers to destination container

**Pros:**
- Standard, widely supported
- Works over any IP network
- Same as Docker Swarm uses

**Cons:**
- Not encrypted by default
- MTU overhead (50 bytes)
- Requires multicast or control plane for VTEP discovery

### WireGuard

Modern VPN protocol:

- Simple: ~4,000 lines of code
- Fast: in-kernel, minimal overhead
- Secure: modern cryptography (ChaCha20, Curve25519)
- UDP-based, handles NAT traversal

**For overlay networking:**
- Each node has WireGuard interface
- Peers configured with public keys
- All traffic encrypted automatically
- Can work across NAT/firewalls

**Mesh topology:**
- Every node connects to every other node
- Direct paths minimize latency
- Automatic key exchange via cluster membership

**Pros:**
- Encrypted by default
- Excellent performance
- Simple configuration
- Works across WAN/internet

**Cons:**
- Requires WireGuard kernel module or userspace implementation
- Full mesh is O(N²) connections

### Why Both for Fizz

- **VXLAN** for local/LAN clusters (low overhead, standard)
- **WireGuard** for WAN/federation (encryption required)
- Let users choose based on their network

---

## Secrets Management

### The Problem

- Secrets (passwords, API keys, certificates) needed by containers
- Can't store in images (shared, versioned)
- Can't store in compose files (committed to git)
- Need encryption at rest and in transit
- Need access control (which container sees what)

### Docker Swarm Approach

- Secrets stored encrypted in Raft log
- Decrypted only in memory of target node
- Mounted as tmpfs (never on disk)
- Scoped to specific services

### HashiCorp Vault Approach

- Centralized secret store
- Dynamic secrets (generated on demand with TTL)
- Encryption as a service
- Complex to operate

### SOPS + Age

**SOPS (Secrets OPerationS):**
- Encrypts values in YAML/JSON files
- Keys remain plaintext for version control diffs
- Supports multiple encryption backends

**Age:**
- Modern encryption tool
- Simple: one command, one key format
- No configuration, no key servers
- X25519 + ChaCha20-Poly1305

**For GitOps:**
```yaml
secrets:
  db_password:
    x-fizz:
      encrypted: age1qyqszqgpqx... # Encrypted with age
```

Can commit to git safely, decrypt at deploy time.

### Shamir's Secret Sharing

Split a secret into N shares, require M to reconstruct:

- Master key split into 5 shares
- Any 3 shares can reconstruct
- Losing 2 shares doesn't compromise secret
- No single point of failure

**For Fizz:**
- Cluster master key split across nodes
- 3-of-5 threshold (survives 2 node failures)
- New nodes receive share during join
- Secret encrypted with key derived from master + path

### Why Age + Shamir for Fizz

- Age is simple and modern (no PGP complexity)
- Shamir distributes trust (no single key holder)
- GitOps friendly (encrypted secrets in repo)
- No external dependencies (unlike Vault)

---

## Why Zig

### Single Binary Distribution

- No runtime dependencies
- Cross-compile from any host to any target
- Small binaries (~few MB)
- Important for "curl | sh" installation

### C Interoperability

- Call C libraries directly (libyaml, SQLite, WireGuard)
- No FFI overhead or complexity
- Access to mature ecosystem

### Explicit Memory Management

- Allocator passed explicitly
- No hidden allocations
- Predictable performance
- Good for long-running services

### Safety Without GC

- No garbage collector pauses
- Compile-time checks catch many bugs
- Runtime safety checks (optional)
- Suitable for systems programming

### Comparison to Alternatives

**Go:**
- Garbage collector causes latency spikes
- Larger binaries
- Good networking stdlib though

**Rust:**
- Excellent safety but steep learning curve
- Longer compile times
- Borrow checker complexity for concurrent code

**C:**
- No safety guarantees
- Manual memory management error-prone
- Would work but more dangerous

**Zig:**
- Middle ground: safe enough, simple enough
- Great for networked systems code
- Growing ecosystem

---

## References

### Orchestrators
- [Kubernetes Components](https://kubernetes.io/docs/concepts/overview/components/)
- [Nomad Architecture](https://developer.hashicorp.com/nomad/docs/concepts/architecture)
- [Docker Swarm](https://docs.docker.com/engine/swarm/)

### Compose
- [Compose Specification](https://www.compose-spec.io/)
- [compose-go library](https://github.com/compose-spec/compose-go)

### SWIM & Gossip
- [SWIM Paper](https://www.cs.cornell.edu/projects/Quicksilver/public_pdfs/SWIM.pdf)
- [Lifeguard](https://arxiv.org/abs/1707.00788)
- [Serf](https://www.serf.io/docs/internals/gossip.html)

### CRDTs
- [CRDTs: Consistency without consensus](https://crdt.tech/)
- [A comprehensive study of CRDTs](https://hal.inria.fr/inria-00555588/document)

### Networking
- [VXLAN RFC 7348](https://datatracker.ietf.org/doc/html/rfc7348)
- [WireGuard Protocol](https://www.wireguard.com/protocol/)

### Secrets
- [Age Encryption](https://age-encryption.org/)
- [SOPS](https://github.com/getsops/sops)
- [Shamir's Secret Sharing](https://en.wikipedia.org/wiki/Shamir%27s_secret_sharing)

### Zig
- [Zig Language](https://ziglang.org/)
- [Zig Networking](https://github.com/ziglang/zig/blob/master/lib/std/net.zig)

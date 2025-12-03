# Roadmap

Implementation milestones for Fizz.

## Status

| | |
|---|---|
| **Phase** | Design |
| **MVP** | M2 (Single-Node Orchestration) |
| **Next** | M0 - Project Bootstrap |
| **Started** | Not yet |

---

## Milestones Overview

| # | Milestone | Status | User Value |
|---|-----------|--------|------------|
| 0 | Project Bootstrap | Not started | Project builds |
| 1 | Compose Parsing | Not started | Validate compose files |
| 2 | Single-Node Orchestration | Not started | **MVP: Run compose files locally** |
| 3 | State & Persistence | Not started | Survives restarts |
| 4 | REST API & Observability | Not started | Monitor with Grafana |
| 5 | Cluster Membership | Not started | Nodes discover each other |
| 6 | Distributed State | Not started | State syncs automatically |
| 7 | Distributed Scheduler | Not started | **Auto-failover and scaling** |
| 8 | Service Networking | Not started | Cross-node communication |
| 9 | Secrets Management | Not started | Encrypted credentials |
| 10 | P2P Image Registry | Not started | Fast offline deployments |
| 11 | Federation | Not started | Multi-datacenter |
| 12 | Operators | Not started | Custom automation |

---

## Dependency Graph

```
M0 (Bootstrap)
 │
 ▼
M1 (Compose Parsing)
 │
 ▼
M2 (Single-Node) ◄────────── First usable product
 │
 ├───► M3 (Persistence)
 │      │
 │      ▼
 │     M4 (API/Observability)
 │      │
 ▼      │
M5 (Membership) ◄────────────┘
 │
 ▼
M6 (Distributed State)
 │
 ▼
M7 (Scheduler) ◄──────────── Core cluster value
 │
 ├───► M8 (Networking)
 │
 ├───► M9 (Secrets)
 │
 └───► M10 (Registry)
        │
        ▼
       M11 (Federation)
        │
        ▼
       M12 (Operators)
```

---

## Milestone Details

### M0: Project Bootstrap

**Goal:** Buildable project with development infrastructure

**Outcomes:**
- [ ] Project compiles with `zig build`
- [ ] Tests run with `zig build test`
- [ ] Structured JSON logging operational
- [ ] CLI framework parses commands
- [ ] CI pipeline runs on commits

**Exit Criteria:** `fizz --version` prints version string

---

### M1: Compose Parsing

**Goal:** Parse and validate docker-compose.yml files

**Outcomes:**
- [ ] Parse all standard compose fields
- [ ] Support `x-fizz` extension blocks
- [ ] Environment variable interpolation (`${VAR:-default}`)
- [ ] Validate against compose specification
- [ ] Clear error messages for invalid files

**Exit Criteria:** `fizz validate docker-compose.yml` reports success/errors

---

### M2: Single-Node Orchestration (MVP)

**Goal:** Run compose files on a single machine via Docker

> This is the **Minimum Viable Product**. At M2 completion, Fizz provides value as a Docker Compose alternative with better health monitoring and restart behavior.

**Outcomes:**
- [ ] Create networks and volumes
- [ ] Start containers in dependency order
- [ ] Monitor health checks
- [ ] Restart unhealthy containers
- [ ] Stream logs from containers
- [ ] Stop and remove on `down`

**Commands Working:**
- `fizz up [-f file]`
- `fizz down [-f file]`
- `fizz ps`
- `fizz logs [service]`

**Exit Criteria:**
```bash
# This test must pass:
fizz up -f examples/wordpress-compose.yml
curl http://localhost:8080  # WordPress responds
fizz down
```

**What's NOT included:** Clustering, custom networking, secrets encryption

---

### M3: State & Persistence

**Goal:** Orchestrator state survives restarts

**Outcomes:**
- [ ] Track deployments in SQLite
- [ ] Recover container state on startup
- [ ] Store desired replica counts
- [ ] `fizz inspect` shows full state

**Exit Criteria:** `fizz` restart doesn't lose track of running containers

---

### M4: REST API & Observability

**Goal:** Programmatic access and operational visibility

**Outcomes:**
- [ ] REST API for services, containers, deployments
- [ ] Prometheus metrics at `/metrics`
- [ ] JSON structured logs
- [ ] Event stream via SSE
- [ ] `fizz events` command

**Exit Criteria:** Can scrape metrics with Prometheus, see events in real-time

---

### M5: Cluster Membership

**Goal:** Nodes discover and monitor each other

**Outcomes:**
- [ ] SWIM protocol implementation
- [ ] Join cluster via any peer
- [ ] Detect failed nodes
- [ ] Graceful leave
- [ ] Exchange node metadata

**Commands Working:**
- `fizz init`
- `fizz join <addr>`
- `fizz leave`
- `fizz nodes`

**Exit Criteria:** Three nodes form cluster, one dies, others detect failure

**What's NOT included:** State sync (nodes still independent)

---

### M6: Distributed State

**Goal:** Cluster state converges without coordination

**Outcomes:**
- [ ] CRDT implementations (G-Counter, OR-Set, LWW-Register, LWW-Map)
- [ ] Gossip state dissemination
- [ ] Anti-entropy synchronization
- [ ] Service definitions replicate to all nodes

**Exit Criteria:** Define service on node A, visible on node B within seconds

---

### M7: Distributed Scheduler

**Goal:** Services run across cluster with automatic failover

**Outcomes:**
- [ ] Consistent hash ring placement
- [ ] Constraint evaluation (labels, resources)
- [ ] Reconciliation loop
- [ ] Automatic rescheduling on node failure
- [ ] Rolling updates

**Commands Working:**
- `fizz scale <service>=N`

**Exit Criteria:** Kill a node, its containers restart on surviving nodes

---

### M8: Service Networking

**Goal:** Containers communicate across nodes

**Outcomes:**
- [ ] Distributed IPAM
- [ ] WireGuard mesh between nodes
- [ ] Embedded DNS for service discovery
- [ ] Ingress routing (any node accepts traffic)
- [ ] Load balancing across replicas

**Exit Criteria:** Container on node A can reach container on node B by service name

---

### M9: Secrets Management

**Goal:** Secure secret storage and injection

**Outcomes:**
- [ ] Age encryption at rest
- [ ] Shamir secret sharing for master key
- [ ] Scope secrets to deployment/container
- [ ] Mount secrets as tmpfs
- [ ] `fizz secret` commands

**Exit Criteria:** Create secret, reference in compose, verify injected into container

---

### M10: P2P Image Registry

**Goal:** Efficient image distribution

**Outcomes:**
- [ ] OCI registry API
- [ ] Content-addressable layer storage
- [ ] P2P layer sharing between nodes
- [ ] Garbage collection
- [ ] Fallback to upstream registry

**Exit Criteria:** Second node pulls image from first node, not Docker Hub

---

### M11: Federation

**Goal:** Multiple clusters work together

**Outcomes:**
- [ ] WAN-optimized gossip
- [ ] Cross-cluster service discovery
- [ ] Cluster-scoped secrets
- [ ] Global ingress routing

**Exit Criteria:** Service in cluster A reachable from cluster B

---

### M12: Operators

**Goal:** Custom resource automation

**Outcomes:**
- [ ] Custom Resource Definition schema
- [ ] Controller runtime
- [ ] Watch API
- [ ] Built-in database operator

**Exit Criteria:** Deploy a Database CR, operator creates StatefulSet-like service

---

## Version Planning

| Version | Milestones | Theme |
|---------|------------|-------|
| 0.1 | M0-M2 | Single-node, compose replacement |
| 0.2 | M3-M4 | Production-ready single node |
| 0.3 | M5-M7 | Basic clustering |
| 0.4 | M8-M9 | Secure cluster networking |
| 0.5 | M10 | Self-sufficient cluster |
| 1.0 | M11-M12 | Federation and extensibility |

---

## Progress Log

_Updates will be logged here as milestones complete._

| Date | Milestone | Notes |
|------|-----------|-------|
| - | - | - |

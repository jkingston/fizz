# Architecture

System design for the Fizz orchestrator.

## Table of Contents

- [Overview](#overview)
- [Components](#components)
- [Data Flow](#data-flow)
- [Key Abstractions](#key-abstractions)
- [State Schema](#state-schema)
- [State Transitions](#state-transitions)
- [Consistency Guarantees](#consistency-guarantees)
- [Network Architecture](#network-architecture)
- [Security Model](#security-model)
- [Configuration](#configuration)

---

## Overview

Fizz is a distributed system where every node runs the same binary and participates as an equal peer. There is no separate control plane or leader node.

```
┌─────────────────────────────────────────────────────────────────┐
│                         Fizz Node                               │
├─────────────────────────────────────────────────────────────────┤
│                        User Interface                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │   REST API   │  │     CLI      │  │   Compose Parser     │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                        Core Engine                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │  Scheduler   │  │   Health     │  │  State Manager       │  │
│  │              │  │   Monitor    │  │  (CRDTs)             │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                       Cluster Layer                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │    SWIM      │  │   Gossip     │  │   Federation         │  │
│  │  Membership  │  │   Protocol   │  │   (future)           │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                       Backend Layer                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │   Runtime    │  │   Network    │  │   Storage            │  │
│  │ Docker/Podman│  │  WireGuard   │  │   Local/NFS          │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Components

### User Interface Layer

**CLI**
- Primary user interface
- Commands: `up`, `down`, `ps`, `logs`, `nodes`, `join`, `leave`
- Communicates with local node via REST API

**REST API**
- HTTP API for all operations
- Used by CLI and external tools
- Prometheus metrics endpoint
- Server-sent events for real-time updates

**Compose Parser**
- Parses docker-compose.yml files
- Handles environment variable interpolation
- Extracts `x-fizz` extensions for orchestrator-specific config

### Core Engine

**Scheduler**
- Decides which node runs each container
- Uses consistent hashing for deterministic placement
- Evaluates constraints (labels, resources, affinity)
- Reconciles desired state with actual state

**Health Monitor**
- Executes container health checks
- Tracks container state (running, healthy, unhealthy)
- Triggers restarts or rescheduling on failure

**State Manager**
- Stores cluster state using CRDTs
- Service definitions, container assignments, node metadata
- Merges state from other nodes without conflicts

### Cluster Layer

**SWIM Membership**
- Maintains list of cluster members
- Detects node failures via probe protocol
- Distributed failure detection (no central monitor)

**Gossip Protocol**
- Disseminates state changes across cluster
- Piggybacked on SWIM protocol messages
- Provides eventual consistency

**Federation** (future)
- Connects multiple clusters over WAN
- Selective state synchronization
- Cross-cluster service discovery

### Backend Layer

**Runtime**
- Interface to container runtime (Docker, Podman)
- Container lifecycle: create, start, stop, remove
- Image pulling and management

**Network**
- Overlay networking for cross-node communication
- WireGuard mesh for encrypted traffic
- Service discovery via embedded DNS
- Ingress routing

**Storage**
- Volume management
- Local volumes, NFS mounts
- Future: distributed storage

## Data Flow

### Deploying a Compose File

```
User: fizz up -f compose.yml
         │
         ▼
    ┌─────────┐
    │   CLI   │ ──parse──▶ Compose Parser
    └────┬────┘
         │ HTTP POST /deployments
         ▼
    ┌─────────┐
    │   API   │
    └────┬────┘
         │
         ▼
    ┌─────────────┐
    │   State     │ ──store──▶ Service definitions (CRDT)
    │   Manager   │
    └──────┬──────┘
           │ gossip
           ▼
    ┌─────────────┐
    │   Other     │  All nodes receive service definitions
    │   Nodes     │
    └──────┬──────┘
           │
           ▼
    ┌─────────────┐
    │  Scheduler  │  Each node checks if it should run containers
    └──────┬──────┘
           │
           ▼
    ┌─────────────┐
    │   Runtime   │  Start containers on assigned nodes
    └─────────────┘
```

### Node Failure Recovery

```
    ┌─────────────┐
    │  Node A     │ ──PING──▶ Node B (no response)
    │  (SWIM)     │
    └──────┬──────┘
           │ indirect probe via Node C
           ▼
    ┌─────────────┐
    │  Node C     │ ──PING──▶ Node B (no response)
    └──────┬──────┘
           │
           ▼
    Node B marked suspicious, then dead
           │
           ▼
    ┌─────────────┐
    │  Scheduler  │  Containers from Node B need new homes
    └──────┬──────┘
           │ consistent hash picks new nodes
           ▼
    ┌─────────────┐
    │  Nodes A,C  │  Start containers previously on Node B
    └─────────────┘
```

## Key Abstractions

### Service

A service is a logical grouping defined in a compose file:
- Image to run
- Number of replicas
- Resource requirements
- Health check configuration
- Network attachments

### Container

A running instance of a service:
- Belongs to exactly one service
- Runs on exactly one node
- Has a unique ID
- Tracked in cluster state

### Node

A machine running the Fizz binary:
- Unique ID (generated on first run)
- Address (IP + port)
- Labels (user-defined metadata)
- Resources (CPU, memory)
- State (alive, suspicious, dead, left)

### Deployment

A deployed compose file:
- Name (from compose file or directory)
- Set of services
- Networks and volumes
- Secrets references

## State Schema

All cluster state is stored as CRDTs and synchronized via gossip.

| State | CRDT Type | Description |
|-------|-----------|-------------|
| Nodes | LWW-Map | Node ID → Node metadata |
| Services | LWW-Map | Service name → Service definition |
| Containers | OR-Set | Set of (container ID, node ID, service) |
| Deployments | LWW-Map | Deployment name → Deployment spec |
| Secrets | LWW-Map | Secret path → Encrypted value |
| IP Allocations | OR-Set | Set of (IP, container ID) |

## State Transitions

### Container Lifecycle

```
pending ──► running ──► healthy ◄──► unhealthy
                │                        │
                ▼                        ▼
            stopped ◄─────────────── failed
```

| State | Description | Transitions To |
|-------|-------------|----------------|
| pending | Created, waiting for scheduling | running, failed |
| running | Container started, health unknown | healthy, unhealthy, stopped, failed |
| healthy | Health check passing | unhealthy, stopped |
| unhealthy | Health check failing | healthy (recovery), failed (max retries) |
| stopped | Gracefully stopped | (terminal) |
| failed | Crashed or unrecoverable | (terminal, triggers reschedule) |

### Node Lifecycle

```
joining ──► alive ◄──► suspicious ──► dead
              │                         ▲
              └──── left ───────────────┘
```

| State | Description | Transitions To |
|-------|-------------|----------------|
| joining | Connecting to cluster | alive, failed |
| alive | Healthy, responding to probes | suspicious, left |
| suspicious | Missed probes, may be failing | alive (refuted), dead |
| dead | Confirmed failed | (removed from cluster) |
| left | Gracefully departed | (removed from cluster) |

## Consistency Guarantees

Fizz uses **eventual consistency**. Here's what that means in practice:

### Propagation Time

- State changes propagate to all nodes within **1-5 seconds** (typical)
- During high load or network issues, may take longer
- Anti-entropy sync ensures convergence even if gossip messages lost

### What Happens During Network Partition

```
Partition: Nodes A,B isolated from C,D,E

1. Both sides continue operating independently
2. A,B see C,D,E as suspicious → dead
3. C,D,E see A,B as suspicious → dead
4. Both sides may reschedule "lost" containers
5. When partition heals:
   - Membership merges (all nodes alive again)
   - CRDT state merges automatically
   - Duplicate containers detected and removed
   - System converges to correct state
```

### Guarantees Provided

- **Availability**: Nodes operate independently during partitions
- **Convergence**: All nodes eventually see the same state
- **Crdt Merge**: Concurrent updates never lost (merged deterministically)

### Guarantees NOT Provided

- **Immediate consistency**: Changes not instant across cluster
- **Exactly-once execution**: Container may briefly run on multiple nodes during partition
- **Atomic transactions**: No multi-key atomic updates

### Safe Patterns

- Stateless services (safe to run duplicates briefly)
- Idempotent operations
- Services that can handle duplicate requests

### Patterns Requiring Care

- Stateful services with exclusive access requirements
- Services that can't tolerate brief duplication
- Strict ordering requirements

## Network Architecture

### Single Node

Uses Docker's native bridge networking. No overlay required.

### Multi-Node Cluster

```
    Node A                          Node B
┌─────────────────┐            ┌─────────────────┐
│  Container 1    │            │  Container 2    │
│  10.100.0.2     │            │  10.100.0.3     │
└────────┬────────┘            └────────┬────────┘
         │                              │
    ┌────▼────┐                    ┌────▼────┐
    │  veth   │                    │  veth   │
    └────┬────┘                    └────┬────┘
         │                              │
    ┌────▼────────────────────────────▼────┐
    │           WireGuard Mesh              │
    │   Node A ◄────encrypted────► Node B   │
    └────┬────────────────────────────┬────┘
         │                              │
    Physical Network (192.168.1.0/24)
```

### Service Discovery

Embedded DNS server on each node:
- Containers configured to use node's DNS
- Service name resolves to container IPs
- Round-robin across healthy replicas

## Security Model

### Node-to-Node

- All cluster traffic over WireGuard (encrypted)
- Nodes authenticate via cluster secret key
- New nodes must know secret to join

### Secrets

- Encrypted at rest with Age
- Master key split via Shamir (3-of-5)
- Secrets mounted as tmpfs (never on disk in container)
- Scoped to deployment or container

### API

- Optional TLS for REST API
- Token-based authentication
- Future: RBAC for multi-tenant

## Configuration

See [example config](../examples/config.yaml) for full reference.

Key configuration areas:
- Node identity and labels
- Cluster membership (SWIM parameters)
- Network driver selection
- Runtime selection
- API binding and TLS
- Logging level and format

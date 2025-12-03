# Glossary

Quick reference for terms used in Fizz documentation.

---

## A

**ADR (Architecture Decision Record)**
A document capturing a significant architectural decision, including context, alternatives considered, and consequences.

**Age**
A modern file encryption tool using X25519 and ChaCha20-Poly1305. Fizz uses Age for encrypting secrets at rest. See [age-encryption.org](https://age-encryption.org/).

**Anti-entropy**
Periodic full-state synchronization between nodes to catch any updates missed by gossip. Ensures eventual consistency.

**Affinity**
A scheduling constraint that attracts containers to specific nodes or to other containers. Opposite of anti-affinity.

---

## C

**CAP Theorem**
States that a distributed system can only guarantee two of three properties: Consistency, Availability, and Partition tolerance. Fizz chooses AP (availability + partition tolerance).

**Compose file**
A YAML file (typically `docker-compose.yml`) defining services, networks, and volumes. See [compose-spec.io](https://www.compose-spec.io/).

**Consistent hashing**
A technique for distributing keys across nodes such that adding/removing a node only remaps a small fraction of keys. Used by Fizz's scheduler.

**Container**
A running instance of a service. Managed by a container runtime like Docker.

**CRDT (Conflict-free Replicated Data Type)**
A data structure that can be replicated across nodes and merged without coordination. Guarantees eventual consistency. Types include G-Counter, OR-Set, LWW-Register.

---

## D

**Deployment**
A compose file that has been deployed to the cluster. Contains services, networks, volumes, and secrets.

---

## F

**Fanout**
The number of peers a node sends gossip messages to in each round. Higher fanout = faster propagation but more traffic.

**Federation**
Connecting multiple Fizz clusters so they can share services and route traffic between each other.

---

## G

**G-Counter (Grow-only Counter)**
A CRDT counter that can only increase. Each node maintains its own count; merge takes the max per node. See [CRDT](#c).

**Gossip protocol**
A protocol where nodes periodically share information with random peers. Information spreads epidemically through the cluster.

---

## H

**Health check**
A command or HTTP request that tests if a container is healthy. Fizz monitors health and restarts unhealthy containers.

---

## I

**Incarnation number**
A monotonically increasing counter used in SWIM to distinguish between old and new information about a node.

**Ingress**
Traffic entering the cluster from outside. Fizz's ingress routing allows any node to accept traffic for any service.

**IPAM (IP Address Management)**
The system for allocating IP addresses to containers. Fizz uses a CRDT-based distributed IPAM.

---

## L

**LWW-Register (Last-Writer-Wins Register)**
A CRDT that stores a single value with a timestamp. On merge, the value with the highest timestamp wins.

**LWW-Map**
A map where each key is an LWW-Register. Supports concurrent updates to different keys.

---

## M

**Membership**
The set of nodes currently in the cluster. Managed by the SWIM protocol.

**mTLS (Mutual TLS)**
TLS where both client and server authenticate each other with certificates.

---

## N

**Node**
A machine running the Fizz binary. Identified by a unique ID and network address.

---

## O

**OR-Set (Observed-Remove Set)**
A CRDT set that supports both add and remove operations. Each add is tagged with a unique ID; remove only removes observed tags.

**Overlay network**
A virtual network built on top of the physical network. Allows containers on different hosts to communicate as if on the same LAN.

---

## P

**Peer**
Another node in the cluster. Nodes communicate peer-to-peer without a central server.

**Probe**
A message sent to check if a node is alive. Part of the SWIM protocol.

---

## R

**Reconciliation**
The process of comparing desired state with actual state and taking actions to converge them.

**Replica**
One instance of a service. A service with `replicas: 3` has three replicas.

---

## S

**Scheduler**
The component that decides which node should run each container.

**Service**
A logical unit defined in a compose file. Has an image, replica count, and configuration. Containers are instances of services.

**Shamir's Secret Sharing**
A cryptographic technique to split a secret into N shares where any M shares can reconstruct the secret. Fizz uses 3-of-5 for the master encryption key.

**Suspicion**
In SWIM, a state between alive and dead. A node is marked suspicious when it fails to respond, giving it time to refute before being declared dead.

**SWIM (Scalable Weakly-consistent Infection-style Membership)**
A protocol for cluster membership and failure detection with O(1) message overhead per node. See [SWIM paper](https://www.cs.cornell.edu/projects/Quicksilver/public_pdfs/SWIM.pdf).

---

## V

**Virtual node**
In consistent hashing, each physical node is represented by multiple points on the hash ring. Improves load distribution.

**VTEP (VXLAN Tunnel Endpoint)**
The component that encapsulates/decapsulates VXLAN traffic. Each node runs a VTEP.

**VXLAN (Virtual Extensible LAN)**
An overlay network technology that encapsulates L2 frames in UDP. Standard used by Docker Swarm.

---

## W

**WireGuard**
A modern VPN protocol. Fizz uses WireGuard for encrypted node-to-node communication. See [wireguard.com](https://www.wireguard.com/).

---

## X

**x-fizz**
Extension fields in compose files for Fizz-specific configuration. Ignored by Docker Compose.

```yaml
services:
  web:
    x-fizz:
      placement:
        constraints:
          - node.labels.zone == us-east
```

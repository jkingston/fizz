# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for Fizz.

## What is an ADR?

An ADR captures a significant architectural decision along with its context and consequences. ADRs help future contributors understand why decisions were made.

## ADR Index

| # | Title | Status |
|---|-------|--------|
| [0001](0001-use-zig.md) | Use Zig as Implementation Language | Accepted |
| [0002](0002-leaderless-swim.md) | Leaderless Architecture with SWIM Protocol | Accepted |
| [0003](0003-state-crdts.md) | Use CRDTs for Distributed State | Accepted |
| [0004](0004-compose-compat.md) | Docker Compose Compatibility | Accepted |
| [0005](0005-wireguard-overlay.md) | WireGuard for Overlay Networking | Accepted |
| [0006](0006-age-secrets.md) | Age Encryption with Shamir Secret Sharing | Accepted |
| [0007](0007-libyaml-ffi.md) | Use libyaml via FFI for YAML Parsing | Accepted |
| [0008](0008-deterministic-simulation.md) | Deterministic Simulation Testing | Accepted |

## Creating a New ADR

1. Copy the template below
2. Number sequentially (0007, 0008, etc.)
3. Fill in all sections
4. Submit for review

## Template

```markdown
# ADR NNNN: Title

## Status

Proposed | Accepted | Deprecated | Superseded by [NNNN](NNNN-title.md)

## Context

What is the situation? What forces are at play?

## Decision

What is the decision that was made?

## Rationale

Why was this decision made? What alternatives were considered?

## Consequences

What are the positive and negative outcomes of this decision?
```

## References

- [ADR GitHub Organization](https://adr.github.io/)
- [Michael Nygard's ADR article](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions)

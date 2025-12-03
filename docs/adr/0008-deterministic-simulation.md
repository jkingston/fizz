# ADR 0008: Deterministic Simulation Testing

## Status

Accepted

## Context

Fizz is a distributed system where bugs often manifest under specific timing, network conditions, or failure scenarios. Traditional testing approaches have limitations:

- **Unit tests**: Don't catch integration issues or race conditions
- **Integration tests**: Slow, flaky, hard to reproduce failures
- **Manual testing**: Can't explore edge cases systematically

FoundationDB and TigerBeetle have demonstrated that deterministic simulation testing catches bugs that other approaches miss.

## Decision

Build Fizz with deterministic simulation testing from day one.

## Rationale

1. **Reproducibility**: Any bug can be reproduced with a seed
2. **Coverage**: Test years of operation in seconds
3. **Failure injection**: Simulate network partitions, slow disks, clock skew
4. **Fast feedback**: No real I/O means fast test execution
5. **Confidence**: Comprehensive testing enables aggressive refactoring

## Architecture

Core logic uses injected interfaces instead of direct system calls:

```
Abstractions:
├── Time        # Controllable clock, no real time in core logic
├── Random      # Seeded PRNG for reproducible randomness
├── Network     # Simulated network with partition/delay injection
├── Filesystem  # In-memory or controlled I/O
└── Runtime     # Stub container runtime for testing
```

**Production:** Real implementations (system clock, real network, Docker)
**Testing:** Simulated implementations (controllable clock, fake network, stub runtime)

## Consequences

**Positive:**
- Catch race conditions and edge cases early
- Reproduce any bug with a seed
- Fast test execution (no real I/O)
- Test failure scenarios impossible to create manually
- High confidence in correctness

**Negative:**
- Upfront investment in test infrastructure
- All core code must use abstractions (no direct syscalls)
- Simulation may not catch all real-world issues (e.g., actual Docker bugs)

**Mitigations:**
- Build abstractions incrementally alongside features
- Complement simulation with targeted integration tests against real Docker
- Property-based tests with random seeds for broad coverage

# ADR 0001: Use Zig as Implementation Language

## Status

Accepted

## Context

Fizz needs to be distributed as a single binary with minimal dependencies. It will perform systems-level work including networking, process management, and interfacing with container runtimes. Performance matters for the hot path (gossip, health checks).

Options considered:
- **Go**: Good networking stdlib, garbage collector causes latency spikes, larger binaries
- **Rust**: Excellent safety, steep learning curve, complex ownership for concurrent code
- **C**: Maximum control, no safety guarantees, high bug risk
- **Zig**: C-level performance, explicit memory, good safety, simple C interop

## Decision

Use Zig as the implementation language.

## Rationale

1. **Single binary distribution**: Zig produces static binaries with no runtime dependencies. Cross-compilation is first-class.

2. **C interoperability**: Fizz needs to call C libraries (libyaml, SQLite, potentially WireGuard userspace). Zig can call C directly without FFI overhead.

3. **Explicit memory management**: No garbage collector means predictable latency. Important for distributed protocol timing.

4. **Safety without complexity**: Zig catches many bugs at compile time without Rust's borrow checker complexity.

5. **Performance**: Comparable to C for systems code. No hidden allocations or control flow.

## Consequences

**Positive:**
- Small, self-contained binaries
- Predictable performance
- Easy integration with C ecosystem
- Growing community and tooling

**Negative:**
- Smaller ecosystem than Go/Rust
- Fewer developers familiar with Zig
- Language still evolving (not yet 1.0)
- Some libraries may need to be written from scratch

**Mitigations:**
- Leverage C libraries where mature options exist
- Document Zig patterns for contributors
- Pin Zig version for reproducibility

# ADR 0007: Use libyaml via FFI for YAML Parsing

## Status

Accepted

## Context

Fizz needs to parse Docker Compose YAML files which can be complex (anchors, aliases, multi-document, various scalar styles). Options considered:

- **Pure Zig parser**: Full control, no dependencies, but significant work and risk of edge-case bugs
- **C libyaml FFI**: Battle-tested library used by many projects, full YAML 1.1 support
- **Subset parser**: Only parse what Compose needs, but may hit unexpected edge cases

## Decision

Use libyaml via Zig's C FFI.

## Rationale

1. **Proven**: libyaml is used by PyYAML, Ruby's Psych, and many other projects
2. **Complete**: Full YAML 1.1 specification support
3. **Compose files are complex**: Real-world compose files use anchors, aliases, and edge cases
4. **Lower risk**: Avoid bugs from implementing a parser from scratch
5. **Zig FFI is straightforward**: Zig's C interop is zero-cost and well-documented

## Consequences

**Positive:**
- Robust YAML parsing from day one
- Focus effort on orchestration, not parsing
- Benefit from upstream fixes

**Negative:**
- C dependency (libyaml must be installed or vendored)
- Slightly larger binary
- Must handle C memory management carefully

**Mitigations:**
- Vendor libyaml source for reproducible builds
- Wrap in safe Zig API that handles allocation/deallocation

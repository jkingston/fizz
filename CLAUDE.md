# Fizz - Claude Code Context

This file provides context for Claude Code when working on the Fizz orchestrator.

## Project Overview

Fizz is a lightweight, leaderless container orchestrator written in Zig. It aims to be simpler than Kubernetes while providing cluster-wide deployment, automatic failover, and seamless networking.

**Status:** Pre-alpha / Design phase. No working code yet.

## Key Design Decisions

| Decision | Choice | ADR |
|----------|--------|-----|
| Language | Zig | [0001](docs/adr/0001-use-zig.md) |
| Architecture | Leaderless with SWIM protocol | [0002](docs/adr/0002-leaderless-swim.md) |
| State | CRDTs for distributed state | [0003](docs/adr/0003-state-crdts.md) |
| User Interface | Docker Compose compatible | [0004](docs/adr/0004-compose-compat.md) |
| Networking | WireGuard overlay | [0005](docs/adr/0005-wireguard-overlay.md) |
| Secrets | Age encryption + Shamir sharing | [0006](docs/adr/0006-age-secrets.md) |
| YAML Parsing | C libyaml via FFI | [0007](docs/adr/0007-libyaml-ffi.md) |
| Testing | Deterministic simulation | [0008](docs/adr/0008-deterministic-simulation.md) |

## Architecture Principles

1. **Interfaces over implementations** - Core logic uses injected interfaces (Time, Random, Network, Runtime) to enable deterministic simulation testing
2. **No leader** - All nodes are equal peers using gossip protocol
3. **Eventual consistency** - CRDTs merge without coordination
4. **Compose compatibility** - Standard compose files work; `x-fizz` extensions for cluster features

## Directory Structure (Planned)

```
fizz/
├── src/
│   ├── main.zig           # Entry point
│   ├── cli/               # Command handlers
│   ├── compose/           # YAML parsing
│   ├── runtime/           # Docker/Podman abstraction
│   ├── orchestrator/      # Core scheduling logic
│   ├── sim/               # Simulation testing infrastructure
│   └── log/               # Structured logging
├── tests/
│   ├── unit/
│   └── simulation/
├── examples/
│   ├── config.yaml
│   ├── simple-compose.yml
│   └── wordpress-compose.yml
└── docs/
```

## Implementation Milestones

| Milestone | Description | Status |
|-----------|-------------|--------|
| M0 | Project bootstrap, CLI skeleton | Not started |
| M1 | Compose parsing with libyaml | Not started |
| M2 | **MVP**: Single-node orchestration | Not started |
| M3+ | Clustering, networking, secrets | Future |

**MVP Exit Criteria:**
```bash
fizz up -f examples/wordpress-compose.yml
curl http://localhost:8080  # WordPress responds
fizz down
```

## Coding Conventions

### Zig Style Guide

**Reference:** [Zig: Zero to Hero](https://github.com/jkingston/zig_guide) — Use this as the authoritative coding and style reference for all Zig code in this project.

#### Naming Conventions
| Element | Convention | Example |
|---------|------------|---------|
| Types (struct, enum, union) | PascalCase | `const Point = struct { ... }` |
| Functions returning values | camelCase | `fn calculateSum(a: i32, b: i32) i32` |
| Functions returning types | PascalCase | `fn ArrayList(comptime T: type) type` |
| Variables, parameters, constants | snake_case | `const max_connections = 100` |
| File names | snake_case | `compose_parser.zig` |
| Units in identifiers | Suffix with unit | `latency_ms_max`, `buffer_size_bytes` |
| Acronyms | Fully capitalized | `VSRState`, `CRDTMerge` |

#### Error Handling
- Use error unions (`!T`) for operations that can fail
- Use optionals (`?T`) when absence is valid/expected (not an error)
- Propagate errors with `try`, provide fallbacks with `catch`
- Handle optionals with `orelse` or `if (value) |v|` unwrapping

#### Resource Management
- Pair resource acquisition with immediate `defer` cleanup
- Use `errdefer` for partial-failure rollback
- Remember: defers execute in LIFO order
- Use nested blocks in loops to avoid defer accumulation

#### Module Organization
- Use `pub` explicitly for public API
- Prefer explicit re-exports over implicit patterns
- For large modules, use the module-as-directory pattern with a single entry point

#### Anti-Patterns to Avoid
- `defer` inside loops without nested blocks
- Optionals for error states (use error unions instead)
- Unmarked `comptime` parameters
- Implicit re-exports

### Testing
- All core logic must be testable via simulation (no direct syscalls)
- Use seeded randomness for reproducibility
- Property-based tests where applicable

### Documentation
- ADRs for significant decisions
- Code comments for non-obvious logic only
- Keep README focused on users, ARCHITECTURE.md for contributors

## Key Documentation

| Document | Purpose |
|----------|---------|
| [README.md](README.md) | User-facing overview |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System design |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Implementation milestones |
| [docs/CONTEXT.md](docs/CONTEXT.md) | Background research |
| [docs/GLOSSARY.md](docs/GLOSSARY.md) | Term definitions |
| [docs/adr/](docs/adr/) | Architecture decisions |

## Common Tasks

### Adding a new CLI command
1. Create handler in `src/cli/`
2. Register in `src/cli/root.zig`
3. Add tests with stub runtime

### Adding a new ADR
1. Copy template from `docs/adr/README.md`
2. Number sequentially (0009, 0010, etc.)
3. Update index in `docs/adr/README.md`

### Running tests
```bash
zig build test              # Unit tests
zig build test-simulation   # Simulation tests (planned)
```

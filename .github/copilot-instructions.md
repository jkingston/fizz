# Fizz Code Review Guidelines

Fizz is a leaderless container orchestrator written in Zig. Apply these standards when reviewing pull requests.

## References

- Zig conventions: [Zig: Zero to Hero](https://github.com/jkingston/zig_guide)
- Zig std library: https://ziglang.org/documentation/master/std/
- Architecture decisions: `docs/adr/`
- Project conventions: `CLAUDE.md`

---

## Zig Naming Conventions

- Types (struct, enum, union): PascalCase
- Functions returning values: camelCase
- Functions returning types: PascalCase
- Variables, parameters, constants: snake_case
- File names: snake_case
- Units in identifiers: suffix with unit (timeout_ms, buffer_size_bytes)
- Acronyms: fully capitalized (CRDTState, VSRState)

---

## Error Handling

- Use error unions (`!T`) for operations that can fail
- Use optionals (`?T`) when absence is valid (not an error)
- Propagate errors with `try`
- Provide fallbacks with `catch`
- Handle optionals with `orelse` or `if (value) |v|` unwrapping

---

## Resource Management

- Pair resource acquisition with immediate `defer` cleanup
- Use `errdefer` for partial-failure rollback
- Never use `defer` inside loops without nested blocks
- Remember: defers execute in LIFO order

---

## Architecture (per ADRs)

- Core logic must use injected interfaces (Time, Random, Network, Runtime) for simulation testing (ADR-0008)
- No direct syscalls in core orchestration code
- Use CRDT patterns for distributed state (ADR-0003)
- Maintain Docker Compose compatibility (ADR-0004)

---

## Testing

- New code must have corresponding tests
- Tests must be deterministic (use seeded randomness)
- Core logic must be simulation-testable (uses interfaces, not direct syscalls)
- Cover edge cases and error paths

---

## Documentation

- Significant architectural decisions require an ADR in `docs/adr/`
- Update `CLAUDE.md` if conventions change
- Update `README.md` for user-facing changes
- Add code comments only for non-obvious logic

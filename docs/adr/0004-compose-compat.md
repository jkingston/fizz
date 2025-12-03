# ADR 0004: Docker Compose Compatibility

## Status

Accepted

## Context

Users already have docker-compose.yml files. Requiring a new format would create adoption friction. However, Compose doesn't have all the fields we need for cluster orchestration.

Options considered:
- **New format**: Full control, but adoption barrier
- **Compose compatible**: Familiar, but constrained by spec
- **Kubernetes manifests**: Standard, but complex and different from Compose
- **Compose + extensions**: Best of both worlds

## Decision

Support standard Docker Compose files with Fizz-specific extensions via `x-fizz` blocks and labels.

## Rationale

1. **Familiar format**: Users don't need to learn a new syntax.

2. **Existing files work**: Basic compose files work without modification.

3. **Extension mechanism exists**: Compose spec explicitly supports `x-*` fields for extensions.

4. **Gradual enhancement**: Start with basic compose, add `x-fizz` for advanced features.

## Extension Pattern

```yaml
services:
  web:
    image: nginx
    deploy:
      replicas: 3

    # Fizz extensions in x-fizz block
    x-fizz:
      placement:
        constraints:
          - node.labels.zone == us-east
      scaling:
        min: 2
        max: 10

# Top-level cluster configuration
x-fizz:
  cluster:
    name: production
  networking:
    driver: wireguard
```

## Implementation

- Parse with libyaml (C library)
- Map standard fields to Fizz concepts
- Extract and validate `x-fizz` blocks
- Ignore unknown `x-*` fields (forward compatibility)

## Consequences

**Positive:**
- Low adoption barrier
- Existing compose files work
- Extension mechanism is standard
- Can evolve independently of Compose spec

**Negative:**
- Bound by Compose structure for core concepts
- Some Compose features may not map well to Fizz
- Need to track Compose spec changes

**Mitigations:**
- Document which Compose features are supported
- Validate and warn on unsupported features
- Design extensions thoughtfully for longevity

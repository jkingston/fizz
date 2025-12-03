# Fizz

A lightweight, leaderless container orchestrator with Docker Compose compatibility.

## Status

**Pre-alpha** - Design phase. Not yet functional.

## Current State

Fizz is in **design phase**. No working software exists yet.

- **Can I use Fizz today?** No
- **What should I use now?** Docker Compose (single node) or Nomad (cluster)

**Good fit (future):** 5-100 node clusters, Compose-familiar teams, encryption by default

**Not suitable:** Single machine only, enterprise scale, strong consistency requirements

## What is Fizz?

Fizz is a container orchestrator that aims to be simpler than Kubernetes while providing cluster-wide deployment, automatic failover, and seamless networking. Think of it as Docker Compose that scales across multiple machines.

**Key characteristics:**

- **Single binary** - One executable, minimal dependencies
- **Leaderless** - No control plane; all nodes are equal peers
- **Compose compatible** - Use your existing docker-compose.yml files
- **Secure by default** - Encrypted node communication, encrypted secrets

## Goals

- Run Docker Compose files across a cluster of machines
- Automatic service recovery when nodes fail
- Seamless networking between containers on different hosts
- Built-in secrets management that just works
- Federation across datacenters (eventually)

## Non-Goals

- Replace Kubernetes for large-scale enterprise deployments
- Support every orchestration feature imaginable
- Manage non-container workloads

## Documentation

| I want to... | Start here |
|--------------|------------|
| Understand the design | [Architecture](docs/ARCHITECTURE.md) |
| See what's planned | [Roadmap](docs/ROADMAP.md) |
| Understand decisions | [ADRs](docs/adr/) |
| Learn background concepts | [Context](docs/CONTEXT.md) |
| Look up a term | [Glossary](docs/GLOSSARY.md) |

See also: [Example configuration](examples/config.yaml)

## Planned CLI

```bash
# Deploy a compose file
fizz up -f docker-compose.yml

# Check status
fizz ps
fizz nodes

# Join a cluster
fizz join 192.168.1.10:7946

# Manage secrets
fizz secret create db-password
```

## License

TBD

## Contributing

Not yet accepting contributions. Design is still in flux.

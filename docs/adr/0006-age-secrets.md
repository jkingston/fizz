# ADR 0006: Age Encryption with Shamir Secret Sharing

## Status

Accepted

## Context

Fizz needs to manage secrets (passwords, API keys, certificates). Secrets must be encrypted at rest and distributed securely. Users should be able to commit encrypted secrets to git (GitOps).

Options considered:
- **Vault**: Powerful, but external dependency and complex
- **SOPS + GPG**: Established, but GPG is complex
- **SOPS + Age**: Simple modern encryption
- **Age + Shamir**: Distributed trust, no external service

## Decision

Use Age for encryption with Shamir's Secret Sharing for the master key.

## Rationale

1. **Age is simple**: One command, one key format, no configuration. Modern replacement for GPG.

2. **No external service**: Unlike Vault, no separate service to operate.

3. **Shamir distributes trust**: Master key split across nodes. No single node can decrypt all secrets.

4. **GitOps friendly**: Encrypted secrets can be committed to version control.

5. **Scoped secrets**: Secrets scoped to cluster, deployment, or container.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   Master Key                         │
│   Split via Shamir's Secret Sharing (3-of-5)        │
└─────────────────────────────────────────────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        ▼                 ▼                 ▼
    ┌───────┐         ┌───────┐         ┌───────┐
    │Share 1│         │Share 2│         │Share 3│  ...
    │Node A │         │Node B │         │Node C │
    └───────┘         └───────┘         └───────┘

Secret encryption:
┌──────────────────────────────────────────────────┐
│  secret_key = derive(master_key, secret_path)    │
│  encrypted = age.encrypt(secret_key, plaintext)  │
└──────────────────────────────────────────────────┘
```

## Secret Lifecycle

1. **Create**: User runs `fizz secret create name`, enters value
2. **Encrypt**: Value encrypted with derived key
3. **Store**: Encrypted value stored in cluster state (CRDT)
4. **Inject**: At container start, decrypt and mount as tmpfs

## Consequences

**Positive:**
- Simple encryption (Age)
- No external dependencies
- Distributed trust (Shamir)
- GitOps compatible
- Secrets never on disk in containers (tmpfs)

**Negative:**
- Need 3 of 5 nodes to reconstruct master key
- Key rotation requires coordination
- No dynamic secrets (like Vault)

**Mitigations:**
- Bootstrap process ensures enough nodes have shares
- Document key rotation procedure
- Consider Vault integration as optional backend later

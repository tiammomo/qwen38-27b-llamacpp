# Qwen3.8 local runtime agent contract

This repository owns the active local inference service on this host. The retired
`/home/tiammomo/projects/infra/local-inference-stack` checkout is not a deployment or configuration source;
do not reinstall its user units or restart its old runtime unless the user explicitly reverses that decision.

## Read first

Before changing runtime state, read `README.md`, `docs/CONFIGURATION.md`, `docs/OPERATIONS.md`, `.env.example`,
and `compose.yaml`. Treat `.env` as sensitive: do not print it, commit it, or copy its API key into commands,
logs, documentation, or process arguments.

## Runtime invariants

- Primary endpoint: `127.0.0.1:18080`; keep it loopback-bound by default.
- Model alias: `qwen3.8-27b-ud-iq3-xxs`.
- Default host profile: RTX 5070 Ti 16GB, 128K context, one slot, Q4 K/V cache, all layers on GPU.
- Text only: keep `--no-mmproj` unless multimodal memory and security are reviewed separately.
- Model and image identities remain immutable and SHA-256 pinned.
- Do not increase context or parallelism without measuring VRAM, latency, quality, and stability.

## Required workflow

For source/configuration changes, run:

```bash
./scripts/check.sh
./scripts/preflight.sh
```

For an approved runtime/configuration change, use the public scripts rather than ad hoc container commands:

```bash
./scripts/start.sh
./scripts/smoke-test.sh
./scripts/status.sh
```

`start.sh` performs model verification and waits for health. A successful smoke test is required before
declaring a runtime change complete. Use `./scripts/stop.sh` for the documented destructive lifecycle boundary;
it preserves the model, cache, image, and `.env`.

## Repository hygiene

- Never commit `.env`, GGUF files, partial downloads, cache contents, logs, or credentials.
- Update model repository, revision, filename, exact byte size, SHA-256, served ID, documentation, and test
  expectations together.
- Preserve the loopback binding and container hardening. Non-loopback service requires API authentication plus
  a separate TLS, reverse-proxy, firewall, and rate-limit review.
- Keep the baseline and implementation commits reviewable; do not rewrite history or delete user changes.

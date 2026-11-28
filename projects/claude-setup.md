# claude-setup

This repository's own `CLAUDE.md` is the global one that every machine installs, so the outerpale-startup hook never copies this file in. Only JiT reads it, for the `JiT:` line.

# Commands

- Test: `tests/test.sh`. `tests/test.sh --vm` also runs `cloud/setup.sh` in a fresh Ubuntu 24.04 container (needs Docker).

JiT: invariants tests/hook-contract.sh; vm-paths cloud/, install.sh

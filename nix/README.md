# nix support

For comprehensive provisioning and deployment instructions, see:

- **[provisioning.md](../doc/dev/deployment/provisioning.md)** - Full guide for setting up new servers
- **[deployment.md](../doc/dev/deployment/deployment.md)** - Quick reference for deploying to existing servers
- **[local-vm.md](../doc/dev/deployment/local-vm.md)** - Running jl4-demo VM locally for testing

## Quick Reference

### Available Flake Targets

| Target         | Domain                 | Environment             |
| -------------- | ---------------------- | ----------------------- |
| `jl4-demo`     | `jl4.well-typed.com`   | Local VM / Hetzner demo |
| `jl4-aws-2505` | `jl4.legalese.com`     | Beta AWS EC2 (unstable) |
| `jl4-dev`      | `dev.jl4.legalese.com` | Dev/staging AWS EC2     |

**Note:** `jl4-demo` can be run as a local QEMU VM for testing. See **[local-vm.md](../doc/dev/deployment/local-vm.md)** for details.

### Redeploying to Existing Server

```sh
# Remote deployment, from a Linux machine with enough memory (lhs)
nixos-rebuild switch --flake .#jl4-dev --target-host root@dev.jl4.legalese.com

# The beta runs the unstable branch
nixos-rebuild switch --flake github:legalese/l4-ide/unstable#jl4-aws-2505 \
  --target-host root@jl4.legalese.com
```

Do not run `nixos-rebuild` on the servers themselves.
Both are t3a.small (2 GiB), which cannot build the closure: on 2026-07-27 a build on `dev.jl4.legalese.com` made it stop answering ssh and https until the instance was rebooted.

`jl4.legalese.com` was production until the AWS deployment on the US west coast replaced it in October 2026.
Its role is now a beta deployed from `unstable`; after a deploy from this config, `nixos-version --configuration-revision` on the box names the commit it was deployed from.

### Provisioning a New Server

**For AWS EC2:**

```sh
# 1. Launch Ubuntu EC2 instance
# 2. Configure DNS: dev.jl4.legalese.com → [EC2 IP]
# 3. Enable root SSH on the Ubuntu instance
# 4. Run nixos-anywhere from your local machine:

nixos-anywhere --flake .#jl4-dev root@dev.jl4.legalese.com
```

See **[provisioning.md](../doc/dev/deployment/provisioning.md)** for detailed step-by-step instructions.

### State to Transfer When Migrating Servers

- `/var/lib/acme/` - Let's Encrypt certificates
- `/var/lib/private/jl4-websessions/` - SQLite database with saved sessions

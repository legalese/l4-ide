# Working in a cloud session (claude.ai/code)

> **Status — moved from `CLAUDE.md` §2.2 on 2026-10-27; the environment facts were measured by hand on 2026-09-24 and not since.**
> What is installed where in a default cloud environment, and what is on the agent's PATH, are measurements from 2026-09-24.
> What this repository says (`package.json`, `.npmrc`, `.nvmrc`, the workflow pins, `AGENTS.md`) was re-checked against the tree on 2026-10-27.
> The setup script below was tested by hand and has never been run as an environment setup script.

A cloud session gets one fresh clone at `/home/user/l4-ide`, checked out on whatever branch the session was pointed at.
Treat `/home/user/l4-ide` as the reference checkout and add worktrees beside it, for example:

```
git -C /home/user/l4-ide worktree add -b <branch> /home/user/l4wt/<name> origin/unstable
```

The clone is **shallow**, so `git log -S` and `git blame` answer from a truncated history.
A pickaxe that finds only a merge commit is reporting the depth limit, not the origin of the change.

## The toolchain is installed but not reachable

Measured 2026-09-24 in a default cloud environment:

| tool           | installed at            | on the agent's PATH?                                    |
| -------------- | ----------------------- | ------------------------------------------------------- |
| GHC 9.10.2     | `~/.ghcup/bin`          | **no** — `ghc: command not found`                       |
| cabal 3.16.1.0 | `~/.ghcup/bin`          | **no**                                                  |
| Node           | `/opt/node22/bin` (v22) | yes, and it is the **wrong** one                        |
| nvm            | `/opt/nvm`              | loaded by `~/.bashrc`, which agent shells do not source |

Node 22 fails `npm ci` outright with `EBADENGINE`: `package.json` requires `>=24` (`package.json:31`) and `.npmrc` sets `engine-strict=true`.
`nvm install 24` succeeds and sets the default alias, **and the next shell is still on 22**, because `/opt/node22/bin` is hard-coded in PATH and nothing loads nvm.
`/root/.local/bin` is first on PATH, so linking into it is what works.
Put this in the environment's setup script:

```bash
source /opt/nvm/nvm.sh
nvm install 24
N="$(dirname "$(nvm which 24)")"
for b in node npm npx corepack; do ln -sf "$N/$b" /root/.local/bin/$b; done
for b in ghc ghc-pkg ghci cabal; do ln -sf /root/.ghcup/bin/$b /root/.local/bin/$b; done
```

With that, `npm ci` completes and `npm run format:check` passes (measured 2026-09-24).
Two things it does not fix:

- The cabal store starts **empty**, so the first build is a cold one unless the setup script pre-builds dependencies.
  Whether a built store is cached across sessions is unmeasured.
- npm 11, which ships with Node 24, **skipped package install scripts** in that run, esbuild's among them.
  Nothing has checked that against the Vite/Svelte builds.

## What this means for the pre-commit gate

The pre-commit gate in `AGENTS.md` is `cabal test all && npm ci && npm run format` (`AGENTS.md:57`).
Neither of its first two steps can run in a default cloud session until the setup script above is in place.

Node 24 is the version to link: `package.json` requires it, `.nvmrc` says `24`, and every workflow pins `24.x`.

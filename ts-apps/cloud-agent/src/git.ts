import { execFile } from 'node:child_process'

export class GitError extends Error {
  constructor(
    message: string,
    readonly code: number | null,
    readonly stderr: string
  ) {
    super(message)
    this.name = 'GitError'
  }
}

export interface GitResult {
  stdout: string
  stderr: string
  code: number
}

/**
 * Runs `git` in the session repo with configuration the repository
 * can't override (spec §4.7, §9):
 *
 * - `core.hooksPath=/dev/null`: no hooks run, whatever `.git/hooks`
 *   holds; `core.fsmonitor=false`: no fsmonitor hook program.
 * - `core.createObject=rename` (S3 Files has no hard links),
 *   `gc.auto=0` (gc only on sleep), no GPG signing, a fixed identity.
 * - `safe.directory` for the repo (the mount's owner may differ).
 * - No system config, no terminal prompts, a minimal environment (never
 *   the harness's own, which held `AGENT_KEY`).
 */
export class Git {
  private readonly env: NodeJS.ProcessEnv

  constructor(
    readonly repoDir: string,
    baseEnv: NodeJS.ProcessEnv,
    private readonly timeoutMs = 120_000
  ) {
    const env: NodeJS.ProcessEnv = {
      GIT_CONFIG_NOSYSTEM: '1',
      GIT_TERMINAL_PROMPT: '0',
      GIT_AUTHOR_NAME: 'Legalese AI',
      GIT_AUTHOR_EMAIL: 'agent@legalese.cloud',
      GIT_COMMITTER_NAME: 'Legalese AI',
      GIT_COMMITTER_EMAIL: 'agent@legalese.cloud',
      LANG: 'C',
      LC_ALL: 'C',
    }
    for (const k of ['PATH', 'HOME', 'TMPDIR']) {
      if (baseEnv[k]) env[k] = baseEnv[k]
    }
    this.env = env
  }

  private args(args: string[]): string[] {
    return [
      '-c',
      'core.hooksPath=/dev/null',
      '-c',
      'core.fsmonitor=false',
      '-c',
      'core.createObject=rename',
      '-c',
      'gc.auto=0',
      '-c',
      'commit.gpgSign=false',
      '-c',
      'tag.gpgSign=false',
      '-c',
      `safe.directory=${this.repoDir}`,
      '-c',
      'user.name=Legalese AI',
      '-c',
      'user.email=agent@legalese.cloud',
      '-c',
      'advice.detachedHead=false',
      '-c',
      'merge.autoStash=false',
      ...args,
    ]
  }

  /** Run git; resolves with the exit code (never throws on non-zero). */
  run(
    args: string[],
    opts: { input?: string; timeoutMs?: number } = {}
  ): Promise<GitResult> {
    return new Promise((resolve, reject) => {
      const child = execFile(
        'git',
        this.args(args),
        {
          cwd: this.repoDir,
          env: this.env,
          timeout: opts.timeoutMs ?? this.timeoutMs,
          maxBuffer: 64 * 1024 * 1024,
          encoding: 'utf8',
        },
        (err, stdout, stderr) => {
          if (err && typeof (err as { code?: unknown }).code !== 'number') {
            reject(new GitError(`git ${args[0]}: ${err.message}`, null, stderr))
            return
          }
          const code = err ? ((err as { code?: number }).code ?? 1) : 0
          resolve({ stdout, stderr, code })
        }
      )
      if (opts.input !== undefined) child.stdin?.end(opts.input)
      else child.stdin?.end()
    })
  }

  /** Run git and throw {@link GitError} on a non-zero exit. */
  async ok(
    args: string[],
    opts: { input?: string; timeoutMs?: number } = {}
  ): Promise<string> {
    const r = await this.run(args, opts)
    if (r.code !== 0) {
      throw new GitError(
        `git ${args[0]} failed (${r.code}): ${r.stderr.trim().slice(0, 300)}`,
        r.code,
        r.stderr
      )
    }
    return r.stdout
  }

  /** `HEAD`'s commit id, or `null` when the repo has no commits. */
  async head(): Promise<string | null> {
    const r = await this.run(['rev-parse', '--verify', '-q', 'HEAD^{commit}'])
    return r.code === 0 ? r.stdout.trim() : null
  }
}

/** What a deploy uploads, and under which names. The zip used to be flat (the
 *  last path segment of each file) and an unreadable import was logged and
 *  skipped, so two `rates.l4` collided in the service and a missing import was
 *  discovered only when the deployed rules failed to resolve it. */
import { test, describe } from 'node:test'
import * as assert from 'node:assert/strict'
import { collectBundle } from '../deploy-bundle.js'

const decoder = new TextDecoder()

/** A project on "disk": URI to text. Anything else rejects as ENOENT. */
function disk(files: Record<string, string>) {
  const reads: string[] = []
  return {
    reads,
    readText: async (uri: string) => {
      reads.push(uri)
      if (!(uri in files)) {
        throw new Error(`ENOENT: no such file or directory, open '${uri}'`)
      }
      return files[uri]
    },
  }
}

const names = (bundle: { name: string }[]) => bundle.map((f) => f.name)

describe('entry names', () => {
  test('files in one folder keep their plain names, main first, imports in the order given', async () => {
    const fs = disk({
      'file:///work/proj/main.l4': 'main',
      'file:///work/proj/zeta.l4': 'zeta',
      'file:///work/proj/alpha.l4': 'alpha',
    })
    const bundle = await collectBundle(
      'file:///work/proj/main.l4',
      ['file:///work/proj/zeta.l4', 'file:///work/proj/alpha.l4'],
      { ...fs, rootUri: 'file:///work/proj' }
    )
    assert.deepEqual(names(bundle), ['main.l4', 'zeta.l4', 'alpha.l4'])
    assert.deepEqual(
      bundle.map((f) => decoder.decode(f.content)),
      ['main', 'zeta', 'alpha']
    )
  })

  test('a root above the files does not change the names of files that share a folder', async () => {
    const fs = disk({
      'file:///work/proj/rows/main.l4': 'main',
      'file:///work/proj/rows/lib.l4': 'lib',
    })
    const bundle = await collectBundle(
      'file:///work/proj/rows/main.l4',
      ['file:///work/proj/rows/lib.l4'],
      { ...fs, rootUri: 'file:///work' }
    )
    assert.deepEqual(names(bundle), ['main.l4', 'lib.l4'])
  })

  test('main in rows/a importing ../b/mod is a/main.l4 and b/mod.l4', async () => {
    const fs = disk({
      'file:///work/rows/a/main.l4': 'main',
      'file:///work/rows/b/mod.l4': 'mod',
    })
    const bundle = await collectBundle(
      'file:///work/rows/a/main.l4',
      ['file:///work/rows/b/mod.l4'],
      { ...fs, rootUri: 'file:///work' }
    )
    assert.deepEqual(names(bundle), ['a/main.l4', 'b/mod.l4'])
    assert.deepEqual(
      bundle.map((f) => decoder.decode(f.content)),
      ['main', 'mod']
    )
  })

  test('two modules called rates.l4 in different folders both survive, under different names', async () => {
    const fs = disk({
      'file:///work/rows/main.l4': 'main',
      'file:///work/rows/x/rates.l4': 'x rates',
      'file:///work/rows/y/rates.l4': 'y rates',
    })
    const bundle = await collectBundle(
      'file:///work/rows/main.l4',
      ['file:///work/rows/x/rates.l4', 'file:///work/rows/y/rates.l4'],
      { ...fs, rootUri: 'file:///work' }
    )
    assert.deepEqual(names(bundle), ['main.l4', 'x/rates.l4', 'y/rates.l4'])
    assert.deepEqual(
      bundle.map((f) => decoder.decode(f.content)),
      ['main', 'x rates', 'y rates']
    )
  })

  test('the same URI listed twice is collected, and read, once', async () => {
    const fs = disk({
      'file:///work/proj/main.l4': 'main',
      'file:///work/proj/lib.l4': 'lib',
    })
    const bundle = await collectBundle(
      'file:///work/proj/main.l4',
      ['file:///work/proj/lib.l4', 'file:///work/proj/lib.l4'],
      { ...fs, rootUri: 'file:///work/proj' }
    )
    assert.deepEqual(names(bundle), ['main.l4', 'lib.l4'])
    assert.deepEqual(fs.reads, [
      'file:///work/proj/main.l4',
      'file:///work/proj/lib.l4',
    ])
  })

  test('says what it collected, by entry name', async () => {
    const fs = disk({
      'file:///work/rows/a/main.l4': 'main',
      'file:///work/rows/b/mod.l4': 'mod',
    })
    const lines: string[] = []
    await collectBundle(
      'file:///work/rows/a/main.l4',
      ['file:///work/rows/b/mod.l4'],
      { ...fs, rootUri: 'file:///work', log: (l) => lines.push(l) }
    )
    assert.deepEqual(lines, ['Collected: a/main.l4', 'Collected: b/mod.l4'])
  })
})

describe('the standard library', () => {
  test('the embedded stdlib is skipped: not read, not named, not counted as outside the root', async () => {
    const fs = disk({
      'file:///work/proj/main.l4': 'main',
      'file:///work/proj/lib.l4': 'lib',
    })
    const bundle = await collectBundle(
      'file:///work/proj/main.l4',
      [
        'jl4-embedded:/prelude.l4',
        'file:///work/proj/lib.l4',
        'jl4-embedded:/daydate.l4',
      ],
      { ...fs, rootUri: 'file:///work/proj' }
    )
    assert.deepEqual(names(bundle), ['main.l4', 'lib.l4'])
    assert.ok(!fs.reads.some((u) => u.startsWith('jl4-embedded:')))
  })

  test('a stdlib import does not pull the common ancestor upwards or change any name', async () => {
    const fs = disk({
      'file:///work/rows/a/main.l4': 'main',
      'file:///work/rows/a/sub/lib.l4': 'lib',
    })
    const bundle = await collectBundle(
      'file:///work/rows/a/main.l4',
      ['jl4-embedded:/prelude.l4', 'file:///work/rows/a/sub/lib.l4'],
      { ...fs, rootUri: 'file:///work' }
    )
    assert.deepEqual(names(bundle), ['main.l4', 'sub/lib.l4'])
  })
})

describe('a file that cannot be read stops the deploy', () => {
  test('an unreadable import: the error names the file and the reason, and nothing is returned', async () => {
    const fs = disk({
      'file:///work/proj/main.l4': 'main',
      'file:///work/proj/there.l4': 'there',
    })
    await assert.rejects(
      collectBundle(
        'file:///work/proj/main.l4',
        ['file:///work/proj/there.l4', 'file:///work/proj/gone.l4'],
        { ...fs, rootUri: 'file:///work/proj' }
      ),
      (err: Error) => {
        assert.match(err.message, /could not read \/work\/proj\/gone\.l4/)
        assert.match(err.message, /ENOENT/)
        return true
      }
    )
  })

  test('an unreadable main file: the error names it, and no import is read', async () => {
    const fs = disk({ 'file:///work/proj/lib.l4': 'lib' })
    await assert.rejects(
      collectBundle('file:///work/proj/main.l4', ['file:///work/proj/lib.l4'], {
        ...fs,
        rootUri: 'file:///work/proj',
      }),
      /could not read \/work\/proj\/main\.l4: ENOENT/
    )
    assert.deepEqual(fs.reads, ['file:///work/proj/main.l4'])
  })

  test('a reader that rejects with a non-Error still gives a reason', async () => {
    await assert.rejects(
      collectBundle('file:///work/proj/main.l4', [], {
        readText: () => Promise.reject('disk on fire'),
        rootUri: 'file:///work/proj',
      }),
      /could not read \/work\/proj\/main\.l4: disk on fire/
    )
  })
})

describe('the project root', () => {
  test('an import outside the workspace folder stops the deploy and names the file and the root', async () => {
    const fs = disk({
      'file:///work/proj/main.l4': 'main',
      'file:///work/other/lib.l4': 'lib',
    })
    await assert.rejects(
      collectBundle(
        'file:///work/proj/main.l4',
        ['file:///work/other/lib.l4'],
        { ...fs, rootUri: 'file:///work/proj' }
      ),
      (err: Error) => {
        assert.match(err.message, /\/work\/other\/lib\.l4/)
        assert.match(err.message, /outside the project root \/work\/proj\./)
        return true
      }
    )
  })

  test('a sibling folder whose name merely starts with the root name is outside it', async () => {
    const fs = disk({
      'file:///work/proj/main.l4': 'main',
      'file:///work/proj2/lib.l4': 'lib',
    })
    await assert.rejects(
      collectBundle(
        'file:///work/proj/main.l4',
        ['file:///work/proj2/lib.l4'],
        { ...fs, rootUri: 'file:///work/proj' }
      ),
      /\/work\/proj2\/lib\.l4 lies outside the project root \/work\/proj\./
    )
  })

  test('a trailing slash on the root does not matter', async () => {
    const fs = disk({
      'file:///work/proj/main.l4': 'main',
      'file:///work/proj/lib.l4': 'lib',
    })
    const bundle = await collectBundle(
      'file:///work/proj/main.l4',
      ['file:///work/proj/lib.l4'],
      { ...fs, rootUri: 'file:///work/proj/' }
    )
    assert.deepEqual(names(bundle), ['main.l4', 'lib.l4'])
  })

  test('with no workspace folder, the main file directory is the root: a file below it is fine', async () => {
    const fs = disk({
      'file:///work/rows/a/main.l4': 'main',
      'file:///work/rows/a/sub/lib.l4': 'lib',
    })
    const bundle = await collectBundle(
      'file:///work/rows/a/main.l4',
      ['file:///work/rows/a/sub/lib.l4'],
      fs
    )
    assert.deepEqual(names(bundle), ['main.l4', 'sub/lib.l4'])
  })

  test('with no workspace folder, ../b/mod is outside the main file directory and says so', async () => {
    const fs = disk({
      'file:///work/rows/a/main.l4': 'main',
      'file:///work/rows/b/mod.l4': 'mod',
    })
    await assert.rejects(
      collectBundle(
        'file:///work/rows/a/main.l4',
        ['file:///work/rows/b/mod.l4'],
        fs
      ),
      /\/work\/rows\/b\/mod\.l4 lies outside the project root \/work\/rows\/a\./
    )
  })

  test('a file on another scheme or authority is outside the root', async () => {
    const fs = disk({
      'file:///work/proj/main.l4': 'main',
      'vscode-remote://ssh-remote+box/work/proj/lib.l4': 'lib',
    })
    await assert.rejects(
      collectBundle(
        'file:///work/proj/main.l4',
        ['vscode-remote://ssh-remote+box/work/proj/lib.l4'],
        { ...fs, rootUri: 'file:///work/proj' }
      ),
      /lies outside the project root/
    )
  })

  test('nothing outside the root is read', async () => {
    const fs = disk({
      'file:///work/proj/main.l4': 'main',
      'file:///work/other/lib.l4': 'lib',
    })
    await assert.rejects(
      collectBundle(
        'file:///work/proj/main.l4',
        ['file:///work/other/lib.l4'],
        { ...fs, rootUri: 'file:///work/proj' }
      )
    )
    assert.deepEqual(fs.reads, ['file:///work/proj/main.l4'])
  })

  test('a library found through JL4_LIBRARY_PATH arrives as an ordinary file and is refused, with the way out', async () => {
    const fs = disk({
      'file:///work/proj/main.l4': 'main',
      'file:///opt/jl4/libraries/prelude.l4': 'prelude',
    })
    await assert.rejects(
      collectBundle(
        'file:///work/proj/main.l4',
        ['file:///opt/jl4/libraries/prelude.l4'],
        { ...fs, rootUri: 'file:///work/proj' }
      ),
      (err: Error) => {
        // The first sentence, which names the file and the root, is unchanged.
        assert.match(
          err.message,
          /^Deploy stopped: \/opt\/jl4\/libraries\/prelude\.l4 lies outside the project root \/work\/proj\. /
        )
        assert.match(
          err.message,
          /can only include files inside the project root/
        )
        assert.match(
          err.message,
          /JL4_LIBRARY_PATH or the per-user library folder/
        )
        assert.match(err.message, /service's built-in standard library/)
        assert.match(
          err.message,
          /unset JL4_LIBRARY_PATH for the editor, or move the library into the project instead of copying it: the language server reads JL4_LIBRARY_PATH before the project, so while it is set a copy in the project is ignored\.$/
        )
        // Advice that was wrong: a copy is ignored while the variable is set.
        assert.doesNotMatch(err.message, /or copy the library into the project/)
        return true
      }
    )
    assert.deepEqual(fs.reads, ['file:///work/proj/main.l4'])
  })

  test('a main file URI with no "/" has no folder: the root is shown whole, not cut short', async () => {
    const fs = disk({
      'untitled:Untitled-1': 'main',
      'file:///work/lib.l4': 'lib',
    })
    await assert.rejects(
      collectBundle('untitled:Untitled-1', ['file:///work/lib.l4'], fs),
      (err: Error) => {
        assert.match(
          err.message,
          /\/work\/lib\.l4 lies outside the project root untitled:Untitled-1\. /
        )
        assert.doesNotMatch(err.message, /Untitled-\./)
        return true
      }
    )
  })

  test('a main file URI with no "/" is bundled under its own name', async () => {
    const fs = disk({ 'untitled:Untitled-1': 'main' })
    const bundle = await collectBundle('untitled:Untitled-1', [], fs)
    assert.deepEqual(names(bundle), ['Untitled-1'])
  })

  test('a main file in the top folder, no workspace folder: the root is "/", and it holds every file on that filesystem', async () => {
    const fs = disk({
      'file:///main.l4': 'main',
      'file:///work/lib.l4': 'lib',
    })
    const bundle = await collectBundle(
      'file:///main.l4',
      ['file:///work/lib.l4'],
      fs
    )
    assert.deepEqual(names(bundle), ['main.l4', 'work/lib.l4'])
  })

  test('a main file in the top folder, no workspace folder: a file on another authority is outside the root, shown as "/"', async () => {
    const fs = disk({
      'file:///main.l4': 'main',
      'vscode-remote://ssh-remote+box/lib.l4': 'lib',
    })
    await assert.rejects(
      collectBundle(
        'file:///main.l4',
        ['vscode-remote://ssh-remote+box/lib.l4'],
        fs
      ),
      /vscode-remote:\/\/ssh-remote\+box\/lib\.l4 lies outside the project root \/\. /
    )
  })

  test('a main file in the top folder, workspace folder "/": every file is inside, and an outsider is shown against "/"', async () => {
    const fs = disk({
      'file:///main.l4': 'main',
      'file:///work/lib.l4': 'lib',
      'vscode-remote://ssh-remote+box/lib.l4': 'remote',
    })
    const bundle = await collectBundle(
      'file:///main.l4',
      ['file:///work/lib.l4'],
      { ...fs, rootUri: 'file:///' }
    )
    assert.deepEqual(names(bundle), ['main.l4', 'work/lib.l4'])
    await assert.rejects(
      collectBundle(
        'file:///main.l4',
        ['vscode-remote://ssh-remote+box/lib.l4'],
        { ...fs, rootUri: 'file:///' }
      ),
      /lies outside the project root \/\. /
    )
  })

  test('a main file in the top folder is outside a workspace folder below it', async () => {
    const fs = disk({ 'file:///main.l4': 'main' })
    await assert.rejects(
      collectBundle('file:///main.l4', [], { ...fs, rootUri: 'file:///work' }),
      /\/main\.l4 lies outside the project root \/work\. /
    )
    assert.deepEqual(fs.reads, [])
  })

  test('a main file at the top of a Windows drive, no workspace folder: the root is shown as "c:/", not "c:"', async () => {
    const fs = disk({
      'file:///c%3A/main.l4': 'main',
      'file:///d%3A/lib.l4': 'lib',
    })
    await assert.rejects(
      collectBundle('file:///c%3A/main.l4', ['file:///d%3A/lib.l4'], fs),
      /d:\/lib\.l4 lies outside the project root c:\/\. /
    )
  })
})

describe('names that are URIs', () => {
  test('%-escapes are decoded once: a space, and a non-ASCII letter, in a folder and in a file name', async () => {
    // The main file is in the escaped folder (which is not judged: nothing looks
    // the main file up), and the import is a file with an escaped name at the
    // top of the bundle (which is not judged either).
    const fs = disk({
      'file:///work/My%20Rules/sub%20dir/main.l4': 'main',
      'file:///work/My%20Rules/caf%C3%A9.l4': 'cafe',
    })
    const bundle = await collectBundle(
      'file:///work/My%20Rules/sub%20dir/main.l4',
      ['file:///work/My%20Rules/caf%C3%A9.l4'],
      { ...fs, rootUri: 'file:///work/My%20Rules' }
    )
    assert.deepEqual(names(bundle), ['sub dir/main.l4', 'café.l4'])
  })

  test('a file whose name holds a literal percent sign keeps it (%25 decodes to one %, not twice)', async () => {
    const fs = disk({
      'file:///work/proj/main.l4': 'main',
      'file:///work/proj/100%25.l4': 'hundred',
      'file:///work/proj/a%2520b.l4': 'a b',
    })
    const bundle = await collectBundle(
      'file:///work/proj/main.l4',
      ['file:///work/proj/100%25.l4', 'file:///work/proj/a%2520b.l4'],
      { ...fs, rootUri: 'file:///work/proj' }
    )
    assert.deepEqual(names(bundle), ['main.l4', '100%.l4', 'a%20b.l4'])
  })

  test('a Windows file URI loses its drive letter, and the drive letter case does not matter', async () => {
    const fs = disk({
      'file:///c%3A/Users/me/rules/main.l4': 'main',
      'file:///C%3A/Users/me/rules/lib/util.l4': 'util',
    })
    const bundle = await collectBundle(
      'file:///c%3A/Users/me/rules/main.l4',
      ['file:///C%3A/Users/me/rules/lib/util.l4'],
      { ...fs, rootUri: 'file:///c%3A/Users/me/rules' }
    )
    assert.deepEqual(names(bundle), ['main.l4', 'lib/util.l4'])
  })

  test('a Windows import on another drive is outside the root, and the error shows both without the leading slash', async () => {
    const fs = disk({
      'file:///c%3A/Users/me/rules/main.l4': 'main',
      'file:///d%3A/shared/lib.l4': 'lib',
    })
    await assert.rejects(
      collectBundle(
        'file:///c%3A/Users/me/rules/main.l4',
        ['file:///d%3A/shared/lib.l4'],
        { ...fs, rootUri: 'file:///c%3A/Users/me/rules' }
      ),
      /d:\/shared\/lib\.l4 lies outside the project root c:\/Users\/me\/rules\./
    )
  })

  test('an encoded slash in a name is refused, not turned into a folder', async () => {
    const fs = disk({
      'file:///work/proj/main.l4': 'main',
      'file:///work/proj/a%2Fb.l4': 'ab',
    })
    await assert.rejects(
      collectBundle(
        'file:///work/proj/main.l4',
        ['file:///work/proj/a%2Fb.l4'],
        {
          ...fs,
          rootUri: 'file:///work/proj',
        }
      ),
      /cannot be part of a zip entry name/
    )
  })

  test('a ".." is resolved by URL parsing before anything else: inside the root it names the file it reaches', async () => {
    const fs = disk({
      'file:///w/p/main.l4': 'main',
      'file:///w/p/sub/../lib.l4': 'lib',
    })
    const bundle = await collectBundle(
      'file:///w/p/main.l4',
      ['file:///w/p/sub/../lib.l4'],
      { ...fs, rootUri: 'file:///w/p' }
    )
    assert.deepEqual(names(bundle), ['main.l4', 'lib.l4'])
  })

  test('the same ".." is refused when the file it reaches is outside the root, and shows the file it reaches', async () => {
    const fs = disk({
      'file:///w/p/sub/main.l4': 'main',
      'file:///w/p/sub/../lib.l4': 'lib',
    })
    await assert.rejects(
      collectBundle('file:///w/p/sub/main.l4', ['file:///w/p/sub/../lib.l4'], {
        ...fs,
        rootUri: 'file:///w/p/sub',
      }),
      /\/w\/p\/lib\.l4 lies outside the project root \/w\/p\/sub\. /
    )
    assert.deepEqual(fs.reads, ['file:///w/p/sub/main.l4'])
  })

  test('an escaped ".." (%2e%2e) that climbs out of the root is refused as outside the root, and is not read', async () => {
    const fs = disk({
      'file:///w/p/main.l4': 'main',
      'file:///w/p/%2e%2e/%2e%2e/other/lib.l4': 'lib',
    })
    await assert.rejects(
      collectBundle(
        'file:///w/p/main.l4',
        ['file:///w/p/%2e%2e/%2e%2e/other/lib.l4'],
        { ...fs, rootUri: 'file:///w/p' }
      ),
      /\/other\/lib\.l4 lies outside the project root \/w\/p\. /
    )
    assert.deepEqual(fs.reads, ['file:///w/p/main.l4'])
  })

  test('a URI with a host and no path has no file name and is refused, as an import and as the main file', async () => {
    const fs = disk({ 'file:///w/p/main.l4': 'main' })
    await assert.rejects(
      collectBundle('file:///w/p/main.l4', ['file://lib.l4'], {
        ...fs,
        rootUri: 'file:///w/p',
      }),
      /file:\/\/lib\.l4 has no file name/
    )
    await assert.rejects(
      collectBundle('file://lib.l4', [], fs),
      /file:\/\/lib\.l4 has no file name/
    )
  })

  test('a malformed %-escape is refused and the URI is named', async () => {
    const fs = disk({ 'file:///work/proj/main.l4': 'main' })
    await assert.rejects(
      collectBundle(
        'file:///work/proj/main.l4',
        ['file:///work/proj/100%.l4'],
        {
          ...fs,
          rootUri: 'file:///work/proj',
        }
      ),
      /file:\/\/\/work\/proj\/100%\.l4/
    )
  })
})

/** The service does not find a file beside its importer when the first folder of
 *  the file's path in the bundle has a space, a letter outside A to Z, or one of
 *  `# ' + ( ) % , = @ & ! $ ; [ ]` in its name (a residual of the fix for
 *  smucclaw/l4-ide#971, which is closed; no issue tracks it yet), though it
 *  finds one at the top. The deploy is stricter: it stops at any character other
 *  than ASCII letters, digits, `.`, `-` and `_` in any folder of the path. The
 *  deploy knows the files and not the import lines, so every file but the main
 *  one is one an import brought in. */
describe('a folder the service cannot look into', () => {
  /** A main file at the top importing `helper` from `folder` (below the root),
   *  beside nothing: the shape in which the folder survives into the names. */
  const inFolder = (folder: string) => {
    const dir = `file:///work/proj/${folder}`
    const fs = disk({
      'file:///work/proj/main.l4': 'main',
      [`${dir}/helper.l4`]: 'helper',
    })
    return collectBundle('file:///work/proj/main.l4', [`${dir}/helper.l4`], {
      ...fs,
      rootUri: 'file:///work/proj',
    })
  }

  test('a space in the folder stops the deploy, naming the file, the folder and the way out', async () => {
    await assert.rejects(inFolder('my%20dir'), (err: Error) => {
      assert.match(
        err.message,
        /^Deploy stopped: the deployed service may not find a file that is imported, because of the name of the folder it is in: /
      )
      assert.match(
        err.message,
        /my dir\/helper\.l4 \(\/work\/proj\/my dir\/helper\.l4\) is in the folder "my dir"\./
      )
      assert.ok(
        err.message.includes(
          "does not find a file beside the file that imports it when the first folder of the file's path in the bundle has a space, a letter outside A to Z, or one of # ' + ( ) % , = @ & ! $ ; [ ] in its name."
        )
      )
      assert.match(err.message, /every call would then fail/)
      assert.ok(
        err.message.includes(
          'in any folder of the path, not only the first, so it also stops a few names the service would find, for example ok/my dir and a~b. '
        )
      )
      assert.doesNotMatch(
        err.message,
        /so that the check does not depend on how the service reads a path/
      )
      assert.ok(
        err.message.includes(
          "Rename the folder to use only letters, digits, '.', '-' and '_', and deploy again. "
        )
      )
      return true
    })
  })

  test('a Hebrew folder name and an accented one stop the deploy', async () => {
    await assert.rejects(
      inFolder('%D7%AA%D7%99%D7%A7%D7%99%D7%99%D7%94'),
      /in the folder "תיקייה"/
    )
    await assert.rejects(
      inFolder('dossier%20%C3%A9'),
      /in the folder "dossier é"/
    )
    await assert.rejects(inFolder('d%C3%A9j%C3%A0'), /in the folder "déjà"/)
  })

  test('a character outside letters, digits, ".", "-" and "_" stops the deploy, wherever it is in the folder path', async () => {
    await assert.rejects(inFolder('a%2Bb'), /in the folder "a\+b"/)
    await assert.rejects(inFolder('ok/no%20pe'), /in the folder "ok\/no pe"/)
    await assert.rejects(inFolder('a%20b/c'), /in the folder "a b\/c"/)
    await assert.rejects(inFolder('50%25'), /in the folder "50%"/)
  })

  test('each character that the service was measured to fail on stops the deploy', async () => {
    // A space, and # ' + ( ) % , = @ & ! $ ; [ ] (2026-10-26,
    // specs/as-built/import-resolution.md).
    for (const c of " #'+()%,=@&!$;[]") {
      const folder = `a${c}b`
      await assert.rejects(
        inFolder(encodeURIComponent(folder)),
        (err: Error) => {
          assert.ok(err.message.includes(`is in the folder "${folder}"`))
          return true
        }
      )
    }
  })

  test('names that the service finds are stopped too: a~b, and a safe first folder above an unsafe one', async () => {
    await assert.rejects(inFolder('a~b'), /in the folder "a~b"/)
    await assert.rejects(inFolder('ok/my%20dir'), /in the folder "ok\/my dir"/)
    await assert.rejects(
      inFolder('ok/dossier%20%C3%A9'),
      /in the folder "ok\/dossier é"/
    )
  })

  test('the message says what to do about a copy of a standard library module in such a folder', async () => {
    await assert.rejects(inFolder('my%20dir'), (err: Error) => {
      assert.ok(
        err.message.includes(
          'A copy of a standard library module in such a folder stops the deploy too, even when it is exactly the copy built into the service, because this deploy cannot tell a built-in copy from any other file (l4 deploy leaves such a copy out). '
        )
      )
      assert.match(
        err.message,
        /If the language server found that copy through JL4_LIBRARY_PATH, you can instead unset JL4_LIBRARY_PATH for the editor\.$/
      )
      return true
    })
  })

  test('letters, digits, ".", "-" and "_" are allowed, and the folders are kept in the names', async () => {
    assert.deepEqual(names(await inFolder('a')), ['main.l4', 'a/helper.l4'])
    assert.deepEqual(names(await inFolder('my-dir_2.x')), [
      'main.l4',
      'my-dir_2.x/helper.l4',
    ])
    assert.deepEqual(names(await inFolder('Rules/v1.2')), [
      'main.l4',
      'Rules/v1.2/helper.l4',
    ])
  })

  test('the main file may be in such a folder: nothing looks it up', async () => {
    const fs = disk({
      'file:///work/proj/my%20dir/main.l4': 'main',
      'file:///work/proj/defs.l4': 'defs',
    })
    const bundle = await collectBundle(
      'file:///work/proj/my%20dir/main.l4',
      ['file:///work/proj/defs.l4'],
      { ...fs, rootUri: 'file:///work/proj' }
    )
    assert.deepEqual(names(bundle), ['my dir/main.l4', 'defs.l4'])
  })

  test("a file at the top of the bundle is allowed, whatever the main file's folder is called", async () => {
    const fs = disk({
      'file:///work/proj/dossier%20%C3%A9/main.l4': 'main',
      'file:///work/proj/defs.l4': 'defs',
    })
    const bundle = await collectBundle(
      'file:///work/proj/dossier%20%C3%A9/main.l4',
      ['file:///work/proj/defs.l4'],
      { ...fs, rootUri: 'file:///work/proj' }
    )
    assert.deepEqual(names(bundle), ['dossier é/main.l4', 'defs.l4'])
  })

  test('files that all sit in one such folder are uploaded by their plain names, so nothing is refused', async () => {
    const fs = disk({
      'file:///work/proj/my%20dir/main.l4': 'main',
      'file:///work/proj/my%20dir/helper.l4': 'helper',
    })
    const bundle = await collectBundle(
      'file:///work/proj/my%20dir/main.l4',
      ['file:///work/proj/my%20dir/helper.l4'],
      { ...fs, rootUri: 'file:///work/proj' }
    )
    assert.deepEqual(names(bundle), ['main.l4', 'helper.l4'])
  })

  test('every file that is refused is named, and nothing is returned', async () => {
    const fs = disk({
      'file:///work/proj/main.l4': 'main',
      'file:///work/proj/my%20dir/one.l4': 'one',
      'file:///work/proj/ok/two.l4': 'two',
      'file:///work/proj/d%C3%A9j%C3%A0/three.l4': 'three',
    })
    await assert.rejects(
      collectBundle(
        'file:///work/proj/main.l4',
        [
          'file:///work/proj/my%20dir/one.l4',
          'file:///work/proj/ok/two.l4',
          'file:///work/proj/d%C3%A9j%C3%A0/three.l4',
        ],
        { ...fs, rootUri: 'file:///work/proj' }
      ),
      (err: Error) => {
        assert.match(
          err.message,
          /the deployed service may not find files that are imported, because of the names of the folders they are in: /
        )
        assert.match(
          err.message,
          /my dir\/one\.l4 .* is in the folder "my dir"; déjà\/three\.l4 .* is in the folder "déjà"\./
        )
        assert.doesNotMatch(err.message, /ok\/two\.l4/)
        return true
      }
    )
  })
})

describe('two entries with one name', () => {
  test('one file spelled two ways stops the deploy, and both spellings are named', async () => {
    const fs = disk({
      'file:///work/proj/main.l4': 'main',
      'file:///work/proj/a.l4': 'a',
      'file:///work/proj/a%2El4': 'a again',
    })
    await assert.rejects(
      collectBundle(
        'file:///work/proj/main.l4',
        ['file:///work/proj/a.l4', 'file:///work/proj/a%2El4'],
        { ...fs, rootUri: 'file:///work/proj' }
      ),
      (err: Error) => {
        assert.match(err.message, /file:\/\/\/work\/proj\/a\.l4/)
        assert.match(err.message, /file:\/\/\/work\/proj\/a%2El4/)
        assert.match(err.message, /both be stored as "a\.l4"/)
        return true
      }
    )
  })

  test('a name with an uppercase letter spelled two ways (A.l4, %41.l4) stops the deploy, and both spellings are named', async () => {
    const fs = disk({
      'file:///work/proj/main.l4': 'main',
      'file:///work/proj/A.l4': 'a',
      'file:///work/proj/%41.l4': 'a again',
    })
    await assert.rejects(
      collectBundle(
        'file:///work/proj/main.l4',
        ['file:///work/proj/A.l4', 'file:///work/proj/%41.l4'],
        { ...fs, rootUri: 'file:///work/proj' }
      ),
      (err: Error) => {
        assert.match(err.message, /file:\/\/\/work\/proj\/A\.l4/)
        assert.match(err.message, /file:\/\/\/work\/proj\/%41\.l4/)
        assert.match(err.message, /both be stored as "A\.l4"/)
        return true
      }
    )
  })

  test('names that differ only in case are two files, as on the service', async () => {
    const fs = disk({
      'file:///work/proj/main.l4': 'main',
      'file:///work/proj/Rates.l4': 'upper',
      'file:///work/proj/rates.l4': 'lower',
    })
    const bundle = await collectBundle(
      'file:///work/proj/main.l4',
      ['file:///work/proj/Rates.l4', 'file:///work/proj/rates.l4'],
      { ...fs, rootUri: 'file:///work/proj' }
    )
    assert.deepEqual(names(bundle), ['main.l4', 'Rates.l4', 'rates.l4'])
  })
})

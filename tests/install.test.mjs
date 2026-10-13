import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';

function fixture({ incomplete = false } = {}) {
  const root = mkdtempSync(join(process.env.PI_SCRATCH_DIR || tmpdir(), 'blog-install-test-'));
  const bin = join(root, 'bin');
  const source = join(root, 'archive', 'blog-main');
  const state = join(root, 'state');
  const temp = join(root, 'temp');
  const trace = join(root, 'trace');
  for (const dir of [bin, source, temp]) mkdirSync(dir, { recursive: true });
  copyFileSync(new URL('../install.sh', import.meta.url), join(root, 'install.sh'));
  writeFileSync(join(source, 'deploy.sh'), `#!/bin/bash
set -eu
printf 'deploy domain=%s SKIP_PULL=%s umask=%s\\n' "$1" "$SKIP_PULL" "$(umask)" >> "$TRACE"
[ "\${FAIL_DEPLOY:-0}" != 1 ]
`);
  writeFileSync(join(source, 'package.json'), '{}');
  writeFileSync(join(source, 'package-lock.json'), '{}');
  mkdirSync(join(source, 'src', 'pages'), { recursive: true });
  if (!incomplete) writeFileSync(join(source, 'src', 'pages', 'index.astro'), '<html/>');
  const archive = join(root, 'source.tar.gz');
  const pack = spawnSync('tar', ['-czf', archive, '-C', join(root, 'archive'), 'blog-main']);
  assert.equal(pack.status, 0);
  const stubs = {
    id: '#!/bin/sh\necho "${TEST_UID:-0}"\n',
    'apt-get': '#!/bin/sh\necho "unexpected apt-get" >&2\nexit 90\n',
    git: '#!/bin/sh\necho "unexpected git" >&2\nexit 90\n',
    flock: '#!/bin/sh\n[ "${BUSY:-0}" != 1 ]\n',
    curl: `#!/bin/sh
printf 'curl %s\\n' "$*" >> "$TRACE"
[ "\${FAIL_DOWNLOAD:-0}" != 1 ] || exit 22
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then cp "$ARCHIVE" "$2"; exit 0; fi
  shift
done
exit 1
`,
  };
  for (const [name, content] of Object.entries(stubs)) writeFileSync(join(bin, name), content, { mode: 0o755 });
  return {
    state, temp,
    run(args, env = {}) {
      const result = spawnSync('bash', [join(root, 'install.sh'), ...args], {
        encoding: 'utf8', timeout: 10_000,
        env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, BLOG_STATE_DIR: state, TMPDIR: temp, TRACE: trace, ARCHIVE: archive, ...env },
      });
      assert.ifError(result.error);
      return { ...result, output: result.stdout + result.stderr, commands: existsSync(trace) ? readFileSync(trace, 'utf8') : '' };
    },
    dispose() { rmSync(root, { recursive: true, force: true }); },
  };
}

test('GitHub 入口帮助不需要 root，错误参数不下载', () => {
  for (const args of [['--help'], [], ['--bad'], ['a', 'b'], ['example.com/path'], [':0'], [':65536']]) {
    const f = fixture();
    try {
      const r = f.run(args);
      assert.equal(r.status === 0, args[0] === '--help', r.output);
      assert.equal(r.commands, '');
    } finally { f.dispose(); }
  }
});

test('非 root 用户被拒绝，并发部署被拒绝', () => {
  for (const env of [{ TEST_UID: '1000' }, { BUSY: '1' }]) {
    const f = fixture();
    try {
      const r = f.run(['example.com'], env);
      assert.notEqual(r.status, 0);
      assert.equal(r.commands, '');
    } finally { f.dispose(); }
  }
});

test('下载源码实际解压，不调用 Git，部署成功记住域名并清理临时源码', () => {
  const f = fixture();
  try {
    const r = f.run(['https://blog.example.com/']);
    assert.equal(r.status, 0, r.output);
    assert.match(r.commands, /codeload.github.com\/chilin11\/blog\/tar.gz\/refs\/heads\/main/);
    assert.match(r.commands, /deploy domain=blog.example.com SKIP_PULL=1 umask=0022/);
    assert.equal(readFileSync(join(f.state, 'domain'), 'utf8'), 'blog.example.com\n');
    assert.deepEqual(readdirSync(f.temp), []);
    const next = f.run([]);
    assert.equal(next.status, 0, next.output);
  } finally { f.dispose(); }
});

test('HTTP 模式使用 :80', () => {
  const f = fixture();
  try {
    const r = f.run([':80']);
    assert.equal(r.status, 0, r.output);
    assert.match(r.commands, /deploy domain=:80/);
  } finally { f.dispose(); }
});

test('下载失败或源码不完整不部署、不保存域名，清理临时文件', () => {
  for (const incomplete of [false, true]) {
    const f = fixture({ incomplete });
    try {
      const r = f.run(['blog.example.com'], incomplete ? {} : { FAIL_DOWNLOAD: '1' });
      assert.notEqual(r.status, 0);
      assert.doesNotMatch(r.commands, /deploy domain=/);
      assert(!existsSync(join(f.state, 'domain')));
      assert.deepEqual(readdirSync(f.temp), []);
    } finally { f.dispose(); }
  }
});

test('部署失败保留上次域名，不报告更新完成', () => {
  const f = fixture();
  try {
    mkdirSync(f.state);
    writeFileSync(join(f.state, 'domain'), 'old.example.com\n');
    const r = f.run(['new.example.com'], { FAIL_DEPLOY: '1' });
    assert.notEqual(r.status, 0);
    assert.equal(readFileSync(join(f.state, 'domain'), 'utf8'), 'old.example.com\n');
    assert.doesNotMatch(r.output, /更新完成/);
    assert.deepEqual(readdirSync(f.temp), []);
  } finally { f.dispose(); }
});

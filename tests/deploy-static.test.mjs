import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';

const source = readFileSync(new URL('../deploy-static.sh', import.meta.url), 'utf8');

test('本地与嵌入远程脚本均通过 Bash 语法检查', () => {
  const remote = source.split("<<'REMOTE_SCRIPT'\n")[1].split('\nREMOTE_SCRIPT')[0];
  for (const script of [source, remote]) {
    const result = spawnSync('bash', ['-n'], { input: script, encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
  }
});

function fixture() {
  const root = mkdtempSync(join(process.env.PI_SCRATCH_DIR || tmpdir(), 'blog-static-test-'));
  const bin = join(root, 'bin');
  const trace = join(root, 'trace');
  mkdirSync(bin);
  copyFileSync(new URL('../deploy-static.sh', import.meta.url), join(root, 'deploy-static.sh'));
  const stubs = {
    node: '#!/bin/sh\nexit 0\n',
    npm: `#!/bin/sh
printf 'npm %s SITE_URL=%s\\n' "$*" "\${SITE_URL:-}" >> "$TRACE"
[ "\${FAIL_BUILD:-0}" != 1 ] || exit 1
if [ "$1" = run ] && [ "\${MISSING_DIST:-0}" != 1 ]; then mkdir -p dist; echo '<html>built</html>' > dist/index.html; fi
`,
    ssh: `#!/bin/sh
printf 'ssh %s\\n' "$*" >> "$TRACE"
case "$*" in
  *'mktemp -d'*) printf '%s\\n' "\${STAGE:-/tmp/blog-upload.Test1234}" ;;
  *"'setup'"*) cat >/dev/null; [ "\${FAIL_SETUP:-0}" != 1 ] ;;
  *"'check'"*) cat >/dev/null; [ "\${FAIL_CHECK:-0}" != 1 ] ;;
  *"'publish'"*) cat >/dev/null; [ "\${FAIL_PUBLISH:-0}" != 1 ] ;;
  *) cat >/dev/null ;;
esac
`,
    scp: `#!/bin/sh
printf 'scp %s\\n' "$*" >> "$TRACE"
[ "\${FAIL_UPLOAD:-0}" != 1 ]
`,
  };
  for (const [name, content] of Object.entries(stubs)) writeFileSync(join(bin, name), content, { mode: 0o755 });
  return {
    root,
    run(args, overrides = {}) {
      const result = spawnSync('bash', [join(root, 'deploy-static.sh'), ...args], {
        cwd: root, encoding: 'utf8', timeout: 10_000,
        env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, TRACE: trace, ...overrides },
      });
      assert.ifError(result.error);
      return { ...result, output: result.stdout + result.stderr, commands: existsSync(trace) ? readFileSync(trace, 'utf8') : '' };
    },
    dispose() { rmSync(root, { recursive: true, force: true }); },
  };
}
const target = ['root@vps.example.com', 'https://blog.example.com'];

test('帮助与错误参数不构建、不连接服务器', () => {
  for (const args of [['--help'], [], ['--bad'], ['--port'], ['--port', '0', ...target], ['root@host;id', target[1]], [target[0], 'https://blog.example.com/path']]) {
    const f = fixture();
    try {
      const result = f.run(args);
      assert.equal(result.commands, '');
      assert.equal(result.status === 0, args[0] === '--help', result.output);
    } finally { f.dispose(); }
  }
});

test('初始化按本地构建、远程 setup、check、上传、publish 顺序执行并记住配置', () => {
  const f = fixture();
  try {
    const result = f.run(['--setup', '--port', '2222', ...target]);
    assert.equal(result.status, 0, result.output);
    let previous = -1;
    for (const step of ['npm ci', 'npm run build SITE_URL=https://blog.example.com', "'setup'", "'check'", 'scp -P 2222', "'publish'"]) {
      const index = result.commands.indexOf(step);
      assert(index > previous, `Missing/out-of-order: ${step}`);
      previous = index;
    }
    const config = join(f.root, '.deploy-static.env');
    assert.match(readFileSync(config, 'utf8'), /SSH_PORT=2222/);
    assert.equal(statSync(config).mode & 0o777, 0o600);
    const next = f.run([]);
    assert.equal(next.status, 0, next.output);
    assert.match(next.commands, /ssh -p 2222/);
  } finally { f.dispose(); }
});

test('构建失败或缺少 dist 时不连接服务器', () => {
  for (const env of [{ FAIL_BUILD: '1' }, { MISSING_DIST: '1' }]) {
    const f = fixture();
    try {
      const result = f.run(target, env);
      assert.notEqual(result.status, 0);
      assert.doesNotMatch(result.commands, /ssh |scp /);
      assert(!existsSync(join(f.root, '.deploy-static.env')));
    } finally { f.dispose(); }
  }
});

test('远程初始化与检查失败不上传也不保存配置', () => {
  for (const env of [{ FAIL_SETUP: '1' }, { FAIL_CHECK: '1' }]) {
    const f = fixture();
    try {
      const result = f.run(['--setup', ...target], env);
      assert.notEqual(result.status, 0);
      assert.doesNotMatch(result.commands, /scp /);
      assert(!existsSync(join(f.root, '.deploy-static.env')));
    } finally { f.dispose(); }
  }
});

test('上传失败不发布，发布失败不报告成功；两者均清理远程临时目录', () => {
  for (const env of [{ FAIL_UPLOAD: '1' }, { FAIL_PUBLISH: '1' }]) {
    const f = fixture();
    try {
      const result = f.run(target, env);
      assert.notEqual(result.status, 0);
      assert.doesNotMatch(result.output, /发布完成/);
      if (env.FAIL_UPLOAD) assert.doesNotMatch(result.commands, /'publish'/);
      assert.match(result.commands, /rm -rf -- '\/tmp\/blog-upload.Test1234'/);
      assert(!existsSync(join(f.root, '.deploy-static.env')));
    } finally { f.dispose(); }
  }
});

test('无效远程临时路径不上传、不执行危险清理', () => {
  const f = fixture();
  try {
    const result = f.run(target, { STAGE: '/' });
    assert.notEqual(result.status, 0);
    assert.doesNotMatch(result.commands, /scp |rm -rf/);
  } finally { f.dispose(); }
});

test('配置文件只按键值读取，不执行 shell 内容', () => {
  const f = fixture();
  try {
    writeFileSync(join(f.root, '.deploy-static.env'), `TARGET=root@vps.example.com\nSITE_URL=https://blog.example.com\nSSH_PORT=22\nUNKNOWN=$(touch ${join(f.root, 'executed')})\n`);
    const result = f.run([]);
    assert.equal(result.status, 0, result.output);
    assert(!existsSync(join(f.root, 'executed')));
  } finally { f.dispose(); }
});

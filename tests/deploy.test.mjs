import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';

// 隔离 git / Docker / apt，测试不会拉取代码、启动容器或安装系统软件。
function run(args, overrides = {}) {
  const root = mkdtempSync(join(process.env.PI_SCRATCH_DIR || tmpdir(), 'blog-deploy-test-'));
  const bin = join(root, 'bin');
  const trace = join(root, 'trace');
  mkdirSync(bin);
  copyFileSync(new URL('../deploy.sh', import.meta.url), join(root, 'deploy.sh'));
  const stubs = {
    docker: `#!/bin/sh
printf 'docker %s\\n' "$*" >> "$TRACE"
case "$*" in
  *' build '*) [ "\${FAIL_BUILD:-0}" != 1 ] ;;
  *' up '*) [ "\${FAIL_WAIT:-0}" != 1 ] ;;
  *) exit 0 ;;
esac
`,
    git: `#!/bin/sh
printf 'git %s\\n' "$*" >> "$TRACE"
case "$1" in
  status) [ "\${DIRTY:-0}" != 1 ] || printf ' M src/pages/index.astro\\n' ;;
  pull) [ "\${FAIL_PULL:-0}" != 1 ] ;;
  log) printf 'abc123 test version\\n' ;;
  *) exit 0 ;;
esac
`,
    id: '#!/bin/sh\nprintf "0\\n"\n',
    'apt-get': '#!/bin/sh\necho "Unexpected apt-get invocation" >&2\nexit 90\n',
  };
  for (const [name, content] of Object.entries(stubs)) {
    writeFileSync(join(bin, name), content, { mode: 0o755 });
  }
  try {
    const result = spawnSync('bash', [join(root, 'deploy.sh'), ...args], {
      encoding: 'utf8', timeout: 10_000,
      env: { ...process.env, SKIP_PULL: '0', WEB_ROOT: '/var/www/blog', PATH: `${bin}:${process.env.PATH}`, TRACE: trace, ...overrides },
    });
    let commands = '';
    try { commands = readFileSync(trace, 'utf8'); } catch { /* 参数检查可能不执行任何命令 */ }
    assert.ifError(result.error);
    return { ...result, commands, output: result.stdout + result.stderr };
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

test('帮助无需 root、Docker 或系统依赖', () => {
  const result = run(['--help']);
  assert.equal(result.status, 0);
  assert.match(result.output, /--docker/);
  assert.equal(result.commands, '');
});

test('未知参数与 Docker 域名参数被拒绝', () => {
  for (const args of [['--unknown'], ['--docker', 'example.com']]) {
    const result = run(args);
    assert.notEqual(result.status, 0);
    assert.equal(result.commands, '');
  }
});

test('Docker 正常更新按拉取、校验、构建、健康检查的顺序执行', () => {
  const result = run(['--docker']);
  assert.equal(result.status, 0, result.output);
  const steps = ['git pull --ff-only', 'config --quiet', 'build --pull blog', 'up -d --wait --wait-timeout 90 blog', 'ps blog'];
  let previous = -1;
  for (const step of steps) {
    const position = result.commands.indexOf(step);
    assert(position > previous, `Missing or out-of-order step: ${step}`);
    previous = position;
  }
});

test('未提交改动阻止拉取与构建', () => {
  const result = run(['--docker'], { DIRTY: '1' });
  assert.notEqual(result.status, 0);
  assert.match(result.output, /未提交改动/);
  assert.doesNotMatch(result.commands, /git pull|build --pull/);
});

test('--no-pull 和 SKIP_PULL=1 均可部署本地代码', () => {
  for (const [args, env] of [
    [['--docker', '--no-pull'], { DIRTY: '1' }],
    [['--docker'], { DIRTY: '1', SKIP_PULL: '1' }],
  ]) {
    const result = run(args, env);
    assert.equal(result.status, 0, result.output);
    assert.doesNotMatch(result.commands, /git pull|git status/);
    assert.match(result.commands, /build --pull blog/);
  }
});

test('拉取失败不启动构建', () => {
  const result = run(['--docker'], { FAIL_PULL: '1' });
  assert.notEqual(result.status, 0);
  assert.match(result.output, /git pull 失败/);
  assert.doesNotMatch(result.commands, /build --pull/);
});

test('构建失败不替换运行容器', () => {
  const result = run(['--docker'], { FAIL_BUILD: '1' });
  assert.notEqual(result.status, 0);
  assert.doesNotMatch(result.commands, /up -d/);
});

test('健康检查失败提示日志，不报告成功', () => {
  const result = run(['--docker'], { FAIL_WAIT: '1' });
  assert.notEqual(result.status, 0);
  assert.match(result.output, /容器未健康/);
  assert.doesNotMatch(result.output, /Docker 部署完成/);
});

test('Caddy 拒绝包含路径、配置注入字符与越界端口的参数', () => {
  for (const domain of ['example.com/path', 'example.com {', ':0', ':65536', ':abc']) {
    const result = run([domain]);
    assert.notEqual(result.status, 0);
    assert.doesNotMatch(result.output, /Unexpected apt-get/);
    assert.equal(result.commands, '');
  }
});

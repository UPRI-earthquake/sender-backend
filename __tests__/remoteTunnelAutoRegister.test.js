const fs = require('fs').promises;
const os = require('os');
const path = require('path');
const http = require('http');
const { execFile } = require('child_process');
const { promisify } = require('util');

const execFileAsync = promisify(execFile);

const scriptPath = path.resolve(__dirname, '../sender-backend.sh');
jest.setTimeout(30000);

async function writeExecutable(filePath, contents) {
  await fs.writeFile(filePath, contents);
  await fs.chmod(filePath, 0o755);
}

async function runScript(args, env, timeoutMs = 20000) {
  try {
    const result = await execFileAsync('bash', [scriptPath, ...args], {
      env,
      timeout: timeoutMs,
      maxBuffer: 1024 * 1024,
    });
    return {
      code: 0,
      stdout: result.stdout || '',
      stderr: result.stderr || '',
    };
  } catch (error) {
    return {
      code: typeof error.code === 'number' ? error.code : 1,
      stdout: error.stdout || '',
      stderr: error.stderr || '',
    };
  }
}

function startEnrollServer(handler) {
  return new Promise((resolve) => {
    const server = http.createServer(handler);
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      resolve({
        server,
        port: address.port,
      });
    });
  });
}

function closeServer(server) {
  return new Promise((resolve) => {
    server.close(() => resolve());
  });
}

describe('sender-backend remote tunnel auto-register', () => {
  let tempRoot;
  let fakeBin;
  let envFile;
  let keyPath;
  let knownHostsPath;
  let statePath;
  let pidPath;

  beforeEach(async () => {
    tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'sender-tunnel-autoreg-'));
    fakeBin = path.join(tempRoot, 'bin');
    envFile = path.join(tempRoot, 'sender-remote-tunnel.env');
    keyPath = path.join(tempRoot, 'keys', 'id_ed25519');
    knownHostsPath = path.join(tempRoot, 'keys', 'known_hosts');
    statePath = path.join(tempRoot, 'state', 'remote-tunnel-state.json');
    pidPath = path.join(tempRoot, 'state', 'remote-tunnel.pid');

    await fs.mkdir(fakeBin, { recursive: true });
    await writeExecutable(
      path.join(fakeBin, 'autossh'),
      '#!/usr/bin/env bash\nsleep 3\nexit 0\n',
    );
  });

  afterEach(async () => {
    if (tempRoot) {
      await fs.rm(tempRoot, { recursive: true, force: true });
    }
  });

  it('auto-registers tunnel config, writes env/known_hosts, and is retry-safe', async () => {
    let enrollCalls = 0;
    const { server, port } = await startEnrollServer((req, res) => {
      if (req.method === 'POST' && req.url === '/device/tunnel/enroll') {
        enrollCalls += 1;
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
          status: 80,
          message: 'Device tunnel enrollment successful',
          payload: {
            REMOTE_TUNNEL_BASTION_HOST: 'ops.example.org',
            REMOTE_TUNNEL_BASTION_PORT: 443,
            REMOTE_TUNNEL_BASTION_USER: 'rt-am_r24fa',
            REMOTE_TUNNEL_REMOTE_PORT: 22501,
            REMOTE_TUNNEL_BASTION_HOST_KEY: 'ops.example.org ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMockHostKey',
          },
        }));
        return;
      }
      res.writeHead(404);
      res.end();
    });

    try {
      await fs.writeFile(envFile, [
        'REMOTE_TUNNEL_ENABLED=true',
        'REMOTE_TUNNEL_AUTO_REGISTER_ENABLED=true',
        `REMOTE_TUNNEL_ENROLL_ENDPOINT=http://127.0.0.1:${port}/device/tunnel/enroll`,
        'REMOTE_TUNNEL_ENROLL_TOKEN=test-sensor-token',
        `REMOTE_TUNNEL_KEY_PATH=${keyPath}`,
        `REMOTE_TUNNEL_KNOWN_HOSTS_PATH=${knownHostsPath}`,
        `REMOTE_TUNNEL_STATE_FILE=${statePath}`,
        `REMOTE_TUNNEL_PID_FILE=${pidPath}`,
      ].join('\n'));

      const commonEnv = {
        ...process.env,
        PATH: `${fakeBin}:${process.env.PATH}`,
        REMOTE_TUNNEL_ENV_FILE: envFile,
      };

      const first = await runScript(['REMOTE_TUNNEL_START'], commonEnv);
      expect(first.code).toBe(0);
      expect(enrollCalls).toBe(1);

      const writtenEnv = await fs.readFile(envFile, 'utf-8');
      expect(writtenEnv).toMatch(/REMOTE_TUNNEL_BASTION_HOST='ops\.example\.org'/);
      expect(writtenEnv).toMatch(/REMOTE_TUNNEL_BASTION_USER='rt-am_r24fa'/);
      expect(writtenEnv).toMatch(/REMOTE_TUNNEL_REMOTE_PORT='22501'/);
      expect(writtenEnv).toMatch(/REMOTE_TUNNEL_BASTION_HOST_KEY='ops\.example\.org ssh-ed25519 [^']+'/);

      const knownHosts = await fs.readFile(knownHostsPath, 'utf-8');
      expect(knownHosts).toContain('ssh-ed25519');

      const second = await runScript(['REMOTE_TUNNEL_START'], commonEnv);
      expect(second.code).toBe(0);
      expect(`${second.stdout}${second.stderr}`).not.toContain('command not found');
      expect(enrollCalls).toBe(1);
    } finally {
      await closeServer(server);
    }
  });

  it('fails safely when enroll token is missing', async () => {
    await fs.writeFile(envFile, [
      'REMOTE_TUNNEL_ENABLED=true',
      'REMOTE_TUNNEL_AUTO_REGISTER_ENABLED=true',
      'REMOTE_TUNNEL_ENROLL_ENDPOINT=http://127.0.0.1:59999/device/tunnel/enroll',
      `REMOTE_TUNNEL_KEY_PATH=${keyPath}`,
      `REMOTE_TUNNEL_KNOWN_HOSTS_PATH=${knownHostsPath}`,
      `REMOTE_TUNNEL_STATE_FILE=${statePath}`,
      `REMOTE_TUNNEL_PID_FILE=${pidPath}`,
    ].join('\n'));

    const result = await runScript(['REMOTE_TUNNEL_START'], {
      ...process.env,
      PATH: `${fakeBin}:${process.env.PATH}`,
      REMOTE_TUNNEL_ENV_FILE: envFile,
    });

    expect(result.code).not.toBe(0);
    expect(`${result.stdout}${result.stderr}`).toContain('REMOTE_TUNNEL_ENROLL_TOKEN is required');
  });

  it('fails safely on enrollment API error without mutating tunnel mapping', async () => {
    const { server, port } = await startEnrollServer((req, res) => {
      if (req.method === 'POST' && req.url === '/device/tunnel/enroll') {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ status: 190, message: 'Enrollment backend unavailable' }));
        return;
      }
      res.writeHead(404);
      res.end();
    });

    try {
      await fs.writeFile(envFile, [
        'REMOTE_TUNNEL_ENABLED=true',
        'REMOTE_TUNNEL_AUTO_REGISTER_ENABLED=true',
        `REMOTE_TUNNEL_ENROLL_ENDPOINT=http://127.0.0.1:${port}/device/tunnel/enroll`,
        'REMOTE_TUNNEL_ENROLL_TOKEN=test-sensor-token',
        `REMOTE_TUNNEL_KEY_PATH=${keyPath}`,
        `REMOTE_TUNNEL_KNOWN_HOSTS_PATH=${knownHostsPath}`,
        `REMOTE_TUNNEL_STATE_FILE=${statePath}`,
        `REMOTE_TUNNEL_PID_FILE=${pidPath}`,
      ].join('\n'));

      const result = await runScript(['REMOTE_TUNNEL_START'], {
        ...process.env,
        PATH: `${fakeBin}:${process.env.PATH}`,
        REMOTE_TUNNEL_ENV_FILE: envFile,
      });

      expect(result.code).not.toBe(0);
      expect(`${result.stdout}${result.stderr}`).toContain('Auto-registration rejected by enrollment API');

      const writtenEnv = await fs.readFile(envFile, 'utf-8');
      expect(writtenEnv).not.toContain('REMOTE_TUNNEL_BASTION_HOST=ops.example.org');
    } finally {
      await closeServer(server);
    }
  });
});

import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));

export const name = 'lan-toolkit';
export const inject = ['tools'];

function runScript(script, powershell, extraArgs) {
  if (!existsSync(script)) {
    return Promise.resolve({
      exitCode: 1,
      output: `[lan-toolkit] Скрипт не найден: ${script}\nНастрой путь к lan-win.ps1 в конфиге плагина (config.script).`,
    });
  }
  const args = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script, '-NoElevate', ...extraArgs];
  return new Promise((resolve) => {
    const child = spawn(powershell, args, { windowsHide: true });
    let out = '';
    let err = '';
    child.stdout.on('data', (d) => { out += d.toString(); });
    child.stderr.on('data', (d) => { err += d.toString(); });
    child.on('error', (e) => resolve({ exitCode: 1, output: `[lan-toolkit] Не запускается ${powershell}: ${e.message}` }));
    child.on('close', (code) => resolve({ exitCode: code ?? 1, output: (out + (err ? '\n' + err : '')).trim() }));
  });
}

export function apply(ctx, config = {}) {
  const script = config.script || join(__dirname, 'bin', 'lan-win.ps1');
  const powershell = config.powershell || 'powershell.exe';

  function tool(name, description, parameters, buildArgs, timeoutMs) {
    ctx.tools.register({
      name,
      description,
      parameters,
      output: {
        schema: {
          type: 'object',
          properties: {
            exitCode: { type: 'integer', description: 'Код выхода PowerShell (0 = успех).' },
            output: { type: 'string', description: 'Текстовый вывод скрипта.' },
          },
        },
        render(args, value) {
          const text = value && value.output ? value.output : JSON.stringify(value ?? {});
          return [{ type: 'text', text }];
        },
      },
      timeoutMs: timeoutMs ?? 120000,
      isConcurrencySafe: () => false,
      async execute(args) {
        try {
          return await runScript(script, powershell, buildArgs(args || {}));
        } catch (e) {
          return { exitCode: 1, output: `[lan-toolkit] Ошибка: ${e.message}` };
        }
      },
    });
  }

  // ---- Информация (без прав администратора) ----
  tool(
    'lan_toolkit_status',
    'Показать состояние сети Windows: IP-адреса, имя ПК, профиль сети, Wi-Fi (и предупреждение про AP-изоляцию), SMB-шары, службы. Ничего не меняет.',
    { type: 'object', properties: {}, required: [] },
    () => ['-Action', 'status'],
  );

  tool(
    'lan_toolkit_mc_address',
    'Показать адрес Minecraft для друзей (IP + порт), если кто-то открыл «Открыть для сети». Полезно, чтобы дать друзьям ссылку для подключения по LAN.',
    { type: 'object', properties: {}, required: [] },
    () => ['-Action', 'mc'],
  );

  tool(
    'lan_toolkit_worlds',
    'Найти миры Minecraft на этом ПК (Java: vanilla/Prism/MultiMC и Bedrock UWP) и показать их путь, размер и дату изменения.',
    { type: 'object', properties: {}, required: [] },
    () => ['-Action', 'world', '-WorldMode', 'list'],
  );

  // ---- Партнёры по SSH (без прав администратора) ----
  tool(
    'lan_toolkit_peer_list',
    'Показать список настроенных SSH-партнёров и их состояние (есть ли ключ, залиты ли скрипты, взведён ли приём).',
    { type: 'object', properties: {}, required: [] },
    () => ['-Action', 'peer-list'],
  );

  tool(
    'lan_toolkit_peer_test',
    'Проверить SSH-связь с партнёром (подключение, версия тулкита, хеш). Используй перед синхронизацией.',
    {
      type: 'object',
      properties: {
        peer: { type: 'string', description: 'Имя партнёра (например pc2).' },
      },
      required: ['peer'],
    },
    (a) => ['-Action', 'peer-test', '-Peer', a.peer],
  );

  tool(
    'lan_toolkit_peer_setup',
    'Полностью автоматически настроить SSH-партнёра: создать ключ тулкита, установить ключ на партнёра (попросит пароль), залить скрипты, взвести приём и проверить связь. Требует IP и логина партнёра.',
    {
      type: 'object',
      properties: {
        peer: { type: 'string', description: 'Имя партнёра (латиницей, например pc2).' },
        host: { type: 'string', description: 'IP или хост партнёра.' },
        user: { type: 'string', description: 'Логин на партнёре (по умолчанию текущий пользователь).' },
        platform: { type: 'string', enum: ['win', 'linux', 'android'], description: 'Система партнёра.' },
        token: { type: 'string', description: 'Опциональный код приёма на партнёре.' },
      },
      required: ['peer'],
    },
    (a) => {
      const r = ['-Action', 'peer-setup', '-Peer', a.peer];
      if (a.host) r.push('-PeerHost', a.host);
      if (a.user) r.push('-PeerUser', a.user);
      if (a.platform) r.push('-PeerPlatform', a.platform);
      if (a.token) r.push('-Token', a.token);
      return r;
    },
    300000,
  );

  tool(
    'lan_toolkit_peer_sync',
    'Двусторонне синхронизировать папку с партнёром по SSH. Инициатор заходит на партнёра и просит его сделать свою половину. Обе стороны должны иметь одинаковый тулкит.',
    {
      type: 'object',
      properties: {
        peer: { type: 'string', description: 'Имя партнёра.' },
        local: { type: 'string', description: 'Локальная папка (по умолчанию общая папка программы).' },
        remoteDir: { type: 'string', description: 'Папка на партнёре (по умолчанию то же имя).' },
        watch: { type: 'integer', description: 'Обновлять каждые N секунд (0 = один раз).' },
        token: { type: 'string', description: 'Код приёма, если на партнёре взведено.' },
      },
      required: ['peer'],
    },
    (a) => {
      const r = ['-Action', 'peer-sync', '-Peer', a.peer];
      if (a.local) r.push('-Local', a.local);
      if (a.remoteDir) r.push('-RemoteDir', a.remoteDir);
      if (a.watch) r.push('-Watch', String(a.watch));
      if (a.token) r.push('-Token', a.token);
      return r;
    },
  );

  // ---- Требуют прав администратора (вернут предупреждение, если не запущено от админа) ----
  tool(
    'lan_toolkit_setup',
    'Подготовить сеть: сделать профиль Private, открыть firewall, создать SMB-шару (папка обмена) и включить службы. Требует прав администратора — при вызове без прав вернёт предупреждение.',
    {
      type: 'object',
      properties: {
        path: { type: 'string', description: 'Папка для шары (по умолчанию C:\\Users\\Public\\LANShare).' },
        shareName: { type: 'string', description: 'Имя шары (по умолчанию LAN).' },
      },
      required: [],
    },
    (a) => {
      const r = ['-Action', 'setup'];
      if (a.path) r.push('-Path', a.path);
      if (a.shareName) r.push('-ShareName', a.shareName);
      return r;
    },
  );

  tool(
    'lan_toolkit_http',
    'Раздать папку через браузер (http://<IP>:<порт>). Телефон или Linux откроет ссылку и скачает файлы. Требует прав администратора.',
    {
      type: 'object',
      properties: {
        port: { type: 'integer', description: 'Порт (по умолчанию 8080).' },
      },
      required: [],
    },
    (a) => ['-Action', 'http', '-Port', String(a.port || 8080)],
  );
}

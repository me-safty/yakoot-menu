import { createWriteStream } from 'node:fs';
import { access, mkdir, rm } from 'node:fs/promises';
import { arch, platform } from 'node:os';
import { basename } from 'node:path';
import { pipeline } from 'node:stream/promises';
import { setTimeout as wait } from 'node:timers/promises';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const version = '0.38.2';
const targetDir = new URL('../.tools/', import.meta.url);
const zipPath = new URL('../.tools/pocketbase.zip', import.meta.url);

const platformMap = {
	darwin: 'darwin',
	linux: 'linux',
	win32: 'windows',
};

const archMap = {
	arm64: 'arm64',
	x64: 'amd64',
};

const pbPlatform = platformMap[platform()];
const pbArch = archMap[arch()];

if (!pbPlatform || !pbArch) {
	throw new Error(`Unsupported platform: ${platform()} ${arch()}`);
}

const binaryName = platform() === 'win32' ? 'pocketbase.exe' : 'pocketbase';
const binaryPath = new URL(`../.tools/${binaryName}`, import.meta.url);
const targetDirPath = fileURLToPath(targetDir);
const zipPathPath = fileURLToPath(zipPath);

const asset = `pocketbase_${version}_${pbPlatform}_${pbArch}.zip`;
const url = `https://github.com/pocketbase/pocketbase/releases/download/v${version}/${asset}`;

await mkdir(targetDir, { recursive: true });

try {
	await access(binaryPath);
	console.log(`PocketBase already installed at .tools/${binaryName}`);
	process.exit(0);
} catch {
	// install below
}

console.log(`Downloading ${asset}`);
const response = await fetch(url);
if (!response.ok || !response.body) {
	throw new Error(`Download failed: ${response.status} ${response.statusText}`);
}

await pipeline(response.body, createWriteStream(zipPath));

if (platform() === 'win32') {
	await new Promise((resolve, reject) => {
		const unzip = spawn(
			'powershell.exe',
			['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', `Expand-Archive -Force '${zipPathPath}' '${targetDirPath}'`],
			{ stdio: 'inherit' },
		);

		unzip.on('error', reject);
		unzip.on('close', (code) => {
			if (code === 0) resolve();
			else reject(new Error(`Expand-Archive exited ${code}`));
		});
	});
} else {
	await new Promise((resolve, reject) => {
		const unzip = spawn('unzip', ['-o', basename(zipPathPath), binaryName], {
			cwd: targetDirPath,
			stdio: 'inherit',
		});

		unzip.on('error', reject);
		unzip.on('close', (code) => {
			if (code === 0) resolve();
			else reject(new Error(`unzip exited ${code}`));
		});
	});
}

await rm(zipPath, { force: true });

if (platform() !== 'win32') {
	await new Promise((resolve, reject) => {
		const chmod = spawn('chmod', ['+x', binaryName], {
			cwd: targetDirPath,
			stdio: 'inherit',
		});

		chmod.on('error', reject);
		chmod.on('close', (code) => {
			if (code === 0) resolve();
			else reject(new Error(`chmod exited ${code}`));
		});
	});
}

await wait(10);
console.log(`PocketBase installed at .tools/${binaryName}`);

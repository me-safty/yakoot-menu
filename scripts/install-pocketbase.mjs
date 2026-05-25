import { createWriteStream } from 'node:fs';
import { mkdir, rm } from 'node:fs/promises';
import { arch, platform } from 'node:os';
import { basename } from 'node:path';
import { pipeline } from 'node:stream/promises';
import { setTimeout as wait } from 'node:timers/promises';
import { spawn } from 'node:child_process';

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

const asset = `pocketbase_${version}_${pbPlatform}_${pbArch}.zip`;
const url = `https://github.com/pocketbase/pocketbase/releases/download/v${version}/${asset}`;

await mkdir(targetDir, { recursive: true });

console.log(`Downloading ${asset}`);
const response = await fetch(url);
if (!response.ok || !response.body) {
	throw new Error(`Download failed: ${response.status} ${response.statusText}`);
}

await pipeline(response.body, createWriteStream(zipPath));

await new Promise((resolve, reject) => {
	const unzip = spawn('unzip', ['-o', basename(zipPath.pathname), 'pocketbase'], {
		cwd: targetDir.pathname,
		stdio: 'inherit',
	});

	unzip.on('error', reject);
	unzip.on('close', (code) => {
		if (code === 0) resolve();
		else reject(new Error(`unzip exited ${code}`));
	});
});

await rm(zipPath, { force: true });

await new Promise((resolve, reject) => {
	const chmod = spawn('chmod', ['+x', 'pocketbase'], {
		cwd: targetDir.pathname,
		stdio: 'inherit',
	});

	chmod.on('error', reject);
	chmod.on('close', (code) => {
		if (code === 0) resolve();
		else reject(new Error(`chmod exited ${code}`));
	});
});

await wait(10);
console.log('PocketBase installed at .tools/pocketbase');

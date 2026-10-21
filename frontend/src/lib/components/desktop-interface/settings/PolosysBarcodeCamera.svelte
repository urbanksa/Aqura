<script lang="ts">
	import { createEventDispatcher, onMount, onDestroy, tick } from 'svelte';
	const dispatch = createEventDispatcher<{ scan: string; close: void }>();
	let video: HTMLVideoElement;
	let dialog: HTMLDivElement;
	let closeButton: HTMLButtonElement;
	let stream: MediaStream | null = null;
	let timer: ReturnType<typeof setTimeout> | undefined;
	let active = true;
	let generation = 0;
	let starting = true;
	let error = '';
	type Detector = { detect: (source: HTMLCanvasElement | ImageData) => Promise<{ rawValue: string }[]> };
	const formats: Array<'ean_13' | 'ean_8' | 'upc_a' | 'upc_e' | 'code_128' | 'code_39'> = ['ean_13', 'ean_8', 'upc_a', 'upc_e', 'code_128', 'code_39'];

	function stopCamera() {
		generation++;
		clearTimeout(timer);
		stream?.getTracks().forEach(track => track.stop());
		stream = null;
		if (video) video.srcObject = null;
	}

	async function startCamera() {
		stopCamera();
		const current = generation;
		starting = true; error = '';
		try {
			if (!navigator.mediaDevices?.getUserMedia) throw new Error('Camera access is unavailable. Use HTTPS and a supported browser.');
			const acquired = await navigator.mediaDevices.getUserMedia({
				video: { facingMode: { ideal: 'environment' }, width: { ideal: 1280 }, height: { ideal: 720 } }, audio: false
			});
			if (!active || current !== generation) { acquired.getTracks().forEach(track => track.stop()); return; }
			stream = acquired;
			video.srcObject = stream;
			await video.play();
			let detector: Detector | undefined;
			const NativeDetector = (window as unknown as { BarcodeDetector?: new (options: { formats: string[] }) => Detector }).BarcodeDetector;
			if (NativeDetector) {
				try { detector = new NativeDetector({ formats }); } catch { /* Use the existing app polyfill. */ }
			}
			if (!detector) {
				const { BarcodeDetector } = await import('barcode-detector');
				detector = new BarcodeDetector({ formats }) as Detector;
			}
			if (!active || current !== generation) return;
			const canvas = document.createElement('canvas');
			const context = canvas.getContext('2d', { willReadFrequently: true });
			if (!context) throw new Error('Unable to read camera frames.');
			const reader = detector;
			starting = false;
			async function detectFrame() {
				if (!active || current !== generation) return;
				if (video.readyState >= 2 && video.videoWidth && video.videoHeight) {
					try {
						canvas.width = video.videoWidth; canvas.height = video.videoHeight;
						context!.drawImage(video, 0, 0, canvas.width, canvas.height);
						let codes: { rawValue: string }[];
						try { codes = await reader.detect(canvas); }
						catch { codes = await reader.detect(context!.getImageData(0, 0, canvas.width, canvas.height)); }
						if (!active || current !== generation) return;
						const barcode = codes.find(code => code.rawValue?.trim())?.rawValue.trim();
						if (barcode) { stopCamera(); dispatch('scan', barcode); return; }
					} catch { /* Keep scanning when a frame cannot be decoded. */ }
				}
				if (active && current === generation) timer = setTimeout(detectFrame, 250);
			}
			void detectFrame();
		} catch (failure) {
			if (!active || current !== generation) return;
			stopCamera(); starting = false;
			error = failure instanceof Error && failure.name === 'NotAllowedError'
				? 'Camera permission was denied. Allow camera access in your browser, then retry.'
				: failure instanceof Error && failure.name === 'NotFoundError'
					? 'No camera was found on this device.'
					: failure instanceof Error ? failure.message : 'Unable to open camera.';
		}
	}

	function onDialogKey(event: KeyboardEvent) {
		if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); dispatch('close'); }
		if (event.key === 'Tab') {
			const controls = [...dialog.querySelectorAll<HTMLButtonElement>('button:not(:disabled)')];
			const first = controls[0], last = controls[controls.length - 1];
			if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus(); }
			else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus(); }
		}
	}
	onMount(() => { void tick().then(() => closeButton?.focus()); void startCamera(); });
	onDestroy(() => { active = false; stopCamera(); });
</script>

<div class="camera-backdrop">
	<div class="camera-dialog" bind:this={dialog} role="dialog" aria-modal="true" aria-label="Scan product barcode" tabindex="-1" on:keydown={onDialogKey}>
		<header><h3>Scan product barcode</h3><button type="button" bind:this={closeButton} on:click={() => dispatch('close')}>Close</button></header>
		<video bind:this={video} autoplay muted playsinline aria-label="Live camera preview"></video>
		{#if error}<p class="camera-error" role="alert">{error}</p><button type="button" on:click={startCamera}>Retry camera</button>
		{:else}<p role="status">{starting ? 'Opening camera…' : 'Point the camera at the barcode. It will be scanned automatically.'}</p>{/if}
	</div>
</div>

<style>
	.camera-backdrop{position:fixed;inset:0;z-index:2000;display:flex;align-items:center;justify-content:center;padding:20px;background:#0f172ab3}
	.camera-dialog{box-sizing:border-box;width:100%;max-width:640px;max-height:100%;overflow:auto;background:white;color:#1e293b;padding:20px;border-radius:12px;box-shadow:0 20px 60px #0005}
	header{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:16px}h3{font-size:16px;margin:0}video{display:block;width:100%;max-height:50vh;object-fit:contain;background:#0f172a;border-radius:8px}p{font-size:14px;line-height:1.5;margin:14px 0 0}.camera-error{color:#b91c1c;margin-bottom:12px}button{border:1px solid #cbd5e1;border-radius:6px;padding:9px 14px;background:white;color:#334155;font:inherit;cursor:pointer}
</style>

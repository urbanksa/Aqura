<script lang="ts">
	import { createEventDispatcher } from 'svelte';
	import { supabase } from '$lib/utils/supabase';
	type UnitPrice = { unit_id: string; barcode: string; quantity_in_base_units: number; price: number };
	type BranchPrice = { branch_id: number; branch_name: string; purchase_price: number; sales_price: number; multi_units?: UnitPrice[]; fetched_at: string; saved_at: string };
	type PriceResult = { branchId: number; barcode: string; purchasePrice: number; salesPrice: number; fetchedAt: string; multiUnits: UnitPrice[] };
	type BatchProduct = { id: string; data: { name: string; barcode: string; multi_units?: { unit_id: string; barcode: string; quantity_in_base_units: number }[] } };
	const batchSize = 50;
	const concurrency = 3;
	export let disabled = false;
	export let busy = false;
	const dispatch = createEventDispatcher<{ saved: { productId: string; branchPrice: BranchPrice; selectedBranchId: number } }>();
	let open = false;
	let targetProductId = '';
	let targetProductName = '';
	let branches: { id: number; name: string }[] = [];
	let branchId = '';
	let loading = false;
	let running = false;
	let stopRequested = false;
	let phase: 'fetching' | 'saving' = 'fetching';
	let completed = 0;
	let total = 0;
	let error = '';
	let message = '';
	let batchErrors: Record<string, string> = {};
	let batchProducts: BatchProduct[] = [];
	let batchLoaded = false;
	let batchNumber = 1;
	let afterId = '';
	let snapshotTime = '';
	let hasMore = false;
	let overallCount = 0;
	let processedBefore = 0;
	let savedProductIds: string[] = [];
	let finished = false;
	let priceWarnings: string[] = [];
	$: failures = Object.values(batchErrors);
	$: busy = loading || running;
	const validPrice = (value: unknown): value is number => typeof value === 'number' && Number.isFinite(value) && value >= 0;

	function resetRun() {
		priceWarnings = [];
		batchErrors = {}; error = ''; message = ''; batchProducts = []; batchLoaded = false;
		batchNumber = 1; afterId = ''; snapshotTime = ''; hasMore = false; overallCount = 0;
		processedBefore = 0; savedProductIds = []; finished = false; stopRequested = false;
	}

	async function show() {
		if (busy) return;
		if (targetProductId) { open = false; resetRun(); }
		targetProductId = ''; targetProductName = '';
		open = !open;
		if (open) await loadBranches();
	}

	export async function showProduct(productId: string, productName: string, selectedBranch = '') {
		if (busy || disabled) return;
		resetRun();
		targetProductId = productId; targetProductName = productName;
		open = true;
		await loadBranches();
		branchId = branches.some(branch => String(branch.id) === selectedBranch) ? selectedBranch : '';
	}

	async function loadBranches() {
		if (branches.length) return;
		loading = true; error = '';
		try {
			const response = await fetch('/api/polosys-products/branch-prices');
			const result = await response.json();
			if (!response.ok) throw new Error(result.error || 'Unable to load branches.');
			branches = result.branches || [];
		} catch (failure) { error = failure instanceof Error ? failure.message : 'Unable to load branches.'; }
		finally { loading = false; }
	}

	async function requestPrices(body: Record<string, unknown>) {
		const response = await fetch('/api/polosys-products/branch-prices', {
			method: 'POST', headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify(body), signal: AbortSignal.timeout(50000)
		});
		const result = await response.json();
		if (!response.ok) throw new Error(result.error || 'The branch price request failed.');
		return result;
	}

	function recordFailure(product: BatchProduct, failure: unknown) {
		batchErrors = { ...batchErrors, [product.id]: `${product.data.name} (${product.data.barcode}): ${failure instanceof Error ? failure.message : 'Price request failed.'}` };
	}

	async function run() {
		if (!branchId || running || loading || disabled) return;
		if (finished) resetRun();
		running = true; stopRequested = false; error = ''; message = ''; batchErrors = {};
		const selectedBranch = Number(branchId);
		try {
			while (true) {
				if (!batchLoaded) {
					if (!snapshotTime) snapshotTime = new Date().toISOString();
					let query = supabase.from('Polosys_products').select('id, data', { count: 'exact' })
						.lte('created_at', snapshotTime).order('id').limit(batchSize);
					if (targetProductId) query = query.eq('id', targetProductId);
					if (afterId) query = query.gt('id', afterId);
					const { data, error: readError, count } = await query;
					if (readError) throw readError;
					batchProducts = (data || []) as BatchProduct[];
					if (!afterId) overallCount = count || 0;
					hasMore = (count || 0) > batchProducts.length;
					batchLoaded = true;
				}
				if (!batchProducts.length) { finished = true; break; }
				const products = batchProducts.filter(product => !savedProductIds.includes(product.id));
				const fetched: { product: BatchProduct; prices: PriceResult }[] = [];
				phase = 'fetching'; completed = 0; total = products.length;
				for (let offset = 0; offset < products.length; offset += concurrency) {
					await Promise.all(products.slice(offset, offset + concurrency).map(async product => {
						try {
							const result = await requestPrices({ action: 'fetch', productId: product.id, branchId: selectedBranch });
							const expected = product.data.multi_units || [];
							if (result.branchId !== selectedBranch || result.barcode !== product.data.barcode.trim() || !validPrice(result.purchasePrice) || !validPrice(result.salesPrice)
								|| typeof result.fetchedAt !== 'string' || !Number.isFinite(Date.parse(result.fetchedAt))
								|| !Array.isArray(result.multiUnits) || result.multiUnits.length > expected.length
								|| result.multiUnits.some((price: UnitPrice) => !price || !validPrice(price.price)
									|| result.multiUnits.filter((item: UnitPrice) => item?.unit_id === price.unit_id).length !== 1
									|| !expected.some(unit => price.unit_id === unit.unit_id && price.barcode === unit.barcode.trim() && price.quantity_in_base_units === unit.quantity_in_base_units))) throw new Error('Prices did not match the product units.');
							if (Array.isArray(result.warnings)) priceWarnings = [...new Set([...priceWarnings, ...result.warnings.filter((warning: unknown): warning is string => typeof warning === 'string').map((warning: string) => `${product.data.name}: ${warning}`)])];
							fetched.push({ product, prices: result });
						} catch (failure) { recordFailure(product, failure); }
						finally { completed += 1; }
					}));
				}
				// Save this batch automatically before loading any more products.
				phase = 'saving'; completed = 0; total = fetched.length;
				for (let offset = 0; offset < fetched.length; offset += concurrency) {
					await Promise.all(fetched.slice(offset, offset + concurrency).map(async ({ product, prices }) => {
						try {
							const result = await requestPrices({ action: 'save', productId: product.id, ...prices });
							savedProductIds = [...savedProductIds, product.id];
							dispatch('saved', { productId: product.id, ...result });
						} catch (failure) { recordFailure(product, failure); }
						finally { completed += 1; }
					}));
				}
				if (Object.keys(batchErrors).length) {
					message = 'Available prices were saved automatically. Paused on this batch because some products failed. Retry to process only its unsaved products.';
					break;
				}
				if (!hasMore) { finished = true; break; }
				if (stopRequested) { message = 'Stopped after saving the current batch. Resume to continue.'; break; }
				afterId = batchProducts[batchProducts.length - 1].id;
				processedBefore += batchProducts.length;
				batchNumber += 1; batchLoaded = false; batchProducts = []; savedProductIds = [];
			}
			if (finished) {
				message = '';
				open = false;
			}
		} catch (failure) { error = (failure as { message?: string })?.message || 'Unable to process product prices. Resume to retry.'; }
		finally { running = false; }
	}
</script>

<div class="table-pricing">
	<div class="pricing-toolbar">
		<slot name="toolbar" />
	<button type="button" disabled={disabled || busy} aria-expanded={open} on:click={show}>Get Price</button>
	</div>
	{#if finished && priceWarnings.length}<p role="status">Available prices saved. {priceWarnings.join(' ')}</p>{/if}
	{#if open}
		<div class="pricing-panel">
			{#if targetProductId}<p>Get prices for <strong>{targetProductName}</strong></p>{/if}
			{#if loading}<p role="status">Loading branches…</p>{:else}
				<div class="controls">
					<label>Branch<select bind:value={branchId} disabled={busy} on:change={resetRun}><option value="">Select branch</option>{#each branches as branch}<option value={String(branch.id)}>{branch.name}</option>{/each}</select></label>
					<button type="button" class="start" disabled={disabled || busy || !branchId} on:click={run}>{finished ? 'Fetch & save again' : batchLoaded || afterId ? 'Resume / retry' : targetProductId ? 'Fetch & auto-save' : 'Fetch & auto-save all'}</button>
					{#if running}<button type="button" disabled={stopRequested} on:click={() => stopRequested = true}>{stopRequested ? 'Stopping after batch…' : 'Stop after this batch'}</button>{/if}
				</div>
				{#if !branches.length}<p>No active ERP branches are configured.</p>{/if}
			{/if}
			{#if batchLoaded && !finished}<p role="status">Batch {batchNumber} · Up to 50 products per batch · Saved {processedBefore + savedProductIds.length} / {overallCount}</p>{/if}
			{#if running}<p role="status">{phase === 'saving' ? 'Auto-saving' : 'Fetching'} {completed} / {total} products in this batch…</p>{/if}
			{#if error}<p class="error" role="alert">{error}</p>{/if}
			{#if message}<p role="status">{message}</p>{/if}
			{#if failures.length}<details class="error"><summary>{failures.length} lookup or save error(s)</summary><ul>{#each failures as failure}<li>{failure}</li>{/each}</ul></details>{/if}
		</div>
	{/if}
</div>

<style>
	.table-pricing{flex-shrink:0;min-width:0}.pricing-panel{max-height:240px;overflow:auto;overscroll-behavior:contain}
	.pricing-toolbar{display:flex;align-items:end;gap:12px;flex-wrap:wrap}.pricing-toolbar>button{flex:none;white-space:nowrap}
	.table-pricing{margin:12px 0 20px}button{border:1px solid #cbd5e1;border-radius:6px;padding:9px 14px;background:white;color:#0e7490;font:inherit;cursor:pointer}button:disabled,select:disabled{opacity:.55;cursor:default}.pricing-panel{margin-top:12px;padding:16px;border:1px solid #cbd5e1;border-radius:8px;background:white}.controls{display:flex;gap:12px;align-items:end;flex-wrap:wrap}label{display:flex;flex-direction:column;gap:6px}select{box-sizing:border-box;padding:8px;border:1px solid #cbd5e1;border-radius:5px;background:white;color:#0f172a;font:inherit;min-width:220px;max-width:100%}.start{background:#0e7490;color:white;border-color:#0e7490}p{margin:12px 0;font-size:13px}.error{color:#b91c1c;margin-top:12px}
</style>

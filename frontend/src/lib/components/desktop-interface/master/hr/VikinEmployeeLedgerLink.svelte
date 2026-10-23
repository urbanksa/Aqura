<script lang="ts">
	import { createEventDispatcher, onMount, onDestroy } from 'svelte';
	import { supabase } from '$lib/utils/supabase';
	import { currentLocale } from '$lib/i18n';
	import { loadVikinEmployeeLink, saveVikinEmployeeLink, type VikinEmployeeLinkContext } from '$lib/utils/vikinEmployeeLedgerLink';

	export let employeeId: string;
	const dispatch = createEventDispatcher<{
		statechange: { employeeId: string; context: VikinEmployeeLinkContext | null; busy: boolean };
	}>();
	let context: VikinEmployeeLinkContext | null = null;
	let search = '';
	let selectedLedgerId: string | null = null;
	let loading = false;
	let saving = false;
	let error = '';
	let success = '';
	let request = 0;
	$: isArabic = $currentLocale === 'ar';
	$: companyName = context ? (isArabic ? context.company.name_ar || context.company.name_en : context.company.name_en || context.company.name_ar) : '';
	$: filteredLedgers = (context?.ledgers || []).filter(ledger =>
		[ledger.ledger_code, ledger.ledger_name, ledger.account_group_name].some(value => value.toLocaleLowerCase().includes(search.trim().toLocaleLowerCase())));
	$: selectedLedger = context?.ledgers.find(ledger => ledger.id === selectedLedgerId);
	$: dispatch('statechange', { employeeId, context, busy: loading || saving });

	onMount(load);
	onDestroy(() => { request++; });

	export async function removeLink() {
		await save(null);
	}

	async function load() {
		const current = ++request;
		loading = true;
		error = '';
		success = '';
		try {
			const result = await loadVikinEmployeeLink(supabase, employeeId);
			if (current !== request) return;
			context = result;
			selectedLedgerId = result.link?.ledger_id || null;
		} catch (cause) {
			if (current === request) error = cause instanceof Error ? cause.message : 'Unable to load Vikin ledgers.';
		} finally {
			if (current === request) loading = false;
		}
	}

	async function save(ledgerId: string | null) {
		if (!context || loading || saving) return;
		if (ledgerId && !context.ledgers.some(ledger => ledger.id === ledgerId)) return;
		const current = ++request;
		saving = true;
		error = '';
		success = '';
		try {
			const result = await saveVikinEmployeeLink(supabase, employeeId, ledgerId);
			if (current !== request) return;
			context = result;
			selectedLedgerId = result.link?.ledger_id || null;
			success = ledgerId ? (isArabic ? 'تم حفظ ربط حساب فيكن.' : 'Vikin ledger link saved.') : (isArabic ? 'تمت إزالة الربط.' : 'Vikin ledger link removed.');
		} catch (cause) {
			if (current === request) error = cause instanceof Error ? cause.message : 'Unable to save the Vikin ledger link.';
		} finally {
			if (current === request) saving = false;
		}
	}
</script>

<div class="vikin-link">
	<h3>{isArabic ? 'حساب الموظف في فيكن' : 'Vikin Employee Ledger'}</h3>
	{#if loading}
		<div class="notice">{isArabic ? 'جارٍ تحميل الحسابات...' : 'Loading company ledgers...'}</div>
	{:else if context}
		<div class="company"><span>{isArabic ? 'الشركة' : 'Company'}</span><strong>{companyName}</strong></div>
		<p class="hint">{isArabic ? 'اختر حساب الموظف لحفظ الربط لتخطيط القيود لاحقاً.' : 'Select the employee’s ledger to save its link for later entry planning.'}</p>
		<div class="search-row">
			<input type="search" bind:value={search} disabled={saving} aria-label={isArabic ? 'البحث في حسابات فيكن' : 'Search Vikin ledgers'} placeholder={isArabic ? 'ابحث بالاسم أو الرمز أو المجموعة...' : 'Search ledger name, code or account group...'} on:input={() => { selectedLedgerId = null; success = ''; }} />
			<button on:click={load} disabled={saving} aria-label={isArabic ? 'تحديث حسابات فيكن' : 'Refresh Vikin ledgers'}>↻</button>
		</div>
		<div class="columns"><span>{isArabic ? 'الرمز' : 'Code'}</span><span>{isArabic ? 'اسم الحساب' : 'Ledger Name'}</span><span>{isArabic ? 'مجموعة الحساب' : 'Account Group'}</span></div>
		<div class="ledgers">
			{#each filteredLedgers as ledger (ledger.id)}
				<button class="ledger" class:selected={selectedLedgerId === ledger.id} on:click={() => { selectedLedgerId = ledger.id; success = ''; error = ''; }} disabled={saving}>
					<span class="code">{ledger.ledger_code}</span><span>{ledger.ledger_name}</span><span class="group">{ledger.account_group_name}</span>
				</button>
			{:else}
				<div class="notice">{context.ledgers.length ? (isArabic ? 'لا توجد حسابات مطابقة.' : 'No matching ledgers.') : (isArabic ? 'قم بمزامنة حسابات هذه الشركة من المساعد أولاً.' : 'Sync this company’s Vikin ledgers from the Assistant first.')}</div>
			{/each}
		</div>
		{#if selectedLedger}
			<div class="selection"><strong>{selectedLedger.ledger_code} — {selectedLedger.ledger_name}</strong><button class="save" on:click={() => save(selectedLedgerId)} disabled={saving || context.link?.ledger_id === selectedLedgerId}>{saving ? (isArabic ? 'جارٍ الحفظ...' : 'Saving...') : (isArabic ? 'ربط الحساب' : 'Link Ledger')}</button></div>
		{/if}
	{/if}
	{#if error}<div class="error">{error}</div>{/if}
	{#if success}<div class="success">{success}</div>{/if}
	{#if !loading && !context}<button on:click={load}>{isArabic ? 'إعادة المحاولة' : 'Retry'}</button>{/if}
</div>

<style>
	.vikin-link { display: flex; flex-direction: column; flex: 1; min-height: 0; gap: 8px; font-size: 12px; }
	h3 { margin: 0; color: #2563eb; font-size: 12px; text-transform: uppercase; }
	.company { display: flex; gap: 12px; padding: 8px 10px; border: 1px solid #bfdbfe; border-radius: 7px; background: #eff6ff; }
	.company span, .hint, .group { color: #64748b; }
	.hint { margin: 0; font-size: 11px; }
	.search-row { display: flex; gap: 6px; }
	input { flex: 1; min-width: 0; padding: 8px; border: 1px solid #cbd5e1; border-radius: 6px; }
	button { cursor: pointer; border: 1px solid #cbd5e1; background: #fff; border-radius: 5px; padding: 6px 10px; }
	button:disabled { cursor: default; opacity: .55; }
	.columns, .ledger { display: grid; grid-template-columns: 85px minmax(0, 1fr) minmax(110px, .55fr); gap: 8px; align-items: center; text-align: start; }
	.columns { padding: 7px 10px; background: #f1f5f9; color: #475569; font-weight: 700; }
	.ledgers { flex: 1; min-height: 120px; overflow-y: auto; border: 1px solid #e2e8f0; border-radius: 7px; }
	.ledger { width: 100%; border: 0; border-bottom: 1px solid #f1f5f9; border-radius: 0; }
	.ledger:hover { background: #f8fafc; }
	.ledger.selected { background: #dbeafe; }
	.code { color: #1d4ed8; font-weight: 700; }
	.selection { display: flex; align-items: center; justify-content: space-between; gap: 8px; padding: 8px; background: #eff6ff; border-radius: 6px; }
	.save { color: #fff; background: #2563eb; border-color: #2563eb; font-weight: 700; }
	.notice { padding: 14px; color: #64748b; }
	.error { color: #b91c1c; padding: 8px; background: #fef2f2; border-radius: 5px; }
	.success { color: #15803d; padding: 8px; background: #f0fdf4; border-radius: 5px; }
</style>

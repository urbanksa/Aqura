<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { locale, _ as t } from '$lib/i18n';
	import { supabase } from '$lib/utils/supabase';
	type Company = { id: number; name_en: string; name_ar: string };
	type Branch = Company;
	type Ledger = { id: string; company_id: number; ledger_name: string; ledger_code: string; account_group_name: string };
	type Link = { company_id: number; branch_id?: number; ledger_id: string; ledger_name: string; ledger_code: string };
	let companies: Company[] = [];
	let branches: Branch[] = [];
	let ledgers: Ledger[] = [];
	let adjustments: Link[] = [];
	let banks: Link[] = [];
	let loading = true;
	let saving = false;
	let error = '';
	let pickerError = '';
	let kind: 'adjustment' | 'bank' | '' = '';
	let branchId = '';
	let companyId = '';
	let companySearch = '';
	let ledgerSearch = '';
	let ledgerId = '';
	let disposed = false;
	const isBank = (group: string) => /(^|\s)banks?(\s|$)|بنك|بنوك/i.test(group.trim());
	const name = (item: Company | undefined) => item ? ($locale === 'ar' ? item.name_ar || item.name_en : item.name_en || item.name_ar) : '—';
	$: filteredCompanies = companies.filter(item => [item.name_en, item.name_ar].some(value => (value || '').toLowerCase().includes(companySearch.trim().toLowerCase())));
	$: filteredLedgers = ledgers.filter(item => String(item.company_id) === companyId && (kind !== 'bank' || isBank(item.account_group_name))
		&& [item.ledger_name, item.ledger_code, item.account_group_name].some(value => value.toLowerCase().includes(ledgerSearch.trim().toLowerCase())));
	$: selectedLedger = filteredLedgers.find(item => item.id === ledgerId);
	$: title = kind === 'bank' ? $t('reports.salaryVikinSalaryBank') : $t('reports.salaryVikinBranchAdjustment');
	onMount(load);
	onDestroy(() => { disposed = true; });
	function apply(data: { companies: Company[]; branches: Branch[]; ledgers: Ledger[]; adjustments: Link[]; banks: Link[] }) {
		companies = data.companies; branches = data.branches; ledgers = data.ledgers;
		adjustments = data.adjustments; banks = data.banks;
	}
	async function load() {
		try {
			const result = await supabase.rpc('get_salary_vikin_ledger_accounts');
			if (result.error) throw result.error;
			if (!disposed) apply(result.data);
		} catch (cause) { if (!disposed) error = (cause as { message?: string }).message || $t('reports.salaryLedgerLoadError'); }
		finally { if (!disposed) loading = false; }
	}
	function open(value: 'adjustment' | 'bank', link?: Link) {
		kind = value; companySearch = ''; ledgerSearch = ''; pickerError = '';
		branchId = link?.branch_id == null ? '' : String(link.branch_id);
		companyId = link ? String(link.company_id) : '';
		ledgerId = link?.ledger_id || '';
	}
	function chooseExisting() {
		ledgerSearch = ''; pickerError = '';
		const link = (kind === 'bank' ? banks : adjustments).find(item => String(item.company_id) === companyId && (kind === 'bank' || String(item.branch_id) === branchId));
		ledgerId = link?.ledger_id || '';
	}
	async function save() {
		if (!kind || !selectedLedger || !companyId || (kind === 'adjustment' && !branchId) || saving) return;
		saving = true; pickerError = '';
		try {
			const result = await supabase.rpc('set_salary_vikin_ledger_account', {
				p_kind: kind, p_company_id: Number(companyId), p_branch_id: kind === 'adjustment' ? Number(branchId) : null, p_ledger_id: selectedLedger.id
			});
			if (result.error) throw result.error;
			if (!disposed) { apply(result.data); kind = ''; }
		} catch (cause) { if (!disposed) pickerError = (cause as { message?: string }).message || $t('reports.salaryLedgerSaveError'); }
		finally { if (!disposed) saving = false; }
	}
</script>

<div class="p-5 space-y-6">
	{#if loading}<p>{$t('common.loading')}</p>
	{:else if error}<p role="alert" class="text-red-700">{error}</p>
	{:else}
		{#each ['adjustment', 'bank'] as section}
			<section class="border border-slate-200 rounded-lg overflow-hidden">
				<div class="p-4 flex justify-between items-center bg-slate-50">
					<h3 class="font-bold">{$t(section === 'bank' ? 'reports.salaryVikinSalaryBank' : 'reports.salaryVikinBranchAdjustment')}</h3>
					<button type="button" on:click={() => open(section === 'bank' ? 'bank' : 'adjustment')} aria-label={$t(section === 'bank' ? 'reports.salaryVikinSalaryBank' : 'reports.salaryVikinBranchAdjustment')} class="w-8 h-8 bg-blue-600 text-white rounded-lg text-xl font-bold">+</button>
				</div>
				{#if section === 'bank'}<p class="px-4 py-2 text-sm text-slate-500">{$t('reports.salaryOneVikinBankAccount')}</p>{/if}
				<table class="w-full text-sm text-start">
					<thead class="text-slate-600 bg-slate-50"><tr>{#if section !== 'bank'}<th class="p-3 text-start">{$t('hr.branch')}</th>{/if}<th class="p-3 text-start">{$t('reports.salarySponsorCompany')}</th><th class="p-3 text-start">{$t('reports.salaryPostingLedgers')}</th><th class="p-3"></th></tr></thead>
					<tbody>
						{#each (section === 'bank' ? banks : adjustments) as link}
							<tr class="border-t border-slate-100">{#if section !== 'bank'}<td class="p-3">{name(branches.find(item => Number(item.id) === Number(link.branch_id)))}</td>{/if}<td class="p-3">{name(companies.find(item => Number(item.id) === Number(link.company_id)))}</td><td class="p-3"><span class="font-mono">{link.ledger_code}</span> — {link.ledger_name}</td><td class="p-3"><button type="button" on:click={() => open(section === 'bank' ? 'bank' : 'adjustment', link)} class="px-3 py-1 border rounded text-blue-700">{$t('common.edit')}</button></td></tr>
						{:else}<tr><td colspan={section === 'bank' ? 3 : 4} class="p-4 text-slate-500">{$t('reports.salaryVikinNoLedgerLinks')}</td></tr>{/each}
					</tbody>
				</table>
			</section>
		{/each}
	{/if}
</div>

{#if kind}
	<div class="absolute inset-0 z-[100] bg-black/40 flex items-center justify-center p-6" dir={$locale === 'ar' ? 'rtl' : 'ltr'}>
		<section role="dialog" aria-modal="true" aria-label={title} class="w-full max-w-3xl max-h-full bg-white rounded-xl p-5 flex flex-col gap-4 overflow-hidden">
			<div class="flex justify-between items-center"><h3 class="font-bold text-lg">{title}</h3><button type="button" disabled={saving} on:click={() => kind = ''} aria-label={$t('common.close')} class="p-2">×</button></div>
			{#if kind === 'adjustment'}<label class="text-sm font-semibold">{$t('hr.branch')}<select bind:value={branchId} on:change={chooseExisting} disabled={saving} class="block mt-1 w-full border rounded p-2"><option value="">{$t('reports.salarySelectBranch')}</option>{#each branches as branch}<option value={String(branch.id)}>{name(branch)}</option>{/each}</select></label>{/if}
			<label class="text-sm font-semibold">{$t('reports.salarySponsorCompany')}<input type="search" bind:value={companySearch} disabled={saving} placeholder={$t('reports.salarySearchVikinCompany')} class="block mt-1 w-full border rounded p-2" />
				<select bind:value={companyId} on:change={chooseExisting} disabled={saving || (kind === 'adjustment' && !branchId)} class="block mt-2 w-full border rounded p-2"><option value="">{$t('reports.salarySelectVikinCompany')}</option>{#each companies.filter(item => String(item.id) === companyId || filteredCompanies.some(match => match.id === item.id)) as company}<option value={String(company.id)}>{name(company)}</option>{/each}</select>
			</label>
			{#if kind === 'bank'}<p class="text-sm text-slate-500">{$t('reports.salaryOneVikinBankAccount')}</p>{/if}
			<input type="search" bind:value={ledgerSearch} disabled={saving || !companyId} placeholder={$t('reports.salarySearchLedger')} aria-label={$t('reports.salarySearchLedger')} class="w-full border rounded p-2" />
			{#if pickerError}<p role="alert" class="text-red-700 text-sm">{pickerError}</p>{/if}
			<div class="min-h-0 overflow-auto border rounded">
				{#each filteredLedgers as ledger (ledger.id)}<button type="button" disabled={saving} aria-pressed={ledgerId === ledger.id} on:click={() => ledgerId = ledger.id} class="w-full p-3 text-start border-b hover:bg-blue-50 {ledgerId === ledger.id ? 'bg-blue-100' : ''}"><strong class="font-mono">{ledger.ledger_code}</strong> — {ledger.ledger_name}<span class="block text-xs text-slate-500">{ledger.account_group_name}</span></button>
				{:else}<p class="p-4 text-sm text-slate-500">{$t('reports.salaryVikinNoSyncedLedgers')}</p>{/each}
			</div>
			<div class="flex justify-end gap-2"><button type="button" disabled={saving} on:click={() => kind = ''} class="px-4 py-2 bg-slate-100 rounded">{$t('hr.salaryStatement.cancel')}</button><button type="button" on:click={save} disabled={saving || !selectedLedger || (kind === 'adjustment' && !branchId)} class="px-4 py-2 bg-blue-600 text-white rounded disabled:opacity-50">{saving ? $t('common.loading') : $t('common.save')}</button></div>
		</section>
	</div>
{/if}

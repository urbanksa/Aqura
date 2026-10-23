<script lang="ts">
	import { _ as t, locale } from '$lib/i18n';
	import { onMount, onDestroy } from 'svelte';
	import { supabase } from '$lib/utils/supabase';
	import SalaryVikinLedgerAccounts from './SalaryVikinLedgerAccounts.svelte';

	type Branch = { branch_id: number; branch_name: string };
	type Ledger = { LedgerID: number; LedgerCode: string | number; LedgerName: string };
	type Mapping = { branch_id: number; deduction_key: string; erp_ledger_id: number; ledger_code: string; ledger_name: string };
	type SponsorCompany = { id: number; name_en: string; name_ar: string; erp_provider: 'polosys' | 'vikin' | null };
	type CompanyBranch = { id: number; company_id: number; name_en: string; name_ar: string };
	type SponsorBank = { company_id: number; branch_id: number; erp_ledger_id: number; ledger_code: string; ledger_name: string };
	let companyBranches: CompanyBranch[] = [];
	let sponsorBanks: SponsorBank[] = [];
	let sponsorAdjustments: SponsorBank[] = [];
	let activeSponsor: SponsorCompany | null = null;
	let sponsorCompanies: SponsorCompany[] = [];
	let sponsorsLoading = true;
	let sponsorsError = '';
	let branches: Branch[] = [];
	let mappings: Mapping[] = [];
	let activeDeduction = '';
	let branchId = '';
	let search = '';
	let ledgers: Ledger[] = [];
	let selectedLedger: Ledger | null = null;
	let loading = false;
	let saving = false;
	let error = '';
	let pageError = '';
	let requestId = 0;
	let accountTab: 'deductions' | 'main' | 'sponsors' | 'adjustments' | 'vikin' = 'deductions';
	$: isAdjustmentPicker = activeDeduction === 'sponsorAdjustment';
	$: visibleSponsors = accountTab === 'adjustments' ? sponsorCompanies.filter(company => company.erp_provider === 'vikin') : sponsorCompanies;
	$: filteredLedgers = ledgers.filter(ledger =>
		[ledger.LedgerName, ledger.LedgerCode].some(value => String(value ?? '').toLowerCase().includes(search.trim().toLowerCase())));
	$: pickerBranches = isAdjustmentPicker
		? branches.filter(branch => companyBranches.some(item => Number(item.id) === Number(branch.branch_id) && sponsorCompanies.some(company => Number(company.id) === Number(item.company_id) && company.erp_provider === 'polosys')))
		: activeSponsor
		? companyBranches.filter(branch => Number(branch.company_id) === Number(activeSponsor?.id)).map(branch => ({ branch_id: branch.id, branch_name: $locale === 'ar' ? branch.name_ar || branch.name_en : branch.name_en || branch.name_ar }))
		: branches;

	function sponsorBranchName(id: number, language: string) {
		const branch = companyBranches.find(branch => Number(branch.id) === Number(id));
		return branch ? (language === 'ar' ? branch.name_ar || branch.name_en : branch.name_en || branch.name_ar) : String(id);
	}

	onMount(async () => {
		const [branchResult, mappingResult, sponsorResult, companyBranchResult, sponsorBankResult, adjustmentResult] = await Promise.all([
			supabase.from('erp_connections').select('branch_id, branch_name').eq('is_active', true).order('branch_id'),
			supabase.from('salary_deduction_posting_accounts').select('branch_id, deduction_key, erp_ledger_id, ledger_code, ledger_name'),
			supabase.from('company_master').select('id, name_en, name_ar, erp_provider').order('name_en'),
			supabase.from('branches').select('id, company_id, name_en, name_ar').eq('is_active', true).order('name_en'),
			supabase.from('salary_sponsor_bank_accounts').select('company_id, branch_id, erp_ledger_id, ledger_code, ledger_name'),
			supabase.from('salary_company_adjustment_accounts').select('company_id, branch_id, erp_ledger_id, ledger_code, ledger_name')
		]);
		branches = branchResult.data || [];
		mappings = mappingResult.data || [];
		pageError = branchResult.error?.message || mappingResult.error?.message || '';
		sponsorCompanies = sponsorResult.data || [];
		companyBranches = companyBranchResult.data || [];
		sponsorBanks = sponsorBankResult.data || [];
		sponsorAdjustments = adjustmentResult.data || [];
		sponsorsError = sponsorResult.error?.message || companyBranchResult.error?.message || sponsorBankResult.error?.message || adjustmentResult.error?.message || '';
		sponsorsLoading = false;
	});
	onDestroy(() => { requestId++; });

	function openPicker(key: string) {
		activeSponsor = null;
		activeDeduction = key;
		branchId = '';
		search = '';
		ledgers = [];
		selectedLedger = null;
		error = '';
		loading = false;
		requestId++;
	}
	function openSponsorBank(company: SponsorCompany) {
		if (company.erp_provider !== 'polosys') return;
		openPicker('sponsorBank');
		activeSponsor = company;
		const existing = sponsorBanks.find(item => Number(item.company_id) === Number(company.id));
		if (existing) {
			branchId = String(existing.branch_id);
			loadLedgers();
		}
	}
	function openSponsorAdjustment(company: SponsorCompany) {
		if (company.erp_provider !== 'vikin') return;
		openPicker('sponsorAdjustment');
		activeSponsor = company;
	}
	function closePicker() {
		if (saving) return;
		activeDeduction = '';
		requestId++;
	}
	async function loadLedgers() {
		const current = ++requestId;
		ledgers = [];
		search = '';
		selectedLedger = null;
		error = '';
		loading = !!branchId;
		if (!branchId) return;
		try {
			const groupFilter = isAdjustmentPicker ? '' : activeSponsor ? '&bankOnly=true' : ['foodAllowanceDeduction', 'gosiDeduction', 'mainSalaryAccount', 'nonSponsorshipSalaryAccount'].includes(activeDeduction) ? '' : '&indirectIncomeOnly=true';
			const response = await fetch(`/api/erp-ledger-search?branchId=${branchId}${groupFilter}`, { signal: AbortSignal.timeout(20000) });
			const data = await response.json();
			if (current !== requestId) return;
			if (!response.ok || !data.success) throw new Error(data.error || $t('reports.salaryLedgerLoadError'));
			ledgers = data.ledgers || [];
			const existing = activeSponsor
				? (isAdjustmentPicker ? sponsorAdjustments : sponsorBanks).find(item => Number(item.company_id) === Number(activeSponsor?.id) && String(item.branch_id) === branchId)
				: mappings.find(item => String(item.branch_id) === branchId && item.deduction_key === activeDeduction);
			selectedLedger = ledgers.find(item => Number(item.LedgerID) === Number(existing?.erp_ledger_id)) || null;
		} catch (e) {
			if (current === requestId) error = e instanceof Error ? e.message : $t('reports.salaryLedgerLoadError');
		} finally {
			if (current === requestId) loading = false;
		}
	}
	async function saveSelection() {
		if (!selectedLedger || !branchId || saving || loading) return;
		saving = true;
		error = '';
		if (activeSponsor) {
			try {
				if (activeSponsor.erp_provider !== (isAdjustmentPicker ? 'vikin' : 'polosys') || !pickerBranches.some(branch => String(branch.branch_id) === branchId)) throw new Error($t('reports.salarySponsorBranchRequired'));
				const mapping: SponsorBank = { company_id: Number(activeSponsor.id), branch_id: Number(branchId), erp_ledger_id: Number(selectedLedger.LedgerID), ledger_code: String(selectedLedger.LedgerCode ?? ''), ledger_name: selectedLedger.LedgerName };
				const { error: saveError } = await supabase.from(isAdjustmentPicker ? 'salary_company_adjustment_accounts' : 'salary_sponsor_bank_accounts').upsert({ ...mapping, updated_at: new Date().toISOString() }, { onConflict: isAdjustmentPicker ? 'company_id,branch_id' : 'company_id' });
				if (saveError) throw saveError;
				if (isAdjustmentPicker) sponsorAdjustments = [...sponsorAdjustments.filter(item => !(Number(item.company_id) === mapping.company_id && Number(item.branch_id) === mapping.branch_id)), mapping];
				else sponsorBanks = [...sponsorBanks.filter(item => Number(item.company_id) !== mapping.company_id), mapping];
				activeDeduction = '';
				activeSponsor = null;
			} catch (e) {
				error = (e as { message?: string })?.message || $t('reports.salaryLedgerSaveError');
			} finally { saving = false; }
			return;
		}
		const mapping: Mapping = {
			branch_id: Number(branchId), deduction_key: activeDeduction,
			erp_ledger_id: Number(selectedLedger.LedgerID),
			ledger_code: String(selectedLedger.LedgerCode ?? ''), ledger_name: selectedLedger.LedgerName
		};
		try {
			const { error: saveError } = await supabase.from('salary_deduction_posting_accounts')
				.upsert({ ...mapping, updated_at: new Date().toISOString() }, { onConflict: 'branch_id,deduction_key' });
			if (saveError) throw saveError;
			mappings = [...mappings.filter(item => !(Number(item.branch_id) === mapping.branch_id && item.deduction_key === mapping.deduction_key)), mapping];
			activeDeduction = '';
		} catch (e) {
			error = e instanceof Error ? e.message : (e as { message?: string })?.message || $t('reports.salaryLedgerSaveError');
		} finally {
			saving = false;
		}
	}

	function accountLabelKey(key: string) {
		if (key === 'nonSponsorshipSalaryAccount') return 'reports.salaryNonSponsorshipAccount';
		return key === 'mainSalaryAccount' ? 'reports.salaryMainAccount' : `hr.salaryStatement.${key}`;
	}

	const deductionKeys = [
		'gosiDeduction',
		'lateDeductions',
		'underWorkedDeductions',
		'incompleteDeductions',
		'unapprovedLeaveDeductions',
		'penaltiesDeductions',
		'otherDeductions',
		'foodAllowanceDeduction',
		'mainSalaryAccount',
		'nonSponsorshipSalaryAccount'
	];
	$: visibleAccountKeys = accountTab === 'deductions' ? deductionKeys.slice(0, 8) : deductionKeys.slice(8);
</script>

<div class="flex-1 min-h-0 p-6" dir={$locale === 'ar' ? 'rtl' : 'ltr'}>
	<div class="h-full bg-white rounded-xl border border-slate-200 flex flex-col overflow-hidden">
		<h2 class="p-5 text-lg font-bold text-slate-800 border-b border-slate-200">{$t('reports.manageSalaryAccounts')}</h2>
		<nav class="flex gap-2 px-5 py-3 border-b border-slate-200" aria-label={$t('reports.manageSalaryAccounts')}>
			<button type="button" aria-pressed={accountTab === 'deductions'} on:click={() => accountTab = 'deductions'} class="px-4 py-2 rounded-lg text-sm font-bold {accountTab === 'deductions' ? 'bg-blue-600 text-white' : 'bg-slate-100 text-slate-600 hover:bg-slate-200'}">
				{$t('hr.salaryStatement.deductions')}
			</button>
			<button type="button" aria-pressed={accountTab === 'main'} on:click={() => accountTab = 'main'} class="px-4 py-2 rounded-lg text-sm font-bold {accountTab === 'main' ? 'bg-blue-600 text-white' : 'bg-slate-100 text-slate-600 hover:bg-slate-200'}">
				{$t('reports.salaryMainAccounts')}
			</button>
			<button type="button" aria-pressed={accountTab === 'sponsors'} on:click={() => accountTab = 'sponsors'} class="px-4 py-2 rounded-lg text-sm font-bold {accountTab === 'sponsors' ? 'bg-blue-600 text-white' : 'bg-slate-100 text-slate-600 hover:bg-slate-200'}">
				{$t('reports.salarySponsors')}
			</button>
			<button type="button" aria-pressed={accountTab === 'adjustments'} on:click={() => accountTab = 'adjustments'} class="px-4 py-2 rounded-lg text-sm font-bold {accountTab === 'adjustments' ? 'bg-blue-600 text-white' : 'bg-slate-100 text-slate-600 hover:bg-slate-200'}">
				{$t('reports.salaryCompanyAdjustmentAccounts')}
			</button>
			<button type="button" aria-pressed={accountTab === 'vikin'} on:click={() => accountTab = 'vikin'} class="px-4 py-2 rounded-lg text-sm font-bold {accountTab === 'vikin' ? 'bg-blue-600 text-white' : 'bg-slate-100 text-slate-600 hover:bg-slate-200'}">{$t('reports.salaryVikinLedgerLinks')}</button>
		</nav>
		{#if pageError}<p class="px-5 py-3 text-sm text-red-700" role="alert">{pageError}</p>{/if}
		<div class="flex-1 min-h-0 overflow-auto">
			{#if accountTab === 'vikin'}
				<SalaryVikinLedgerAccounts />
			{:else if accountTab === 'sponsors' || accountTab === 'adjustments'}
				<table class="w-full text-sm text-start">
					<thead class="sticky top-0 bg-slate-100 text-slate-700"><tr>
						<th class="px-5 py-3 text-start">{$t('reports.salarySponsorCompany')}</th>
						<th class="px-5 py-3 text-start">{$t('reports.salaryCompanyErpProvider')}</th>
						<th class="px-5 py-3 text-start">{$t(accountTab === 'adjustments' ? 'reports.salaryPostingLedgers' : 'reports.salarySponsorBankAccounts')}</th>
						<th class="w-20 px-5 py-3"></th>
					</tr></thead>
					<tbody class="divide-y divide-slate-100">
						{#if sponsorsLoading}<tr><td colspan="4" class="px-5 py-6 text-slate-500">{$t('common.loading')}</td></tr>
						{:else if sponsorsError}<tr><td colspan="4" class="px-5 py-6 text-red-700" role="alert">{sponsorsError}</td></tr>
						{:else if visibleSponsors.length === 0}<tr><td colspan="4" class="px-5 py-6 text-slate-500">{$t('reports.salaryNoSponsorCompanies')}</td></tr>
						{:else}
							{#each visibleSponsors as company (company.id)}
								<tr class="even:bg-slate-50">
									<td class="px-5 py-3 font-medium text-slate-800">{$locale === 'ar' ? company.name_ar || company.name_en : company.name_en || company.name_ar}</td>
									<td class="px-5 py-3 text-slate-600">{company.erp_provider === 'polosys' ? 'Polosys' : company.erp_provider === 'vikin' ? 'Vikin' : $t('reports.salaryCompanyErpNotLinked')}</td>
									<td class="px-5 py-3 text-slate-600">
										{#each (accountTab === 'adjustments' ? sponsorAdjustments : sponsorBanks).filter(item => Number(item.company_id) === Number(company.id)) as mapping (mapping.branch_id)}
											<div class="py-1">{sponsorBranchName(mapping.branch_id, $locale)}: <span class="font-mono">{mapping.ledger_code}</span> — {mapping.ledger_name}</div>
										{/each}
									</td>
									<td class="px-5 py-3">
										{#if accountTab === 'adjustments'}
											<button type="button" on:click={() => openSponsorAdjustment(company)} aria-label={`${$t('reports.salarySelectPostingLedger')}: ${$locale === 'ar' ? company.name_ar : company.name_en}`} class="w-8 h-8 bg-blue-600 hover:bg-blue-700 text-white rounded-lg text-xl font-bold">+</button>
										{:else if company.erp_provider === 'polosys'}
											<button type="button" on:click={() => openSponsorBank(company)} aria-label={`${$t('reports.salarySelectBankAccount')}: ${$locale === 'ar' ? company.name_ar : company.name_en}`} class="w-8 h-8 bg-blue-600 hover:bg-blue-700 text-white rounded-lg text-xl font-bold">+</button>
										{/if}
									</td>
								</tr>
							{/each}
						{/if}
					</tbody>
				</table>
			{:else}
			<table class="w-full text-sm text-start">
				<thead class="sticky top-0 bg-slate-100 text-slate-700">
					<tr>
						<th class="w-16 px-5 py-3 text-start">#</th>
						<th class="px-5 py-3 text-start">{$t('reports.salaryPostingAccountType')}</th>
						<th class="px-5 py-3 text-start">{$t('reports.salaryPostingLedgers')}</th>
						<th class="w-20 px-5 py-3"></th>
					</tr>
				</thead>
				<tbody class="divide-y divide-slate-100">
					{#each visibleAccountKeys as key (key)}
						<tr class="even:bg-slate-50">
							<td class="px-5 py-3 text-slate-500">{deductionKeys.indexOf(key) + 1}</td>
							<td class="px-5 py-3 font-medium text-slate-800">{$t(accountLabelKey(key))}</td>
							<td class="px-5 py-3 text-slate-600">
								{#each mappings.filter(item => item.deduction_key === key) as mapping (mapping.branch_id)}
									<div class="py-1">{branches.find(branch => Number(branch.branch_id) === Number(mapping.branch_id))?.branch_name || mapping.branch_id}: <span class="font-mono">{mapping.ledger_code}</span> — {mapping.ledger_name}</div>
								{/each}
							</td>
							<td class="px-5 py-3">
								<button type="button" on:click={() => openPicker(key)} aria-label={`${$t('reports.salarySelectPostingLedger')}: ${$t(accountLabelKey(key))}`} class="w-8 h-8 bg-blue-600 hover:bg-blue-700 text-white rounded-lg text-xl font-bold">+</button>
							</td>
						</tr>
					{/each}
				</tbody>
			</table>
			{/if}
		</div>
	</div>
</div>

{#if activeDeduction}
	<div class="absolute inset-0 z-[100] bg-black/40 flex items-center justify-center p-6" dir={$locale === 'ar' ? 'rtl' : 'ltr'}>
		<section role="dialog" aria-modal="true" aria-label={$t(activeSponsor && !isAdjustmentPicker ? 'reports.salarySelectBankAccount' : 'reports.salarySelectPostingLedger')} class="w-full max-w-3xl max-h-full bg-white rounded-xl shadow-xl p-5 flex flex-col gap-4 overflow-hidden">
			<div class="flex justify-between items-center gap-4">
				<h3 class="text-lg font-bold text-slate-800">{activeSponsor ? ($locale === 'ar' ? activeSponsor.name_ar : activeSponsor.name_en) : $t(accountLabelKey(activeDeduction))} — {$t(activeSponsor && !isAdjustmentPicker ? 'reports.salarySelectBankAccount' : 'reports.salarySelectPostingLedger')}</h3>
				<button type="button" on:click={closePicker} disabled={saving} aria-label={$t('common.close')} class="p-2 rounded hover:bg-slate-100">&#215;</button>
			</div>
			<label class="text-sm font-semibold text-slate-700">
				{$t('hr.branch')}
				<select bind:value={branchId} on:change={loadLedgers} disabled={saving} class="block mt-1 w-full border border-slate-300 rounded-lg px-3 py-2">
					<option value="">{$t('reports.salarySelectBranch')}</option>
					{#each pickerBranches as branch (branch.branch_id)}<option value={String(branch.branch_id)}>{branch.branch_name}</option>{/each}
				</select>
			</label>
			{#if activeSponsor && !isAdjustmentPicker}<p class="text-sm text-slate-500">{$t('reports.salaryOneSponsorBankAccount')}</p>{/if}
			<label class="text-sm font-semibold text-slate-700">
				{$t(isAdjustmentPicker ? 'reports.salaryAllLedgers' : activeSponsor ? 'reports.salarySponsorBankAccounts' : ['foodAllowanceDeduction', 'gosiDeduction', 'mainSalaryAccount', 'nonSponsorshipSalaryAccount'].includes(activeDeduction) ? 'reports.salaryAllLedgers' : 'reports.salaryIndirectIncomeLedgers')}
				<input type="search" bind:value={search} disabled={!branchId || loading || saving} placeholder={$t('reports.salarySearchLedger')} class="block mt-1 w-full border border-slate-300 rounded-lg px-3 py-2" />
			</label>
			{#if error}<p class="text-sm text-red-700" role="alert">{error}</p>{/if}
			<div class="min-h-0 overflow-auto border border-slate-200 rounded-lg">
				{#if loading}<p class="p-4 text-sm text-slate-500">{$t('common.loading')}</p>
				{:else if branchId && !error && filteredLedgers.length === 0}<p class="p-4 text-sm text-slate-500">{$t(isAdjustmentPicker ? 'reports.salaryNoLedgers' : activeSponsor ? 'reports.salaryNoBankLedgers' : ['foodAllowanceDeduction', 'gosiDeduction', 'mainSalaryAccount', 'nonSponsorshipSalaryAccount'].includes(activeDeduction) ? 'reports.salaryNoLedgers' : 'reports.salaryNoIncomeLedgers')}</p>
				{:else}
					{#each filteredLedgers as ledger (ledger.LedgerID)}
						<button type="button" disabled={saving} aria-pressed={selectedLedger?.LedgerID === ledger.LedgerID} on:click={() => selectedLedger = ledger} class="w-full px-4 py-3 text-start border-b border-slate-100 hover:bg-blue-50 {selectedLedger?.LedgerID === ledger.LedgerID ? 'bg-blue-100 text-blue-800' : 'text-slate-700'}">
							<span class="font-mono font-bold">{ledger.LedgerCode}</span> — {ledger.LedgerName}
						</button>
					{/each}
				{/if}
			</div>
			<div class="flex justify-end gap-2">
				<button type="button" on:click={closePicker} disabled={saving} class="px-4 py-2 bg-slate-100 rounded-lg">{$t('hr.salaryStatement.cancel')}</button>
				<button type="button" on:click={saveSelection} disabled={!selectedLedger || loading || saving} class="px-4 py-2 bg-blue-600 text-white rounded-lg disabled:opacity-50">{saving ? $t('common.loading') : $t('common.save')}</button>
			</div>
		</section>
	</div>
{/if}

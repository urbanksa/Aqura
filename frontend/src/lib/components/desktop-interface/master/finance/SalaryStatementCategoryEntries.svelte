<script lang="ts">
	import { onMount, onDestroy, tick } from 'svelte';
	import { _ as t, locale } from '$lib/i18n';
	import { supabase } from '$lib/utils/supabase';
	import { salaryCategoryEntries, type SalaryCategoryEmployee, type SalaryEntryCategory } from '$lib/utils/salaryCategoryEntries';
	import type { SalaryPaymentContext } from '$lib/utils/salaryPaymentPreview';
	import type { SavedSalaryEmployeeContext } from '$lib/utils/savedSalaryEmployeeContext';
	import { savedSalaryCategoryEntries, type SavedSalaryEntryBundle, type SalaryEntryResult } from '$lib/utils/salaryEntryWorkflow';
	export let employeeContexts: Record<string, SavedSalaryEmployeeContext>;
	export let category: SalaryEntryCategory;
	export let rows: { employeeId: string; employeeName: string; branchId: number; grossEarnings: number; netSalary: number; netBank: number; netCash: number; deductions: Partial<Record<string, number>> }[];
	export let startDate: string;
	export let endDate: string;
	export let onGenerated: (success: boolean, result?: SalaryEntryResult) => void;
	export let savedBundle: SavedSalaryEntryBundle | null = null;
	export let onSavedBundleChange: (bundle: SavedSalaryEntryBundle) => void;
	let posting = '';
	let taskError = '';
	async function postTasks(voucherId?: string) {
		if (!savedBundle || !categorySaved || posting) return;
		posting = voucherId || category; taskError = '';
		try {
			const response = await supabase.rpc('post_salary_entry_tasks', { p_batch_id: savedBundle.id, p_category: category, p_voucher_id: voucherId || null });
			if (response.error) throw response.error;
			if (!disposed) onSavedBundleChange(response.data);
		} catch(e) { if (!disposed) taskError = (e as { message?: string }).message || $t('reports.salaryEntryLoadError'); }
		finally { if (!disposed) posting = ''; }
	}
	let resolved: SalaryCategoryEmployee[] = [];
	let branchNames: Record<number, { name_en: string; name_ar: string }> = {};
	let loading = true;
	let loaded = 0;
	let error = '';
	let disposed = false;
	const controller = new AbortController();
	onDestroy(() => { disposed = true; controller.abort(); });
	$: generatedResult = salaryCategoryEntries(resolved.map(employee => ({ ...employee,
		employeeName: rows.find(row => row.employeeId === employee.employeeId)?.employeeName || employee.employeeName,
		branchName: $locale === 'ar' ? branchNames[employee.branchId]?.name_ar || employee.branchName : branchNames[employee.branchId]?.name_en || employee.branchName
	})), $locale, $t('reports.salarySponsorAdjustmentAccount'), $t('reports.salaryVikinBankAccount'));
	$: result = savedBundle ? savedSalaryCategoryEntries(savedBundle, generatedResult, $locale) : generatedResult;
	$: savedCategory = savedBundle?.vouchers.filter(v => v.category === category) || [];
	$: isVikinCategory = category === 'bankVikin' || category === 'adjustmentsVikin';
	$: categorySaved = !!savedBundle && (!isVikinCategory || savedBundle.vikin_entries_saved === true);
	$: vouchers = result.categories[category];
	$: issues = result.issues[category];
	$: branchIds = [...new Set(vouchers.map(v => v.branchId))];
	onMount(async () => {
		try {
			if (!rows.length) return;
			const [branches, accounts, cash] = await Promise.all([
				supabase.from('branches').select('id, company_id, name_en, name_ar').in('id', [...new Set(rows.map(row => row.branchId))]),
				supabase.from('salary_deduction_posting_accounts').select('branch_id, deduction_key, ledger_name, ledger_code'),
				supabase.from('erp_posting_ledger_links').select('branch_id, ledger_name, ledger_code').eq('account_key', 'branch_cash')
			]);
			for (const response of [branches, accounts, cash]) if (response.error) throw response.error;
			if (disposed) return;
			branchNames = Object.fromEntries((branches.data || []).map(branch => [Number(branch.id), branch]));
			const contexts = new Map<string, Promise<{ context: SalaryPaymentContext; error?: string }>>();
			const entries: SalaryCategoryEmployee[] = new Array(rows.length);
			let next = 0;
			async function worker() {
				while (next < rows.length && !disposed) {
					const index = next++;
					const row = rows[index];
					const profile = employeeContexts[row.employeeId];
					const branch = branches.data?.find(b => Number(b.id) === row.branchId);
					const ledgers = Object.fromEntries((accounts.data || []).filter(a => Number(a.branch_id) === row.branchId).map(a => [a.deduction_key, { name: a.ledger_name, code: a.ledger_code }]));
					const branchCash = cash.data?.find(c => Number(c.branch_id) === row.branchId);
					const entry: SalaryCategoryEmployee = { ...row, startDate, endDate,
						employeeSponsorId: profile?.sponsor_id == null ? null : Number(profile.sponsor_id),
						branchCompanyId: branch?.company_id == null ? null : Number(branch.company_id),
						branchName: branch?.name_en || branch?.name_ar || String(row.branchId),
						mainLedger: ledgers.mainSalaryAccount || null, employeeLedger: null, deductionLedgers: ledgers,
						nonSponsorshipLedger: ledgers.nonSponsorshipSalaryAccount || null,
						cashLedger: branchCash ? { name: branchCash.ledger_name, code: branchCash.ledger_code } : null, context: {} };
					if (!profile || !branch) entry.metadataError = $t('reports.salaryEntryLoadError');
					else if (entry.employeeSponsorId) {
						const key = `${row.employeeId}:${row.branchId}`;
						if (!contexts.has(key)) contexts.set(key, (async () => {
							const response = await supabase.rpc('get_salary_payment_preview_accounts', { p_employee_id: row.employeeId, p_branch_id: row.branchId });
							return { context: response.data || {}, error: response.error?.message };
						})());
						const erpEmployeeId = profile.erp_employee_id_mapping?.[String(row.branchId)];
						const ledgerPromise = (async () => {
							if (!erpEmployeeId) return;
							try {
								const response = await fetch('/api/erp-employee-balance', { method: 'POST', headers: { 'Content-Type': 'application/json' },
									body: JSON.stringify({ branchId: row.branchId, erpEmployeeId }), signal: AbortSignal.any([controller.signal, AbortSignal.timeout(25000)]) });
								const data = await response.json();
								if (response.ok && data.success && data.balance?.ledgerName) entry.employeeLedger = { name: data.balance.ledgerName, code: String(data.balance.ledgerCode ?? '') };
							} catch { /* A missing ledger is reported per employee by the preview helpers. */ }
						})();
						const [paymentContext] = await Promise.all([contexts.get(key)!, ledgerPromise]);
						entry.context = paymentContext.context;
						entry.paymentError = paymentContext.error;
					}
					entries[index] = entry;
					if (!disposed) loaded++;
				}
			}
			await Promise.all(Array.from({ length: Math.min(4, rows.length) }, worker));
			if (!disposed) resolved = entries;
		} catch (e) { if (!disposed) error = (e as { message?: string }).message || $t('reports.salaryEntryLoadError'); }
		finally {
			if (!disposed) {
				loading = false;
				await tick();
				if (!disposed) onGenerated(!error, !error ? generatedResult : undefined);
			}
		}
	});
</script>

<div class="flex-1 min-h-0 overflow-auto p-6" dir={$locale === 'ar' ? 'rtl' : 'ltr'}>
	<p class="text-xs text-slate-500 mb-4">{categorySaved ? $t('reports.salaryEntriesSavedLocked') : $t('reports.salaryEntryPreviewOnly')} · {startDate} — {endDate}</p>
	{#if categorySaved && category !== 'cash'}
		<button type="button" disabled={!!posting || !savedCategory.length || savedCategory.every(v => !!v.task_id)} on:click={() => postTasks()} class="mb-4 px-4 py-2 bg-blue-600 text-white rounded-lg font-bold disabled:opacity-40">{posting ? $t('common.loading') : $t('reports.salaryPostTask')}</button>
	{/if}
	{#if taskError}<p role="alert" class="mb-4 text-sm text-red-700">{taskError}</p>{/if}
	{#if isVikinCategory}
		<p class="mb-4 text-sm text-slate-600">{$t('reports.salaryVikinSavedTaskHelp')}</p>
	{/if}
	{#if loading}<p class="text-sm text-slate-600">{$t('common.loading')} {loaded} / {rows.length}</p>
	{:else if error}<p class="text-sm text-red-700" role="alert">{error}</p>
	{:else}
		{#if issues.length}<div class="mb-4 p-3 bg-amber-50 border border-amber-200 rounded text-sm text-amber-900" role="alert">
			<p class="font-bold mb-2">{$t('reports.salaryCategoryIncomplete')}</p>
			{#each issues as issue}<p>{issue.employeeId} — {issue.employeeName}: {issue.error || $t(`reports.${issue.messageKey}`)}</p>{/each}
		</div>{/if}
		{#if !vouchers.length}<p class="text-sm text-slate-500">{$t('reports.salaryCategoryEmpty')}</p>{/if}
		{#each branchIds as id}
			<section class="mb-6">
				<h3 class="font-bold text-slate-800 mb-3">{vouchers.find(v => v.branchId === id)?.branchName}</h3>
				{#each vouchers.filter(v => v.branchId === id) as voucher}
					<div class="mb-4 p-4 bg-white border border-slate-200 rounded-lg">
						<div class="flex justify-between gap-3 mb-3"><strong>{voucher.voucherType}{voucher.companyName ? ` — ${voucher.companyName}` : ''}{voucher.employeeName ? ` — ${voucher.employeeName}` : ''}</strong><span class="text-xs text-green-800">{voucher.debit === voucher.credit ? $t('reports.salaryEntryBalanced') : ''}</span></div>
						{#if isVikinCategory}
							<p class="mb-3 text-sm text-slate-600">{$t('reports.salaryVikinCombinedCounts').replace('{employees}', String(voucher.employees?.length || 0)).replace('{lines}', String(voucher.lines.length))}</p>
						{/if}
						{#each savedCategory.filter(v => v.id === voucher.key) as saved}
							<div class="flex items-center gap-3 mb-3 text-sm">
								{#if category === 'cash'}<button type="button" disabled={!!posting || !!saved.task_id} on:click={() => postTasks(saved.id)} class="px-3 py-2 bg-blue-600 text-white rounded-lg font-bold disabled:opacity-40">{posting === saved.id ? $t('common.loading') : $t('reports.salaryPostTask')}</button>{/if}
								<span class="font-bold">{$t(`reports.salaryTaskStatus_${saved.task_status}`)}</span>
								{#if saved.assigned_user_name}<span>{saved.assigned_user_name}</span>{/if}
								{#if saved.voucher_date}<span>{saved.voucher_date}</span>{/if}
							</div>
						{/each}
						{#if voucher.paidFrom}<p class="text-sm mb-3">{$t('reports.salaryEntryPaidFrom')}: {voucher.paidFrom.name} <span class="font-mono">{voucher.paidFrom.code}</span></p>{/if}
						<table class="w-full text-sm">
							<thead class="bg-slate-100 text-slate-600"><tr>{#if category === 'booking' || category === 'adjustments'}<th class="p-2 text-start w-12">#</th>{/if}<th class="p-2 text-start">{$t('reports.salaryPostingAccountType')}</th><th class="p-2 text-start">{$t('reports.salaryEntryNarration')}</th><th class="p-2 text-end">{$t('reports.salaryEntryDebit')}</th>{#if voucher.voucherType !== 'CP'}<th class="p-2 text-end">{$t('reports.salaryEntryCredit')}</th>{/if}</tr></thead>
							<tbody>{#each voucher.lines.filter(line => voucher.voucherType !== 'CP' || line.side === 'Debit') as line, lineIndex}<tr class="border-b border-slate-100">
								{#if category === 'booking' || category === 'adjustments'}<td class="p-2 text-slate-500 font-mono">{lineIndex + 1}</td>{/if}<td class="p-2"><strong>{line.ledger_name}</strong><span class="block text-xs text-slate-500">{line.placeholder ? $t('reports.salaryPaymentPlaceholder') : line.ledger_code}</span></td><td class="p-2">{line.narration}</td><td class="p-2 text-end font-mono text-green-700">{line.side === 'Debit' ? line.amount : '—'}</td>{#if voucher.voucherType !== 'CP'}<td class="p-2 text-end font-mono text-red-700">{line.side === 'Credit' ? line.amount : '—'}</td>{/if}
							</tr>{/each}</tbody>
							<tfoot class="bg-slate-50 font-bold"><tr><td colspan={category === 'booking' || category === 'adjustments' ? 3 : 2} class="p-2 text-end">{$t('reports.salaryEntryTotal')}</td><td class="p-2 text-end font-mono">{voucher.debit.toFixed(2)}</td>{#if voucher.voucherType !== 'CP'}<td class="p-2 text-end font-mono">{voucher.credit.toFixed(2)}</td>{/if}</tr></tfoot>
						</table>
					</div>
				{/each}
			</section>
		{/each}
	{/if}
</div>

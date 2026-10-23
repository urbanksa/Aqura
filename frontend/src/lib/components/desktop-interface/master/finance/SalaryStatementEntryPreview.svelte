<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { _ as t, locale } from '$lib/i18n';
	import { supabase } from '$lib/utils/supabase';
	import { salaryBookingPreview, isSalarySponsored } from '$lib/utils/salaryBookingPreview';
	import SalaryStatementPaymentPreview from './SalaryStatementPaymentPreview.svelte';
	import type { SavedSalaryEmployeeContext } from '$lib/utils/savedSalaryEmployeeContext';

	export let employeeId: string;
	export let employeeName: string;
	export let branchId: number;
	export let grossEarnings: number;
	export let netSalary: number;
	export let netBank: number;
	export let netCash: number;
	export let deductions: Partial<Record<string, number>> = {};
	export let startDate: string;
	export let endDate: string;
	export let onCollapse: () => void;
	export let employeeContext: SavedSalaryEmployeeContext | undefined;
	let employeeSponsorId: number | null = null;
	let branchCompanyId: number | null = null;
	let branchNameEn = '';
	let branchNameAr = '';
	let mainLedger: { name: string; code: string } | null = null;
	let employeeLedger: { name: string; code: string } | null = null;
	let cashLedger: { name: string; code: string } | null = null;
	let deductionLedgers: Record<string, { name: string; code: string }> = {};
	let loading = true;
	let error = '';
	let disposed = false;
	onDestroy(() => { disposed = true; });
	$: preview = salaryBookingPreview({ employeeSponsorId, branchCompanyId, grossEarnings,
		employeeId, employeeName, startDate, endDate, mainLedger, employeeLedger, deductions, deductionLedgers,
		netSalary, nonSponsorshipLedger: deductionLedgers.nonSponsorshipSalaryAccount, cashLedger });

	onMount(async () => {
		try {
			const [employeeResult, branchResult, accountResult] = await Promise.all([
				Promise.resolve({ data: employeeContext, error: employeeContext ? null : new Error($t('reports.salaryEntryLoadError')) }),
				supabase.from('branches').select('company_id, name_en, name_ar').eq('id', branchId).single(),
				supabase.from('salary_deduction_posting_accounts').select('deduction_key, ledger_name, ledger_code').eq('branch_id', branchId)
			]);
			if (disposed) return;
			for (const result of [employeeResult, branchResult, accountResult]) if (result.error) throw result.error;
			employeeSponsorId = employeeResult.data?.sponsor_id == null ? null : Number(employeeResult.data.sponsor_id);
			branchCompanyId = branchResult.data?.company_id == null ? null : Number(branchResult.data.company_id);
			branchNameEn = branchResult.data?.name_en || '';
			branchNameAr = branchResult.data?.name_ar || '';
			deductionLedgers = Object.fromEntries((accountResult.data || []).map(account => [account.deduction_key, { name: account.ledger_name, code: account.ledger_code }]));
			mainLedger = deductionLedgers.mainSalaryAccount || null;
			if (!branchCompanyId) return;
			if (!isSalarySponsored(employeeSponsorId)) {
				const { data: cash, error: cashError } = await supabase.from('erp_posting_ledger_links')
					.select('ledger_name, ledger_code').eq('branch_id', branchId).eq('account_key', 'branch_cash').maybeSingle();
				if (disposed) return;
				if (cashError) throw cashError;
				if (cash) cashLedger = { name: cash.ledger_name, code: cash.ledger_code };
				return;
			}
			const erpEmployeeId = employeeResult.data?.erp_employee_id_mapping?.[String(branchId)];
			if (!erpEmployeeId) return;
			const response = await fetch('/api/erp-employee-balance', {
				method: 'POST', headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ branchId, erpEmployeeId }), signal: AbortSignal.timeout(25000)
			});
			const data = await response.json();
			if (disposed) return;
			if (!response.ok || !data.success) throw new Error(data.error || $t('reports.salaryEntryLoadError'));
			if (data.balance?.ledgerName) employeeLedger = { name: data.balance.ledgerName, code: String(data.balance.ledgerCode ?? '') };
		} catch (e) {
			if (!disposed) error = (e as { message?: string })?.message || $t('reports.salaryEntryLoadError');
		} finally {
			if (!disposed) loading = false;
		}
	});
</script>

<section class="bg-white border border-blue-200 rounded-lg p-4 w-[1100px] max-w-full" dir={$locale === 'ar' ? 'rtl' : 'ltr'} aria-label={`${$t('reports.salaryShowEntry')}: ${employeeName}`}>
	<div class="flex items-start justify-between gap-4 mb-3">
		<div>
			<h3 class="font-bold text-slate-800">{employeeId} — {employeeName}</h3>
			<p class="mt-1 text-xs text-slate-500">{$t('reports.salaryEntryPreviewOnly')}</p>
			{#if !loading && !error && preview.lines.length}<p class="mt-1 text-xs font-bold text-blue-700">{preview.voucherType === 'CP' ? $t('reports.salaryEntryCashPayment') : 'MJV'}</p>{/if}
		</div>
		<div class="flex items-center gap-3 shrink-0">
			{#if !loading && !error && preview.lines.length && preview.voucherType !== 'CP'}<span class="px-2 py-1 rounded bg-green-100 text-green-800 text-xs font-bold">{$t('reports.salaryEntryBalanced')}</span>{/if}
			<button type="button" on:click={onCollapse} class="px-3 py-2 rounded-lg bg-slate-100 hover:bg-slate-200 text-slate-700 text-xs font-bold">{$t('reports.salaryHideEntry')} &#215;</button>
		</div>
	</div>
	{#if loading}<p class="text-sm text-slate-500">{$t('common.loading')}</p>
	{:else if error}<p role="alert" class="text-sm text-red-700">{error}</p>
	{:else if preview.messageKey}<p class="text-sm text-amber-700">{$t(`reports.${preview.messageKey}`)}</p>
	{:else if preview.voucherType === 'CP' && preview.cashPayment}
		<div class="mb-3 text-sm text-slate-600 space-y-1">
			<p><strong>{$t('hr.branch')}:</strong> {$locale === 'ar' ? branchNameAr || branchNameEn : branchNameEn || branchNameAr}</p>
			<p><strong>{$t('reports.salaryEntryPaidFrom')}:</strong> {cashLedger?.name} <span class="font-mono">{cashLedger?.code}</span></p>
		</div>
		<table class="w-full text-sm text-start">
			<thead class="bg-slate-100 text-slate-600"><tr>
				<th class="p-2 text-start">{$t('reports.salaryPostingAccountType')}</th>
				<th class="p-2 text-end">{$t('reports.salaryEntryAmount')}</th>
				<th class="p-2 text-start">{$t('reports.salaryEntrySide')}</th>
				<th class="p-2 text-start">{$t('reports.salaryEntryNarration')}</th>
			</tr></thead>
			<tbody><tr class="border-b border-slate-100">
				<td class="p-2"><strong>{preview.cashPayment.ledger_name}</strong><span class="block font-mono text-xs text-slate-500">{deductionLedgers.nonSponsorshipSalaryAccount?.code}</span></td>
				<td class="p-2 text-end font-mono">{preview.cashPayment.amount}</td>
				<td class="p-2">{$t('reports.salaryEntryDebit')}</td>
				<td class="p-2">{preview.cashPayment.narration}</td>
			</tr></tbody>
		</table>
	{:else}
		<table class="w-full text-sm text-start">
			<thead class="bg-slate-100 text-slate-600"><tr>
				<th class="p-2 text-start">{$t('hr.branch')}</th>
				<th class="p-2 text-start">{$t('reports.salaryPostingAccountType')}</th>
				<th class="p-2 text-start">{$t('reports.salaryEntryNarration')}</th>
				<th class="p-2 text-end">{$t('reports.salaryEntryDebit')}</th>
				<th class="p-2 text-end">{$t('reports.salaryEntryCredit')}</th>
			</tr></thead>
			<tbody>
				{#each preview.lines as line}
					<tr class="border-b border-slate-100">
						<td class="p-2">{$locale === 'ar' ? branchNameAr || branchNameEn : branchNameEn || branchNameAr}</td>
						<td class="p-2"><strong>{line.ledger_name}</strong><span class="block font-mono text-xs text-slate-500">{line.ledger_code}</span></td>
						<td class="p-2">{line.narration}</td>
						<td class="p-2 text-end text-green-700 font-mono">{line.side === 'Debit' ? line.amount : '—'}</td>
						<td class="p-2 text-end text-red-700 font-mono">{line.side === 'Credit' ? line.amount : '—'}</td>
					</tr>
				{/each}
			</tbody>
			<tfoot class="bg-slate-50 font-bold"><tr><td colspan="3" class="p-2 text-end">{$t('reports.salaryEntryTotal')}</td><td class="p-2 text-end font-mono">{preview.debit.toFixed(2)}</td><td class="p-2 text-end font-mono">{preview.credit.toFixed(2)}</td></tr></tfoot>
		</table>
	{/if}
	{#if !loading && isSalarySponsored(employeeSponsorId)}
		<SalaryStatementPaymentPreview {employeeId} {employeeName} {branchId} {netBank} {netCash} {employeeLedger} {startDate} {endDate}
			branchName={$locale === 'ar' ? branchNameAr || branchNameEn : branchNameEn || branchNameAr} />
	{/if}
	<div class="flex justify-end mt-4">
		<button type="button" on:click={onCollapse} class="px-3 py-2 rounded-lg bg-slate-100 hover:bg-slate-200 text-slate-700 text-xs font-bold">{$t('reports.salaryHideEntry')} &#215;</button>
	</div>
</section>

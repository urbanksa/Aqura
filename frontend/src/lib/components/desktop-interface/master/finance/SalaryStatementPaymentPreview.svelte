<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { _ as t, locale } from '$lib/i18n';
	import { supabase } from '$lib/utils/supabase';
	import { salaryPaymentPreview, salaryCashPaymentPreview, salaryVikinPaymentPreview, salaryVikinAdjustmentPreview, type SalaryPaymentContext } from '$lib/utils/salaryPaymentPreview';
	export let employeeId: string;
	export let employeeName: string;
	export let branchId: number;
	export let branchName: string;
	export let netBank: number;
	export let netCash: number;
	export let employeeLedger: { name: string; code: string } | null;
	export let startDate: string;
	export let endDate: string;
	let context: SalaryPaymentContext = {};
	let loading = true;
	let error = '';
	let cashError = '';
	let cashLedger: { name: string; code: string } | null = null;
	let disposed = false;
	onDestroy(() => { disposed = true; });
	$: preview = salaryPaymentPreview({ context, netBank, branchId, branchName, employeeLedger,
		employeeId, employeeName, startDate, endDate, language: $locale, adjustmentLabel: $t('reports.salarySponsorAdjustmentAccount') });
	$: cashPreview = salaryCashPaymentPreview({ provider: context.provider, netCash, employeeLedger, cashLedger,
		employeeId, employeeName, startDate, endDate });
	$: vikinPreview = salaryVikinPaymentPreview({ context, netBank, branchId, branchName,
		employeeId, employeeName, startDate, endDate, language: $locale,
		adjustmentLabel: $t('reports.salarySponsorAdjustmentAccount'), bankLabel: $t('reports.salaryVikinBankAccount') });
	$: vikinAdjustmentPreview = salaryVikinAdjustmentPreview({ context, netBank, branchId, branchName,
		employeeId, employeeName, startDate, endDate, language: $locale });
	onMount(async () => {
		try {
			const result = await supabase.rpc('get_salary_payment_preview_accounts', { p_employee_id: employeeId, p_branch_id: branchId });
			if (disposed) return;
			if (result.error) throw result.error;
			context = result.data || {};
			if (context.provider === 'polosys' && netCash > 0) {
				const cash = await supabase.from('erp_posting_ledger_links').select('ledger_name, ledger_code')
					.eq('branch_id', branchId).eq('account_key', 'branch_cash').maybeSingle();
				if (disposed) return;
				if (cash.error) cashError = cash.error.message;
				else if (cash.data) cashLedger = { name: cash.data.ledger_name, code: cash.data.ledger_code };
			}
		} catch (e) {
			if (!disposed) error = (e as { message?: string }).message || $t('reports.salaryEntryLoadError');
		} finally { if (!disposed) loading = false; }
	});
</script>

{#if loading || error || context.provider === 'polosys'}
	<section class="mt-5 pt-4 border-t border-slate-200" aria-label={$t('reports.salaryPaymentTitle')}>
		<h4 class="font-bold text-blue-800 mb-3">{$t('reports.salaryPaymentTitle')}</h4>
		{#if loading}<p class="text-sm text-slate-500">{$t('common.loading')}</p>
		{:else if error}<p role="alert" class="text-sm text-red-700">{error}</p>
		{:else if preview.messageKey}<p class="text-sm text-amber-700">{$t(`reports.${preview.messageKey}`)}</p>
		{:else}
			{#each preview.groups as group}
				<div class="mb-4 border border-slate-200 rounded p-3">
					<div class="flex justify-between gap-3 mb-2"><strong>MJV — {group.branchName}</strong><span class="text-xs text-green-800 bg-green-100 rounded px-2 py-1">{$t('reports.salaryEntryBalanced')}</span></div>
					<table class="w-full text-sm text-start">
						<thead class="bg-slate-100 text-slate-600"><tr>
							<th class="p-2 text-start">{$t('reports.salaryPostingAccountType')}</th>
							<th class="p-2 text-start">{$t('reports.salaryEntryNarration')}</th>
							<th class="p-2 text-end">{$t('reports.salaryEntryDebit')}</th>
							<th class="p-2 text-end">{$t('reports.salaryEntryCredit')}</th>
						</tr></thead>
						<tbody>{#each group.lines as line}<tr class="border-b border-slate-100">
							<td class="p-2"><strong>{line.ledger_name}</strong>{#if line.placeholder}<span class="block text-xs text-amber-700">{$t('reports.salaryPaymentPlaceholder')}</span>{:else}<span class="block font-mono text-xs text-slate-500">{line.ledger_code}</span>{/if}</td>
							<td class="p-2">{line.narration}</td>
							<td class="p-2 text-end text-green-700 font-mono">{line.side === 'Debit' ? line.amount : '—'}</td>
							<td class="p-2 text-end text-red-700 font-mono">{line.side === 'Credit' ? line.amount : '—'}</td>
						</tr>{/each}</tbody>
						<tfoot class="bg-slate-50 font-bold"><tr><td colspan="2" class="p-2 text-end">{$t('reports.salaryEntryTotal')}</td><td class="p-2 text-end font-mono">{group.total.toFixed(2)}</td><td class="p-2 text-end font-mono">{group.total.toFixed(2)}</td></tr></tfoot>
					</table>
				</div>
			{/each}
		{/if}
	</section>
{/if}

{#each [{ titleKey: 'reports.salaryVikinAdjustmentTitle', preview: vikinAdjustmentPreview }, { titleKey: 'reports.salaryVikinPaymentTitle', preview: vikinPreview }] as vikinSection}
{#if !loading && !error && (vikinSection.preview.lines.length || vikinSection.preview.messageKey)}
	<section class="mt-5 pt-4 border-t border-slate-200" aria-label={$t(vikinSection.titleKey)}>
		<h4 class="font-bold text-blue-800 mb-3">{$t(vikinSection.titleKey)}</h4>
		{#if vikinSection.preview.messageKey}<p class="text-sm text-amber-700">{employeeId} — {employeeName}: {$t(`reports.${vikinSection.preview.messageKey}`)}</p>
		{:else}
			<p class="mb-3 text-sm font-bold">{$locale === 'ar' ? context.sponsor_name_ar || context.sponsor_name : context.sponsor_name || context.sponsor_name_ar}</p>
			<table class="w-full text-sm text-start">
				<thead class="bg-slate-100 text-slate-600"><tr>
					<th class="p-2 text-start">{$t('reports.salaryPostingAccountType')}</th>
					<th class="p-2 text-start">{$t('reports.salaryEntryNarration')}</th>
					<th class="p-2 text-end">{$t('reports.salaryEntryDebit')}</th>
					<th class="p-2 text-end">{$t('reports.salaryEntryCredit')}</th>
				</tr></thead>
				<tbody>{#each vikinSection.preview.lines as line}<tr class="border-b border-slate-100">
					<td class="p-2"><strong>{line.ledger_name}</strong><span class="block font-mono text-xs text-slate-500">{line.ledger_code}</span></td>
					<td class="p-2">{line.narration}</td>
					<td class="p-2 text-end text-green-700 font-mono">{line.side === 'Debit' ? line.amount : '—'}</td>
					<td class="p-2 text-end text-red-700 font-mono">{line.side === 'Credit' ? line.amount : '—'}</td>
				</tr>{/each}</tbody>
				<tfoot class="bg-slate-50 font-bold"><tr><td colspan="2" class="p-2 text-end">{$t('reports.salaryEntryTotal')}</td><td class="p-2 text-end font-mono">{vikinSection.preview.total.toFixed(2)}</td><td class="p-2 text-end font-mono">{vikinSection.preview.total.toFixed(2)}</td></tr></tfoot>
			</table>
		{/if}
	</section>
{/if}
{/each}

{#if !loading && !error && context.provider === 'polosys' && (cashError || cashPreview.messageKey || cashPreview.payment)}
	<section class="mt-5 pt-4 border-t border-slate-200" aria-label={$t('reports.salaryCashPaymentTitle')}>
		<h4 class="font-bold text-blue-800 mb-3">{$t('reports.salaryCashPaymentTitle')}</h4>
		{#if cashError}<p role="alert" class="text-sm text-red-700">{cashError}</p>
		{:else if cashPreview.messageKey}<p class="text-sm text-amber-700">{$t(`reports.${cashPreview.messageKey}`)}</p>
		{:else if cashPreview.payment}
			<p class="mb-2 text-sm"><strong>{$t('hr.branch')}:</strong> {branchName}</p>
			<p class="mb-3 text-sm"><strong>{$t('reports.salaryEntryPaidFrom')}:</strong> {cashPreview.payment.paidFrom.name} <span class="font-mono">{cashPreview.payment.paidFrom.code}</span></p>
			<table class="w-full text-sm text-start">
				<thead class="bg-slate-100 text-slate-600"><tr>
					<th class="p-2 text-start">{$t('reports.salaryPostingAccountType')}</th>
					<th class="p-2 text-end">{$t('reports.salaryEntryAmount')}</th>
					<th class="p-2 text-start">{$t('reports.salaryEntrySide')}</th>
					<th class="p-2 text-start">{$t('reports.salaryEntryNarration')}</th>
				</tr></thead>
				<tbody><tr class="border-b border-slate-100">
					<td class="p-2"><strong>{cashPreview.payment.ledger_name}</strong><span class="block text-xs font-mono text-slate-500">{cashPreview.payment.ledger_code}</span></td>
					<td class="p-2 text-end font-mono">{cashPreview.payment.amount}</td>
					<td class="p-2">{$t('reports.salaryEntryDebit')}</td>
					<td class="p-2">{cashPreview.payment.narration}</td>
				</tr></tbody>
			</table>
		{/if}
	</section>
{/if}

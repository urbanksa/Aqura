import type { SalaryMjvLine } from './salaryBookingPreview';

type Ledger = { name: string; code: string };
export function salaryCashPaymentPreview(input: {
	provider?: string | null; netCash: number; employeeLedger: Ledger | null; cashLedger: Ledger | null;
	employeeId: string; employeeName: string; startDate: string; endDate: string;
}) {
	const empty = (messageKey = '') => ({ messageKey, payment: null });
	if (input.provider !== 'polosys') return empty();
	if (!Number.isFinite(input.netCash) || input.netCash < 0) return empty('salaryCashPaymentInvalidAmount');
	const amount = (Math.round(input.netCash * 100) / 100).toFixed(2);
	if (Number(amount) === 0) return empty();
	if (!input.cashLedger?.name) return empty('salaryEntryMissingCashAccount');
	if (!input.employeeLedger?.name) return empty('salaryEntryMissingEmployeeLedger');
	return { messageKey: '', payment: {
		ledger_name: input.employeeLedger.name, ledger_code: input.employeeLedger.code, amount, side: 'Debit' as const,
		narration: `Paid ${input.employeeName} (${input.employeeId}) salary in cash for the period ${input.startDate} to ${input.endDate}.`,
		paidFrom: input.cashLedger
	} };
}
export type SalaryPaymentContext = {
	provider?: string | null;
	sponsor_provider?: string | null;
	sponsor_name?: string | null;
	sponsor_name_ar?: string | null;
	vikin_employee_ledger?: { employee_id: string; ledger_name: string; ledger_code: string } | null;
	vikin_branch_adjustment?: { branch_id: number; ledger_name: string; ledger_code: string } | null;
	vikin_bank?: { ledger_name: string; ledger_code: string } | null;
	sponsor_adjustment?: { branch_id: number; ledger_name: string; ledger_code: string } | null;
	bank?: { branch_id: number; branch_name: string; ledger_name: string; ledger_code: string } | null;
	cross_branch_accounts?: { source_branch_id: number; target_branch_id: number; ledger_name: string; ledger_code?: string }[];
};

type SalaryVikinPreviewInput = {
	context: SalaryPaymentContext; netBank: number; branchId: number; branchName: string;
	employeeId: string; employeeName: string; startDate: string; endDate: string;
	language?: string; adjustmentLabel?: string; bankLabel?: string;
};

export function salaryVikinPaymentPreview(input: SalaryVikinPreviewInput) {
	return salaryVikinPreview(input, 'bank');
}

export function salaryVikinAdjustmentPreview(input: SalaryVikinPreviewInput) {
	return salaryVikinPreview(input, 'adjustment');
}

function salaryVikinPreview(input: SalaryVikinPreviewInput, kind: 'bank' | 'adjustment') {
	const lines: (SalaryMjvLine & { placeholder?: boolean })[] = [];
	const empty = (messageKey = '') => ({ messageKey, lines, total: 0 });
	if (input.context.sponsor_provider !== 'vikin') return empty();
	if (!Number.isFinite(input.netBank) || input.netBank < 0) return empty('salaryPaymentInvalidAmount');
	const total = Math.round(input.netBank * 100) / 100;
	if (!total) return empty();
	const sponsor = input.language === 'ar'
		? input.context.sponsor_name_ar || input.context.sponsor_name
		: input.context.sponsor_name || input.context.sponsor_name_ar;
	if (!sponsor) return empty('salaryPaymentMissingSponsorName');
	const employeeLedger = input.context.vikin_employee_ledger;
	if (employeeLedger?.employee_id !== input.employeeId || !employeeLedger.ledger_name || !employeeLedger.ledger_code) {
		return empty('salaryPaymentMissingVikinEmployeeLedger');
	}
	const narration = `Salary ${kind === 'bank' ? 'bank payment' : 'branch adjustment'} ${input.startDate} to ${input.endDate} | ${input.employeeId} - ${input.employeeName} | ${input.branchName}`;
	const line = (ledger: { ledger_name: string; ledger_code: string }, side: 'Debit' | 'Credit'): SalaryMjvLine => ({
		ledger_name: ledger.ledger_name, ledger_code: ledger.ledger_code, amount: total.toFixed(2), side, narration
	});
	if (kind === 'adjustment') {
		const adjustment = input.context.vikin_branch_adjustment;
		if (!adjustment?.ledger_name || !adjustment.ledger_code || Number(adjustment.branch_id) !== input.branchId) return empty('salaryPaymentMissingVikinAdjustment');
		return { messageKey: '', total, lines: [line(adjustment, 'Debit'), line(employeeLedger, 'Credit')] };
	}
	const bank = input.context.vikin_bank;
	if (!bank?.ledger_name || !bank.ledger_code) return empty('salaryPaymentMissingVikinBank');
	return { messageKey: '', total, lines: [line(employeeLedger, 'Debit'), line(bank, 'Credit')] };
}

export function salaryPaymentPreview(input: {
	context: SalaryPaymentContext; netBank: number; branchId: number; branchName: string;
	employeeLedger: Ledger | null; employeeId: string; employeeName: string; startDate: string; endDate: string;
	language?: string; adjustmentLabel?: string;
}) {
	const groups: { branchId: number; branchName: string; lines: (SalaryMjvLine & { placeholder?: boolean })[]; total: number }[] = [];
	const empty = (messageKey = '') => ({ messageKey, groups });
	if (input.context.provider !== 'polosys') return empty();
	if (!Number.isFinite(input.netBank) || input.netBank < 0) return empty('salaryPaymentInvalidAmount');
	const total = Math.round(input.netBank * 100) / 100;
	if (!total) return empty('salaryPaymentZero');
	if (!input.employeeLedger?.name) return empty('salaryEntryMissingEmployeeLedger');
	const amount = total.toFixed(2);
	const narration = `Salary bank payment ${input.startDate} to ${input.endDate} | ${input.employeeId} - ${input.employeeName}`;
	const line = (ledger: Ledger, side: 'Debit' | 'Credit', text = narration): SalaryMjvLine => ({
		ledger_name: ledger.name, ledger_code: ledger.code, amount, side, narration: text
	});
	const isPlaceholder = input.context.sponsor_provider === 'vikin';
	if (isPlaceholder) {
		const adjustment = input.context.sponsor_adjustment;
		if (!adjustment?.ledger_name || Number(adjustment.branch_id) !== input.branchId) return empty('salaryPaymentMissingCompanyAdjustment');
		groups.push({ branchId: input.branchId, branchName: input.branchName, total, lines: [
			line(input.employeeLedger, 'Debit'),
			line({ name: adjustment.ledger_name, code: adjustment.ledger_code }, 'Credit')
		] });
		return { messageKey: '', groups };
	}
	const bank = input.context.bank;
	if (!bank?.branch_id || !bank.ledger_name) return empty('salaryPaymentMissingBank');
	const paymentCredit = line({ name: bank.ledger_name, code: bank.ledger_code || '' }, 'Credit');
	if (Number(bank.branch_id) === input.branchId) {
		groups.push({ branchId: input.branchId, branchName: input.branchName, total,
			lines: [line(input.employeeLedger, 'Debit'), paymentCredit] });
	} else {
		const accounts = input.context.cross_branch_accounts || [];
		const payer = accounts.find(a => Number(a.source_branch_id) === Number(bank.branch_id) && Number(a.target_branch_id) === input.branchId);
		const employee = accounts.find(a => Number(a.source_branch_id) === input.branchId && Number(a.target_branch_id) === Number(bank.branch_id));
		if (!payer?.ledger_name || !employee?.ledger_name) return empty('salaryPaymentMissingAdjustments');
		groups.push({ branchId: Number(bank.branch_id), branchName: bank.branch_name, total, lines: [
			line({ name: payer.ledger_name, code: payer.ledger_code || '' }, 'Debit', `${narration} paid by ${bank.branch_name} for ${input.branchName}`),
			paymentCredit
		] }, { branchId: input.branchId, branchName: input.branchName, total, lines: [
			line(input.employeeLedger, 'Debit'),
			line({ name: employee.ledger_name, code: employee.ledger_code || '' }, 'Credit', `${narration} funded by ${bank.branch_name}`)
		] });
	}
	return { messageKey: '', groups };
}

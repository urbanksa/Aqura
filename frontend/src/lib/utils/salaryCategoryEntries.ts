import { salaryBookingPreview, isSalarySponsored, type SalaryMjvLine } from './salaryBookingPreview';
import { salaryPaymentPreview, salaryCashPaymentPreview, salaryVikinPaymentPreview, salaryVikinAdjustmentPreview, type SalaryPaymentContext } from './salaryPaymentPreview';

export const SALARY_ENTRY_CATEGORIES = ['booking', 'adjustments', 'adjustmentsVikin', 'bankPolosys', 'bankVikin', 'cash'] as const;
export type SalaryEntryCategory = typeof SALARY_ENTRY_CATEGORIES[number];
export type SalaryCategoryEmployee = Parameters<typeof salaryBookingPreview>[0] & {
	branchId: number; branchName: string; netBank: number; netCash: number;
	context: SalaryPaymentContext; metadataError?: string; paymentError?: string;
};
export type SalaryCategoryVoucher = {
	key: string; branchId: number; branchName: string; voucherType: 'MJV' | 'JV' | 'CP';
	companyName?: string; employeeName?: string; paidFrom?: { name: string; code: string };
	companyId?: number; employees?: { employeeId: string; amount: number }[];
	lines: (SalaryMjvLine & { placeholder?: boolean })[]; debit: number; credit: number;
};

export function salaryCategoryEntries(employees: SalaryCategoryEmployee[], language = 'en', adjustmentLabel = 'Adjustment Account', bankLabel = 'Bank Account') {
	const categories = Object.fromEntries(SALARY_ENTRY_CATEGORIES.map(key => [key, []])) as unknown as Record<SalaryEntryCategory, SalaryCategoryVoucher[]>;
	const issues = Object.fromEntries(SALARY_ENTRY_CATEGORIES.map(key => [key, []])) as unknown as Record<SalaryEntryCategory, { employeeId: string; employeeName: string; messageKey?: string; error?: string }[]>;
	function issue(category: SalaryEntryCategory, employee: SalaryCategoryEmployee, messageKey?: string, error?: string) {
		if (messageKey || error) issues[category].push({ employeeId: employee.employeeId, employeeName: employee.employeeName, messageKey, error });
	}
	function add(category: SalaryEntryCategory, voucher: Omit<SalaryCategoryVoucher, 'debit' | 'credit'>, combine = true) {
		let target = combine ? categories[category].find(item => item.branchId === voucher.branchId
			&& (!['adjustmentsVikin', 'bankVikin'].includes(category) || item.companyId === voucher.companyId)) : undefined;
		if (!target) { target = { ...voucher, employees: voucher.employees ? [] : undefined, lines: [], debit: 0, credit: 0 }; categories[category].push(target); }
		if (voucher.employees) target.employees!.push(...voucher.employees);
		target.lines.push(...voucher.lines);
		target.debit = target.lines.filter(l => l.side === 'Debit').reduce((sum, l) => sum + Math.round(Number(l.amount) * 100), 0) / 100;
		target.credit = target.lines.filter(l => l.side === 'Credit').reduce((sum, l) => sum + Math.round(Number(l.amount) * 100), 0) / 100;
	}
	for (const employee of employees) {
		if (employee.metadataError) {
			for (const category of SALARY_ENTRY_CATEGORIES) issue(category, employee, undefined, employee.metadataError);
			continue;
		}
		const base = { key: employee.employeeId, branchId: employee.branchId, branchName: employee.branchName };
		const sponsored = isSalarySponsored(employee.employeeSponsorId);
		const booking = salaryBookingPreview(employee);
		if (booking.messageKey) issue(sponsored ? 'booking' : 'cash', employee, booking.messageKey);
		else if (booking.voucherType === 'CP') add('cash', { ...base, voucherType: 'CP', employeeName: employee.employeeName, paidFrom: employee.cashLedger || undefined, lines: booking.lines }, false);
		else add('booking', { ...base, voucherType: 'MJV', lines: booking.lines });
		if (!sponsored) continue;
		const isVikin = employee.context.sponsor_provider === 'vikin';
		const bankCategory = isVikin ? 'adjustments' : 'bankPolosys';
		if (employee.paymentError) {
			for (const category of ['adjustments', 'adjustmentsVikin', 'bankPolosys', 'bankVikin'] as const) issue(category, employee, undefined, employee.paymentError);
		} else if (employee.netBank !== 0) {
			const payment = salaryPaymentPreview({ ...employee, language, adjustmentLabel });
			issue(bankCategory, employee, payment.messageKey);
			if (payment.messageKey && !isVikin && employee.context.bank && Number(employee.context.bank.branch_id) !== employee.branchId) issue('adjustments', employee, payment.messageKey);
			for (const group of payment.groups) {
				const category = isVikin || (payment.groups.length > 1 && group.branchId === employee.branchId) ? 'adjustments' : 'bankPolosys';
				add(category, { key: employee.employeeId, branchId: group.branchId, branchName: group.branchName, voucherType: 'MJV', lines: group.lines });
			}
			const vikin = salaryVikinPaymentPreview({ ...employee, language, adjustmentLabel, bankLabel });
			const vikinAdjustment = salaryVikinAdjustmentPreview({ ...employee, language, adjustmentLabel, bankLabel });
			issue('adjustmentsVikin', employee, vikinAdjustment.messageKey);
			if (vikinAdjustment.lines.length) add('adjustmentsVikin', { ...base,
				key: `${employee.branchId}:${employee.employeeSponsorId}`, companyId: Number(employee.employeeSponsorId), voucherType: 'JV',
				employees: [{ employeeId: employee.employeeId, amount: vikinAdjustment.total }],
				companyName: language === 'ar' ? employee.context.sponsor_name_ar || employee.context.sponsor_name || '' : employee.context.sponsor_name || employee.context.sponsor_name_ar || '', lines: vikinAdjustment.lines });
			issue('bankVikin', employee, vikin.messageKey);
			if (vikin.lines.length) add('bankVikin', { ...base,
				key: `${employee.branchId}:${employee.employeeSponsorId}`, companyId: Number(employee.employeeSponsorId), voucherType: 'JV',
				employees: [{ employeeId: employee.employeeId, amount: vikin.total }],
				companyName: language === 'ar' ? employee.context.sponsor_name_ar || employee.context.sponsor_name || '' : employee.context.sponsor_name || employee.context.sponsor_name_ar || '', lines: vikin.lines });
		}
		if (employee.netCash !== 0) {
			const cash = salaryCashPaymentPreview({ ...employee, cashLedger: employee.cashLedger || null, provider: employee.context.provider });
			issue('cash', employee, cash.messageKey);
			if (cash.payment) add('cash', { ...base, voucherType: 'CP', employeeName: employee.employeeName, paidFrom: cash.payment.paidFrom, lines: [
				{ ledger_name: cash.payment.ledger_name, ledger_code: cash.payment.ledger_code, amount: cash.payment.amount, side: 'Debit', narration: cash.payment.narration },
				{ ledger_name: cash.payment.paidFrom.name, ledger_code: cash.payment.paidFrom.code, amount: cash.payment.amount, side: 'Credit', narration: cash.payment.narration }
			] }, false);
		}
	}
	for (const category of SALARY_ENTRY_CATEGORIES) categories[category].sort((a, b) => a.branchName.localeCompare(b.branchName));
	return { categories, issues };
}

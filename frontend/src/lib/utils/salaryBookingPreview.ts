export type SalaryMjvLine = {
	ledger_name: string;
	ledger_code: string;
	amount: string;
	side: 'Debit' | 'Credit';
	narration: string;
};

export function isSalarySponsored(employeeSponsorId: number | null): boolean {
	return employeeSponsorId !== null && employeeSponsorId > 0;
}

export const SALARY_BOOKING_DEDUCTIONS = [
	{ key: 'gosi', accountKey: 'gosiDeduction', label: 'GOSI' },
	{ key: 'late', accountKey: 'lateDeductions', label: 'Late arrival' },
	{ key: 'underWorked', accountKey: 'underWorkedDeductions', label: 'Underworked hours' },
	{ key: 'incomplete', accountKey: 'incompleteDeductions', label: 'Incomplete attendance' },
	{ key: 'unapprovedLeave', accountKey: 'unapprovedLeaveDeductions', label: 'Unapproved leave' },
	{ key: 'penalties', accountKey: 'penaltiesDeductions', label: 'Penalties' },
	{ key: 'other', accountKey: 'otherDeductions', label: 'Other deductions' },
	{ key: 'food', accountKey: 'foodAllowanceDeduction', label: 'Food allowance deduction' }
] as const;

export function salaryBookingPreview(input: {
	employeeSponsorId: number | null;
	branchCompanyId: number | null;
	grossEarnings: number;
	netSalary?: number;
	employeeId: string;
	employeeName: string;
	startDate: string;
	endDate: string;
	mainLedger: { name: string; code: string } | null;
	employeeLedger: { name: string; code: string } | null;
	nonSponsorshipLedger?: { name: string; code: string } | null;
	cashLedger?: { name: string; code: string } | null;
	deductions?: Partial<Record<string, number>>;
	deductionLedgers?: Record<string, { name: string; code: string }>;
}): { messageKey: string; lines: SalaryMjvLine[]; debit: number; credit: number; voucherType: 'MJV' | 'CP'; cashPayment?: { ledger_name: string; amount: string; narration: string } } {
	const voucherType = isSalarySponsored(input.employeeSponsorId) ? 'MJV' as const : 'CP' as const;
	const empty = (messageKey: string) => ({ messageKey, lines: [], debit: 0, credit: 0, voucherType });
	if (!input.branchCompanyId) return empty('salaryEntryMissingBranchCompany');
	if (voucherType === 'CP') {
		if (!input.nonSponsorshipLedger?.name) return empty('salaryEntryMissingNonSponsorshipAccount');
		if (!input.cashLedger?.name) return empty('salaryEntryMissingCashAccount');
		if (!Number.isFinite(input.netSalary) || Number(input.netSalary) <= 0) return empty('salaryEntryInvalidNet');
		const amount = Number(input.netSalary).toFixed(2);
		const narration = `Paid ${input.employeeName} (${input.employeeId}) total daily wages for the period ${input.startDate} to ${input.endDate}.`;
		return { messageKey: '', voucherType,
			cashPayment: { ledger_name: input.nonSponsorshipLedger.name, amount, narration },
			lines: [
				{ ledger_name: input.nonSponsorshipLedger.name, ledger_code: input.nonSponsorshipLedger.code, amount, side: 'Debit', narration },
				{ ledger_name: input.cashLedger.name, ledger_code: input.cashLedger.code, amount, side: 'Credit', narration }
			], debit: Number(amount), credit: Number(amount)
		};
	}
	const mainLedger = input.mainLedger;
	const employeeLedger = input.employeeLedger;
	if (!mainLedger?.name) return empty('salaryEntryMissingMainAccount');
	if (!employeeLedger?.name) return empty('salaryEntryMissingEmployeeLedger');
	if (!Number.isFinite(input.grossEarnings) || input.grossEarnings <= 0) return empty('salaryEntryInvalidGross');
	const amount = input.grossEarnings.toFixed(2);
	const narration = `Salary booking ${input.startDate} to ${input.endDate} | ${input.employeeId} - ${input.employeeName}`;
	const lines: SalaryMjvLine[] = [
		{ ledger_name: mainLedger.name, ledger_code: mainLedger.code, amount, side: 'Debit', narration },
		{ ledger_name: employeeLedger.name, ledger_code: employeeLedger.code, amount, side: 'Credit', narration }
	];
	let totalCents = Math.round(Number(amount) * 100);
	for (const deduction of SALARY_BOOKING_DEDUCTIONS) {
		const value = input.deductions?.[deduction.key] ?? 0;
		if (!Number.isFinite(value) || value < 0) return empty('salaryEntryInvalidDeduction');
		const cents = Math.round(value * 100);
		if (!cents) continue;
		const ledger = input.deductionLedgers?.[deduction.accountKey];
		if (!ledger?.name) return empty('salaryEntryMissingDeductionAccount');
		const deductionNarration = `${deduction.label} | ${input.startDate} to ${input.endDate} | ${input.employeeId} - ${input.employeeName}`;
		lines.push(
			{ ledger_name: employeeLedger.name, ledger_code: employeeLedger.code, amount: (cents / 100).toFixed(2), side: 'Debit', narration: deductionNarration },
			{ ledger_name: ledger.name, ledger_code: ledger.code, amount: (cents / 100).toFixed(2), side: 'Credit', narration: deductionNarration }
		);
		totalCents += cents;
	}
	return {
		messageKey: '',
		voucherType,
		lines,
		debit: totalCents / 100, credit: totalCents / 100
	};
}

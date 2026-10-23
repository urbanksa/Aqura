import { expect, it } from 'vitest';
import { salaryBookingPreview, SALARY_BOOKING_DEDUCTIONS } from './salaryBookingPreview';

const input = {
	employeeSponsorId: 1, branchCompanyId: 1, grossEarnings: 4320,
	employeeId: 'EMP3', employeeName: 'Employee', startDate: '2026-08-25', endDate: '2026-09-24',
	mainLedger: { name: 'Branch salary expense', code: '500' },
	employeeLedger: { name: 'Employee salary ledger', code: '1835' }
};

it('previews gross salary with the Assistant MJV line contract, debit main salary and credit employee ledger', () => {
	const result = salaryBookingPreview(input);
	expect(result.messageKey).toBe('');
	expect(result.debit).toBe(4320);
	expect(result.credit).toBe(4320);
	expect(result.lines).toEqual([
		{ ledger_name: input.mainLedger.name, ledger_code: '500', amount: '4320.00', side: 'Debit', narration: expect.stringContaining('EMP3') },
		{ ledger_name: input.employeeLedger.name, ledger_code: '1835', amount: '4320.00', side: 'Credit', narration: expect.stringContaining('2026-08-25 to 2026-09-24') }
	]);
});

it.each([
	{ change: { employeeSponsorId: null }, message: 'salaryEntryMissingNonSponsorshipAccount' },
	{ change: { branchCompanyId: null }, message: 'salaryEntryMissingBranchCompany' },
	{ change: { employeeSponsorId: 2, employeeLedger: null }, message: 'salaryEntryMissingEmployeeLedger' },
	{ change: { mainLedger: null }, message: 'salaryEntryMissingMainAccount' },
	{ change: { employeeLedger: null }, message: 'salaryEntryMissingEmployeeLedger' },
	{ change: { grossEarnings: 0 }, message: 'salaryEntryInvalidGross' },
	{ change: { grossEarnings: NaN }, message: 'salaryEntryInvalidGross' }
])('does not invent entries when $message', ({ change, message }) => {
	const result = salaryBookingPreview({ ...input, ...change });
	expect(result.messageKey).toBe(message);
	expect(result.lines).toEqual([]);
});

it.each(SALARY_BOOKING_DEDUCTIONS)('debits the employee ledger and credits the configured $label ledger', deduction => {
	const result = salaryBookingPreview({ ...input,
		deductions: { [deduction.key]: 123.45 },
		deductionLedgers: { [deduction.accountKey]: { name: deduction.label, code: '10122' } }
	});
	expect(result.lines).toHaveLength(4);
	expect(result.lines[2]).toMatchObject({ ledger_name: input.employeeLedger.name, side: 'Debit', amount: '123.45' });
	expect(result.lines[3]).toMatchObject({ ledger_name: deduction.label, side: 'Credit', amount: '123.45' });
	expect(result.debit).toBe(4443.45);
	expect(result.credit).toBe(result.debit);
});

it('does not rebook POS shortages, advances or loans, and skips zero deductions', () => {
	const result = salaryBookingPreview({ ...input, deductions: { gosi: 0, posShortage: 100, salaryAdvance: 200, loan: 300 } });
	expect(result.lines).toHaveLength(2);
	expect(result.debit).toBe(input.grossEarnings);
});

it('requires a branch posting ledger for every non-zero configured deduction', () => {
	const result = salaryBookingPreview({ ...input, deductions: { late: 5 } });
	expect(result.messageKey).toBe('salaryEntryMissingDeductionAccount');
	expect(result.lines).toEqual([]);
});

it('keeps separate deduction pairs when several types use the same ledger', () => {
	const ledger = { name: 'Attendance Deduction', code: '10122' };
	const result = salaryBookingPreview({ ...input, deductions: { late: 0.1, incomplete: 0.2 },
		deductionLedgers: { lateDeductions: ledger, incompleteDeductions: ledger } });
	expect(result.lines).toHaveLength(6);
	expect(result.lines[2].narration).toContain('Late arrival');
	expect(result.lines[4].narration).toContain('Incomplete attendance');
	expect(result.debit).toBe(4320.3);
	expect(result.credit).toBe(4320.3);
});

it.each([-1, NaN, Infinity])('rejects invalid deduction %s', value => {
	expect(salaryBookingPreview({ ...input, deductions: { gosi: value } }).messageKey).toBe('salaryEntryInvalidDeduction');
});

const cashPaymentInput = {
	...input, employeeSponsorId: null, netSalary: 3820.73, mainLedger: null, employeeLedger: null,
	nonSponsorshipLedger: { name: 'Non-sponsorship salary', code: '700' },
	cashLedger: { name: 'Statement branch cash', code: '100' },
	deductions: { gosi: 390, late: 20, posShortage: 109.27 }
};

it('shows only one balanced net-salary CP for a non-sponsored employee without an ERP employee link', () => {
	const result = salaryBookingPreview(cashPaymentInput);
	expect(result.messageKey).toBe('');
	expect(result.voucherType).toBe('CP');
	expect(result.cashPayment).toEqual({ ledger_name: 'Non-sponsorship salary', amount: '3820.73',
		narration: 'Paid Employee (EMP3) total daily wages for the period 2026-08-25 to 2026-09-24.' });
	expect(result.lines).toHaveLength(2);
	expect(result.lines[0]).toMatchObject({ ledger_name: 'Non-sponsorship salary', ledger_code: '700', side: 'Debit', amount: '3820.73' });
	expect(result.lines[1]).toMatchObject({ ledger_name: 'Statement branch cash', ledger_code: '100', side: 'Credit', amount: '3820.73' });
	expect(result.debit).toBe(3820.73);
	expect(result.credit).toBe(3820.73);
	expect(result.lines.every(line => line.narration.includes('EMP3'))).toBe(true);
});

it.each([
	{ change: { cashLedger: null }, message: 'salaryEntryMissingCashAccount' },
	{ change: { nonSponsorshipLedger: null }, message: 'salaryEntryMissingNonSponsorshipAccount' },
	{ change: { netSalary: 0 }, message: 'salaryEntryInvalidNet' },
	{ change: { netSalary: -1 }, message: 'salaryEntryInvalidNet' },
	{ change: { netSalary: NaN }, message: 'salaryEntryInvalidNet' }
])('does not invent a cash payment when $message', ({ change, message }) => {
	const result = salaryBookingPreview({ ...cashPaymentInput, ...change });
	expect(result.messageKey).toBe(message);
	expect(result.lines).toEqual([]);
});

it('keeps sponsored employees on the gross-salary MJV workflow', () => {
	expect(salaryBookingPreview({ ...cashPaymentInput, ...input }).voucherType).toBe('MJV');
});

it('previews the 1900 net-salary CP for EMP35 with no sponsor assigned', () => {
	const result = salaryBookingPreview({ ...cashPaymentInput, employeeSponsorId: null,
		employeeId: 'EMP35', employeeName: 'Zafar', grossEarnings: 2100, netSalary: 1900 });
	expect(result.messageKey).toBe('');
	expect(result.voucherType).toBe('CP');
	expect(result.lines).toHaveLength(2);
	expect(result.lines[0]).toMatchObject({ side: 'Debit', amount: '1900.00', ledger_name: 'Non-sponsorship salary' });
	expect(result.lines[1]).toMatchObject({ side: 'Credit', amount: '1900.00', ledger_name: 'Statement branch cash' });
	expect(result.debit).toBe(1900);
	expect(result.credit).toBe(1900);
});

it('still requires the statement branch company for a sponsorless employee', () => {
	const result = salaryBookingPreview({ ...cashPaymentInput, employeeSponsorId: null, branchCompanyId: null });
	expect(result.messageKey).toBe('salaryEntryMissingBranchCompany');
	expect(result.lines).toEqual([]);
});

it('shows the normal MJV for EMP100 with a sponsor different from the branch company', () => {
	const result = salaryBookingPreview({ ...input, employeeSponsorId: 2, branchCompanyId: 1,
		employeeId: 'EMP100', employeeName: 'Nayon Kumar', grossEarnings: 1800, netSalary: 1600,
		deductions: { late: 200 }, deductionLedgers: { lateDeductions: { name: 'Attendance Deduction', code: '10122' } } });
	expect(result.messageKey).toBe('');
	expect(result.voucherType).toBe('MJV');
	expect(result.cashPayment).toBeUndefined();
	expect(result.lines).toHaveLength(4);
	expect(result.lines[0]).toMatchObject({ ledger_name: input.mainLedger.name, side: 'Debit', amount: '1800.00' });
	expect(result.lines[1]).toMatchObject({ ledger_name: input.employeeLedger.name, side: 'Credit', amount: '1800.00' });
	expect(result.lines[2]).toMatchObject({ ledger_name: input.employeeLedger.name, side: 'Debit', amount: '200.00' });
	expect(result.lines[3]).toMatchObject({ ledger_name: 'Attendance Deduction', side: 'Credit', amount: '200.00' });
});

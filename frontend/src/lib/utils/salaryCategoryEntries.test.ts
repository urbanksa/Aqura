import { expect, it } from 'vitest';
import { salaryCategoryEntries, type SalaryCategoryEmployee } from './salaryCategoryEntries';

function employee(id: string, changes: Partial<SalaryCategoryEmployee> = {}): SalaryCategoryEmployee {
	return { employeeId: id, employeeName: id, employeeSponsorId: 1, branchCompanyId: 1, branchId: 3, branchName: 'Employee branch',
		grossEarnings: 2000, netSalary: 1800, netBank: 1500, netCash: 300, startDate: '2026-08-25', endDate: '2026-09-24',
		mainLedger: { name: 'Salary expense', code: '500' }, employeeLedger: { name: `${id} ledger`, code: id },
		deductions: { food: 200 }, deductionLedgers: { foodAllowanceDeduction: { name: 'Food deduction', code: '501' } },
		cashLedger: { name: 'Branch cash', code: '1000' }, nonSponsorshipLedger: { name: 'Daily wages', code: '502' },
		context: { provider: 'polosys', sponsor_provider: 'polosys', bank: { branch_id: 1, branch_name: 'Bank branch', ledger_name: 'Bank', ledger_code: '1271' },
			cross_branch_accounts: [ { source_branch_id: 1, target_branch_id: 3, ledger_name: 'Due from branch 3' }, { source_branch_id: 3, target_branch_id: 1, ledger_name: 'Due to branch 1' } ] }, ...changes };
}

it('combines booking and deduction lines into one balanced MJV per branch', () => {
	const { categories } = salaryCategoryEntries([employee('EMP1'), employee('EMP2'), employee('EMP3', { branchId: 1, branchName: 'Bank branch', netBank: 0 })]);
	expect(categories.booking).toHaveLength(2);
	const group = categories.booking.find(v => v.branchId === 3)!;
	expect(group.lines).toHaveLength(8);
	expect(group.debit).toBe(4400);
	expect(group.credit).toBe(4400);
	expect(group.lines.some(l => l.narration.includes('EMP1'))).toBe(true);
	expect(group.lines.some(l => l.narration.includes('EMP2'))).toBe(true);
});

it('separates employee-branch adjustments from bank-branch payment and combines each branch MJV', () => {
	const { categories } = salaryCategoryEntries([employee('EMP1'), employee('EMP2')]);
	expect(categories.adjustments).toHaveLength(1);
	expect(categories.adjustments[0]).toMatchObject({ branchId: 3, debit: 3000, credit: 3000 });
	expect(categories.adjustments[0].lines.map(l => l.ledger_name)).toEqual(['EMP1 ledger', 'Due to branch 1', 'EMP2 ledger', 'Due to branch 1']);
	expect(categories.bankPolosys).toHaveLength(1);
	expect(categories.bankPolosys[0]).toMatchObject({ branchId: 1, debit: 3000, credit: 3000 });
	expect(categories.bankPolosys[0].lines.map(l => l.ledger_name)).toEqual(['Due from branch 3', 'Bank', 'Due from branch 3', 'Bank']);
});

it('keeps same-branch bank payments entirely in Bank Payment (Polosys)', () => {
	const { categories } = salaryCategoryEntries([employee('EMP1', { branchId: 1, branchName: 'Bank branch' })]);
	expect(categories.adjustments).toEqual([]);
	expect(categories.bankPolosys[0].lines.map(l => l.ledger_name)).toEqual(['EMP1 ledger', 'Bank']);
});

function vikinEmployee(id: string, changes: Partial<SalaryCategoryEmployee> = {}): SalaryCategoryEmployee {
	return employee(id, { employeeSponsorId: 2, context: {
		provider: 'polosys', sponsor_provider: 'vikin', sponsor_name: 'Sponsor A', sponsor_name_ar: 'الكفيل أ',
		sponsor_adjustment: { branch_id: 3, ledger_name: 'Sponsor ledger', ledger_code: '1501' },
		vikin_employee_ledger: { employee_id: id, ledger_name: `${id} Vikin ledger`, ledger_code: `EP${id}` },
		vikin_branch_adjustment: { branch_id: 3, ledger_name: 'Branch in Vikin', ledger_code: 'AL98' },
		vikin_bank: { ledger_name: 'Vikin bank', ledger_code: 'BK2' }
	}, ...changes });
}

it('uses the real sponsor account in Polosys and combines Vikin adjustment and bank lines for a branch and company', () => {
	const { categories } = salaryCategoryEntries([vikinEmployee('EMP1'), vikinEmployee('EMP2')]);
	expect(categories.bankPolosys).toEqual([]);
	expect(categories.adjustments).toHaveLength(1);
	expect(categories.adjustments[0].lines.filter(l => l.side === 'Credit').every(l => l.ledger_code === '1501')).toBe(true);
	expect(categories.adjustmentsVikin).toHaveLength(1);
	expect(categories.adjustmentsVikin[0]).toMatchObject({
		key: '3:2', branchId: 3, companyId: 2, companyName: 'Sponsor A', voucherType: 'JV', debit: 3000, credit: 3000,
		employees: [{ employeeId: 'EMP1', amount: 1500 }, { employeeId: 'EMP2', amount: 1500 }]
	});
	expect(categories.adjustmentsVikin[0].lines.map(line => [line.ledger_code, line.side])).toEqual([
		['AL98', 'Debit'], ['EPEMP1', 'Credit'], ['AL98', 'Debit'], ['EPEMP2', 'Credit']
	]);
	expect(categories.adjustmentsVikin[0].lines.map(line => line.narration)).toEqual([
		expect.stringContaining('EMP1'), expect.stringContaining('EMP1'), expect.stringContaining('EMP2'), expect.stringContaining('EMP2')
	]);
	expect(categories.adjustmentsVikin[0].employeeName).toBeUndefined();
	expect(categories.bankVikin).toHaveLength(1);
	expect(categories.bankVikin[0]).toMatchObject({ companyId: 2, debit: 3000, credit: 3000,
		employees: [{ employeeId: 'EMP1', amount: 1500 }, { employeeId: 'EMP2', amount: 1500 }] });
	expect(categories.bankVikin[0].lines.map(line => [line.ledger_code, line.side])).toEqual([
		['EPEMP1', 'Debit'], ['BK2', 'Credit'], ['EPEMP2', 'Debit'], ['BK2', 'Credit']
	]);
	for (const voucher of categories.bankVikin) {
		expect(voucher.voucherType).toBe('JV');
		expect(voucher.lines).toHaveLength(4);
		expect(voucher.debit).toBe(voucher.credit);
		expect(voucher.lines.every(l => !l.placeholder && !!l.ledger_code)).toBe(true);
	}
});

it('keeps different Vikin companies and statement branches in separate combined JVs', () => {
	const otherBranch = vikinEmployee('EMP3', { branchId: 4, branchName: 'Other branch' });
	otherBranch.context.vikin_branch_adjustment = { branch_id: 4, ledger_name: 'Other branch in Vikin', ledger_code: 'AL99' };
	const { categories } = salaryCategoryEntries([
		vikinEmployee('EMP1'), vikinEmployee('EMP2', { employeeSponsorId: 8 }), otherBranch
	]);
	expect(categories.adjustmentsVikin).toHaveLength(3);
	expect(categories.adjustmentsVikin.map(voucher => voucher.key).sort()).toEqual(['3:2', '3:8', '4:2']);
	expect(categories.adjustmentsVikin.every(voucher => voucher.lines.length === 2 && voucher.employees?.length === 1)).toBe(true);
	expect(categories.bankVikin).toHaveLength(3);
	expect(categories.bankVikin.map(voucher => voucher.key).sort()).toEqual(['3:2', '3:8', '4:2']);
	expect(categories.bankVikin.every(voucher => voucher.lines.length === 2 && voucher.employees?.length === 1)).toBe(true);
});

it('excludes invalid Vikin employee links from a combined JV and reports the affected employee', () => {
	const missingLink = vikinEmployee('EMP2');
	missingLink.context.vikin_employee_ledger = null;
	const { categories, issues } = salaryCategoryEntries([vikinEmployee('EMP1'), missingLink]);
	expect(categories.adjustmentsVikin).toHaveLength(1);
	expect(categories.adjustmentsVikin[0].employees).toEqual([{ employeeId: 'EMP1', amount: 1500 }]);
	expect(issues.adjustmentsVikin).toEqual([expect.objectContaining({ employeeId: 'EMP2', messageKey: 'salaryPaymentMissingVikinEmployeeLedger' })]);
	expect(categories.bankVikin[0].employees).toEqual([{ employeeId: 'EMP1', amount: 1500 }]);
	expect(issues.bankVikin).toEqual([expect.objectContaining({ employeeId: 'EMP2', messageKey: 'salaryPaymentMissingVikinEmployeeLedger' })]);
});

it('keeps employee amounts and localized company names in combined Vikin adjustment JVs', () => {
	const { categories } = salaryCategoryEntries([vikinEmployee('EMP1', { netBank: 100.11 }), vikinEmployee('EMP2', { netBank: 200.22 })], 'ar');
	expect(categories.adjustmentsVikin[0]).toMatchObject({ companyName: 'الكفيل أ', debit: 300.33, credit: 300.33,
		employees: [{ employeeId: 'EMP1', amount: 100.11 }, { employeeId: 'EMP2', amount: 200.22 }] });
});

it('keeps CPs separate under their branch and includes non-sponsored daily wage CPs once', () => {
	const { categories } = salaryCategoryEntries([employee('EMP1'), employee('EMP2'), employee('EMP3', { employeeSponsorId: null })]);
	expect(categories.cash).toHaveLength(3);
	expect(categories.cash.map(v => v.debit)).toEqual([300, 300, 1800]);
	expect(categories.cash.every(v => v.voucherType === 'CP' && v.branchId === 3 && v.paidFrom?.code === '1000')).toBe(true);
	expect(categories.booking[0].lines.some(l => l.narration.includes('EMP3'))).toBe(false);
});

it('reports missing configuration per category without hiding other valid categories', () => {
	const { categories, issues } = salaryCategoryEntries([employee('EMP1', { deductionLedgers: {} })]);
	expect(categories.booking).toEqual([]);
	expect(issues.booking[0].messageKey).toBe('salaryEntryMissingDeductionAccount');
	expect(categories.adjustments).toHaveLength(1);
	expect(categories.bankPolosys).toHaveLength(1);
	expect(categories.cash).toHaveLength(1);
});

it('does not duplicate booking or payment rows across categories and balances all vouchers', () => {
	const { categories } = salaryCategoryEntries([employee('EMP1'), employee('EMP2')]);
	for (const vouchers of Object.values(categories)) for (const voucher of vouchers) expect(voucher.debit).toBe(voucher.credit);
	expect(categories.bankVikin).toEqual([]);
	expect(categories.booking[0].debit).toBe(4400);
	expect(categories.adjustments[0].debit).toBe(3000);
	expect(categories.bankPolosys[0].debit).toBe(3000);
});

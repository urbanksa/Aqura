import { expect, it } from 'vitest';
import { salaryPaymentPreview, salaryCashPaymentPreview, salaryVikinPaymentPreview } from './salaryPaymentPreview';

const input = {
	context: { provider: 'polosys', bank: { branch_id: 1, branch_name: 'Paying branch', ledger_name: 'Salary bank', ledger_code: '1271' },
		cross_branch_accounts: [
			{ source_branch_id: 1, target_branch_id: 3, ledger_name: 'Due from employee branch' },
			{ source_branch_id: 3, target_branch_id: 1, ledger_name: 'Due to paying branch' }
		] },
	netBank: 1300, branchId: 3, branchName: 'Employee branch', employeeLedger: { name: 'Employee ledger', code: '2360' },
	employeeId: 'EMP100', employeeName: 'Employee', startDate: '2026-08-25', endDate: '2026-09-24'
};

const cashInput = { ...input, provider: 'polosys', netCash: 300, cashLedger: { name: 'Branch cash', code: '1000' } };
it('shows the real Vikin employee debit and salary-paying bank credit', () => {
	const context = { ...input.context, sponsor_provider: 'vikin', sponsor_name: 'Sponsor A',
		vikin_employee_ledger: { employee_id: 'EMP100', ledger_name: 'Vikin employee', ledger_code: 'EP1' },
		vikin_bank: { ledger_name: 'Vikin salary bank', ledger_code: 'BK2' } };
	const result = salaryVikinPaymentPreview({ ...input, context });
	expect(result.lines).toEqual([
		{ ledger_name: 'Vikin employee', ledger_code: 'EP1', amount: '1300.00', side: 'Debit', narration: expect.stringContaining('Employee branch') },
		{ ledger_name: 'Vikin salary bank', ledger_code: 'BK2', amount: '1300.00', side: 'Credit', narration: expect.stringContaining('2026-08-25 to 2026-09-24') }
	]);
	expect(result.total).toBe(1300);
	expect(result.lines.every(l => l.narration.includes('EMP100'))).toBe(true);
	expect(result.lines.some(l => l.ledger_name.includes('Employee ledger'))).toBe(false);
});
it('requires Vikin employee and bank links before generating bank payment lines', () => {
	const context = { sponsor_provider: 'vikin', sponsor_name: 'Sponsor A' };
	expect(salaryVikinPaymentPreview({ ...input, context }).messageKey).toBe('salaryPaymentMissingVikinEmployeeLedger');
	const linkedEmployee = { ...context, vikin_employee_ledger: { employee_id: 'EMP100', ledger_name: 'Vikin employee', ledger_code: 'EP1' } };
	expect(salaryVikinPaymentPreview({ ...input, context: linkedEmployee }).messageKey).toBe('salaryPaymentMissingVikinBank');
	expect(salaryVikinPaymentPreview({ ...input, context: { ...linkedEmployee,
		vikin_employee_ledger: { ...linkedEmployee.vikin_employee_ledger, employee_id: 'EMP999' },
		vikin_bank: { ledger_name: 'Vikin salary bank', ledger_code: 'BK2' }
	} }).messageKey).toBe('salaryPaymentMissingVikinEmployeeLedger');
});
it.each(['polosys', null, undefined])('does not add a Vikin JV for sponsor ERP %s', sponsor_provider => {
	expect(salaryVikinPaymentPreview({ ...input, context: { ...input.context, sponsor_provider } }).lines).toEqual([]);
});
it.each([0, -1, NaN, Infinity])('does not create a Vikin payment for amount %s', netBank => {
	expect(salaryVikinPaymentPreview({ ...input, netBank, context: { sponsor_provider: 'vikin', sponsor_name: 'Sponsor A' } }).lines).toEqual([]);
});
it('routes Vikin-funded payment directly through the employee branch without an unrelated bank branch', () => {
	const result = salaryPaymentPreview({ ...input, context: { ...input.context, sponsor_provider: 'vikin', sponsor_name: 'Sponsor A', sponsor_adjustment: { branch_id: 3, ledger_name: 'Linked Sponsor Ledger', ledger_code: '1501' } } });
	expect(result.groups).toHaveLength(1);
	expect(result.groups[0].branchId).toBe(3);
	expect(result.groups[0].lines.map(l => [l.ledger_name, l.side, l.amount])).toEqual([
		['Employee ledger', 'Debit', '1300.00'], ['Linked Sponsor Ledger', 'Credit', '1300.00']
	]);
	expect(result.groups[0].lines[1]).toMatchObject({ ledger_code: '1501' });
	expect(result.groups[0].lines.every(l => !l.narration.includes('Paying branch'))).toBe(true);
});
it('requires no Polosys bank or reciprocal branch accounts when Vikin funds the payment', () => {
	const result = salaryPaymentPreview({ ...input, context: { provider: 'polosys', sponsor_provider: 'vikin', sponsor_name: 'Sponsor A', sponsor_adjustment: { branch_id: 3, ledger_name: 'Linked Sponsor Ledger', ledger_code: '1501' } } });
	expect(result.messageKey).toBe('');
	expect(result.groups).toHaveLength(1);
	expect(result.groups[0].branchId).toBe(input.branchId);
});
it('uses the linked company adjustment ledger for the selected statement branch', () => {
	const result = salaryPaymentPreview({ ...input, branchId: 3, context: { ...input.context, sponsor_provider: 'vikin', sponsor_name: 'Sponsor A', sponsor_adjustment: { branch_id: 3, ledger_name: 'Linked Sponsor Ledger', ledger_code: '1501' }, cross_branch_accounts: [] } });
	expect(result.groups).toHaveLength(1);
	expect(result.groups[0].lines[1]).toMatchObject({ ledger_name: 'Linked Sponsor Ledger', amount: '1300.00', side: 'Credit', ledger_code: '1501' });
});
it('preserves real bank credit for Polosys sponsors', () => {
	const result = salaryPaymentPreview({ ...input, context: { ...input.context, sponsor_provider: 'polosys', sponsor_name: 'Sponsor A' } });
	expect(result).toEqual(salaryPaymentPreview(input));
});
it('requires an adjustment mapping for the exact employee branch', () => {
 const context = { ...input.context, sponsor_provider: 'vikin', sponsor_name: 'Sponsor A' };
 expect(salaryPaymentPreview({ ...input, context }).messageKey).toBe('salaryPaymentMissingCompanyAdjustment');
 expect(salaryPaymentPreview({ ...input, context: { ...context, sponsor_adjustment: { branch_id: 1, ledger_name: 'Wrong branch', ledger_code: '123' } } }).messageKey).toBe('salaryPaymentMissingCompanyAdjustment');
});
it('previews a single CP debit for Net Cash paid from branch cash, separate from Net Bank', () => {
	const result = salaryCashPaymentPreview(cashInput);
	expect(result.messageKey).toBe('');
	expect(result.payment).toMatchObject({ ledger_name: 'Employee ledger', ledger_code: '2360', amount: '300.00', side: 'Debit', paidFrom: cashInput.cashLedger });
	expect(result.payment?.narration).toContain('EMP100');
	expect(result.payment?.narration).toContain('2026-08-25 to 2026-09-24');
	expect(salaryPaymentPreview(input).groups[0].total).toBe(1300);
});
it.each([0, 0.001])('does not create a zero CP for %s', netCash => {
	expect(salaryCashPaymentPreview({ ...cashInput, netCash }).payment).toBeNull();
});
it.each([-1, NaN, Infinity])('rejects invalid cash amounts %s', netCash => {
	expect(salaryCashPaymentPreview({ ...cashInput, netCash }).messageKey).toBe('salaryCashPaymentInvalidAmount');
});
it('requires cash and employee ledgers and limits cash previews to Polosys', () => {
	expect(salaryCashPaymentPreview({ ...cashInput, cashLedger: null }).messageKey).toBe('salaryEntryMissingCashAccount');
	expect(salaryCashPaymentPreview({ ...cashInput, employeeLedger: null }).messageKey).toBe('salaryEntryMissingEmployeeLedger');
	expect(salaryCashPaymentPreview({ ...cashInput, provider: 'vikin' }).payment).toBeNull();
});

it('balances each branch independently for cross-branch payment using Net Bank only', () => {
	const result = salaryPaymentPreview(input);
	expect(result.messageKey).toBe('');
	expect(result.groups.map(g => g.branchId)).toEqual([1, 3]);
	expect(result.groups.flatMap(g => g.lines.map(l => [l.ledger_name, l.side, l.amount]))).toEqual([
		['Due from employee branch', 'Debit', '1300.00'], ['Salary bank', 'Credit', '1300.00'],
		['Employee ledger', 'Debit', '1300.00'], ['Due to paying branch', 'Credit', '1300.00']
	]);
	for (const group of result.groups) {
		expect(group.lines.filter(l => l.side === 'Debit').reduce((s,l) => s + Number(l.amount),0)).toBe(group.total);
		expect(group.lines.filter(l => l.side === 'Credit').reduce((s,l) => s + Number(l.amount),0)).toBe(group.total);
		expect(group.lines.every(l => l.narration.includes('EMP100') && l.narration.includes('2026-09-24'))).toBe(true);
	}
});

it('uses a single balanced MJV without adjustment ledgers for same-branch payment', () => {
	const result = salaryPaymentPreview({ ...input, branchId: 1, context: { ...input.context, cross_branch_accounts: [] } });
	expect(result.groups).toHaveLength(1);
	expect(result.groups[0].lines.map(l => [l.ledger_name, l.side])).toEqual([['Employee ledger','Debit'],['Salary bank','Credit']]);
});

it.each(['vikin', null, undefined])('does not create payments for provider %s', provider => {
	expect(salaryPaymentPreview({ ...input, context: { ...input.context, provider } }).groups).toEqual([]);
});

it.each([[], [input.context.cross_branch_accounts[0]], [input.context.cross_branch_accounts[1]]].map(accounts => ({ accounts })))('requires both directions of cross-branch mapping', ({ accounts }) => {
	const result = salaryPaymentPreview({ ...input, context: { ...input.context, cross_branch_accounts: accounts } });
	expect(result.messageKey).toBe('salaryPaymentMissingAdjustments');
	expect(result.groups).toEqual([]);
});

it('does not produce an entry without a sponsor bank or employee ledger', () => {
	expect(salaryPaymentPreview({ ...input, context: { provider: 'polosys' } }).messageKey).toBe('salaryPaymentMissingBank');
	expect(salaryPaymentPreview({ ...input, employeeLedger: null }).messageKey).toBe('salaryEntryMissingEmployeeLedger');
});

it.each([NaN, Infinity, -1])('rejects invalid Net Bank amount %s', netBank => {
	expect(salaryPaymentPreview({ ...input, netBank }).messageKey).toBe('salaryPaymentInvalidAmount');
});

it('skips zero bank payments and rounds the same amount on both sides', () => {
	expect(salaryPaymentPreview({ ...input, netBank: 0 }).messageKey).toBe('salaryPaymentZero');
	expect(salaryPaymentPreview({ ...input, netBank: 12.345 }).groups.flatMap(g => g.lines).every(l => l.amount === '12.35')).toBe(true);
});

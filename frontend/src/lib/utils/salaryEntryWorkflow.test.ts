import { expect, it } from 'vitest';
import { SALARY_ENTRY_CATEGORIES, salaryCategoryEntries, type SalaryCategoryEmployee, type SalaryCategoryVoucher, type SalaryEntryCategory } from './salaryCategoryEntries';
import { canSaveSalaryEntries, salaryEntrySavePayload, savedSalaryCategoryEntries, type SavedSalaryEntryBundle } from './salaryEntryWorkflow';

const employee: SalaryCategoryEmployee = { employeeId: 'EMP3', employeeName: 'Employee', employeeSponsorId: null,
	branchCompanyId: 1, branchId: 1, branchName: 'Branch', grossEarnings: 1000, netSalary: 900, netBank: 0, netCash: 900,
	startDate: '2026-08-25', endDate: '2026-09-24', mainLedger: null, employeeLedger: null,
	nonSponsorshipLedger: { name: 'Daily wages', code: '1256' }, cashLedger: { name: 'Cash', code: '1000' }, context: {} };

function vikinEmployee(id: string, netBank = 900): SalaryCategoryEmployee {
	return { ...employee, employeeId: id, employeeName: id, employeeSponsorId: 2, netBank, netCash: 0,
		mainLedger: { name: 'Salary expense', code: '500' }, employeeLedger: { name: `${id} Polosys`, code: `P${id}` },
		context: { provider: 'polosys', sponsor_provider: 'vikin', sponsor_name: 'Sponsor', sponsor_name_ar: 'الكفيل',
			sponsor_adjustment: { branch_id: 1, ledger_name: 'Sponsor adjustment', ledger_code: '1501' },
			vikin_employee_ledger: { employee_id: id, ledger_name: `${id} Vikin`, ledger_code: `EP${id}` },
			vikin_branch_adjustment: { branch_id: 1, ledger_name: 'Branch in Vikin', ledger_code: 'AL98' },
			vikin_bank: { ledger_name: 'Vikin bank', ledger_code: 'BK2' }
		} };
}

function savedVoucher(voucher: SalaryCategoryVoucher, category: SalaryEntryCategory): SavedSalaryEntryBundle['vouchers'][number] {
	return { id: `saved-${category}`, category, branch_id: voucher.branchId, branch_name: 'Saved branch',
		employee_id: category === 'cash' ? voucher.key : '', employee_name: voucher.employeeName,
		company_id: voucher.companyId, company_name: 'Saved sponsor', company_name_ar: 'الكفيل المحفوظ',
		employee_ids: voucher.employees?.map(employee => employee.employeeId),
		employee_entries: voucher.employees?.map(employee => ({ employee_id: employee.employeeId, amount: employee.amount })),
		voucher_type: voucher.voucherType, lines: voucher.lines, debit_total: voucher.debit, credit_total: voucher.credit,
		paid_from: voucher.paidFrom, task_status: 'saved' };
}

function legacyBundle(): SavedSalaryEntryBundle {
	return { id: 'batch', statement_id: 'statement', vikin_entries_saved: false,
		vouchers: [savedVoucher(salaryCategoryEntries([employee]).categories.cash[0], 'cash')] };
}

it('saves CPs individually', () => {
	const result = salaryCategoryEntries([employee, { ...employee, employeeId: 'EMP4' }]);
	expect(canSaveSalaryEntries(result)).toBe(true);
	const payload = salaryEntrySavePayload(result);
	expect(payload).toHaveLength(2);
	expect(payload.map(v => v.employee_id)).toEqual(['EMP3', 'EMP4']);
	expect(payload.every(v => v.category === 'cash')).toBe(true);
});
it('saves both Vikin categories with company and employee allocations beside the ordinary vouchers', () => {
	const result = salaryCategoryEntries([employee, vikinEmployee('EMP1'), vikinEmployee('EMP2', 1200)]);
	expect(canSaveSalaryEntries(result)).toBe(true);
	const payload = salaryEntrySavePayload(result);
	expect(payload.some(voucher => voucher.category === 'cash')).toBe(true);
	expect(payload.some(voucher => voucher.category === 'booking')).toBe(true);
	const vikin = payload.filter(voucher => ['adjustmentsVikin', 'bankVikin'].includes(voucher.category));
	expect(vikin).toHaveLength(2);
	for (const voucher of vikin) {
		expect(voucher).toMatchObject({ company_id: 2, voucher_type: 'JV', branch_id: 1, employee_id: '',
			employee_ids: ['EMP1', 'EMP2'], employee_entries: [{ employee_id: 'EMP1', amount: 900 }, { employee_id: 'EMP2', amount: 1200 }] });
		expect(voucher.lines).toHaveLength(4);
	}
	expect(vikin.find(voucher => voucher.category === 'bankVikin')?.lines.map(line => line.ledger_code)).toEqual(['EPEMP1', 'BK2', 'EPEMP2', 'BK2']);
});

it.each(SALARY_ENTRY_CATEGORIES)('blocks Save All for an error in category %s', category => {
	const result = salaryCategoryEntries([employee]);
	result.issues[category].push({ employeeId: 'EMP9', employeeName: 'Missing', messageKey: 'salaryEntryMissingEmployeeLedger' });
	expect(canSaveSalaryEntries(result)).toBe(false);
	expect(() => salaryEntrySavePayload(result)).toThrow();
});

it('requires generated entries and rejects an empty new batch', () => {
	expect(canSaveSalaryEntries(null)).toBe(false);
	expect(canSaveSalaryEntries(salaryCategoryEntries([]))).toBe(false);
});
it('displays the immutable saved lines and IDs instead of freshly generated amounts', () => {
	const generated = salaryCategoryEntries([employee]);
	const bundle: SavedSalaryEntryBundle = { id: 'batch', statement_id: 'statement', vouchers: [{ id: 'voucher', category: 'cash',
		branch_id: 1, branch_name: 'Saved branch', employee_id: 'EMP3', employee_name: 'Saved name', voucher_type: 'CP',
		lines: generated.categories.cash[0].lines, debit_total: 900, credit_total: 900, task_status: 'completed', task_id: 'task', paid_from: employee.cashLedger! }] };
	const view = savedSalaryCategoryEntries(bundle, salaryCategoryEntries([{ ...employee, netSalary: 2000 }]));
	expect(view.categories.cash[0]).toMatchObject({ key: 'voucher', debit: 900, branchName: 'Saved branch', employeeName: 'Saved name' });
	expect(view.categories.cash[0].lines[0].amount).toBe('900.00');
});

it('appends only Vikin entries to a legacy batch while preserving frozen Polosys and CP entries', () => {
	const generated = salaryCategoryEntries([vikinEmployee('EMP1')]);
	generated.issues.booking.push({ employeeId: 'EMP1', employeeName: 'Changed ledger', messageKey: 'salaryEntryMissingMainAccount' });
	const bundle = legacyBundle();
	expect(canSaveSalaryEntries(generated, bundle)).toBe(true);
	const payload = salaryEntrySavePayload(generated, bundle);
	expect(payload.map(voucher => voucher.category)).toEqual(['adjustmentsVikin', 'bankVikin']);
	const view = savedSalaryCategoryEntries(bundle, generated);
	expect(view.categories.cash[0]).toMatchObject({ key: 'saved-cash', debit: 900, branchName: 'Saved branch' });
	expect(view.issues.booking).toEqual([]);
	expect(view.categories.adjustmentsVikin).toEqual(generated.categories.adjustmentsVikin);
	expect(view.categories.bankVikin).toEqual(generated.categories.bankVikin);
});

it.each(['adjustmentsVikin', 'bankVikin'] as const)('blocks a legacy supplement when %s contains a missing ledger', category => {
	const generated = salaryCategoryEntries([vikinEmployee('EMP1')]);
	generated.issues[category].push({ employeeId: 'EMP1', employeeName: 'Missing', messageKey: 'salaryPaymentMissingVikinEmployeeLedger' });
	expect(canSaveSalaryEntries(generated, legacyBundle())).toBe(false);
	expect(() => salaryEntrySavePayload(generated, legacyBundle())).toThrow();
});

it('allows a legacy batch with no Vikin employees to record its one-time empty supplement', () => {
	const generated = salaryCategoryEntries([employee]);
	expect(canSaveSalaryEntries(generated, legacyBundle())).toBe(true);
	expect(salaryEntrySavePayload(generated, legacyBundle())).toEqual([]);
	expect(canSaveSalaryEntries(null, legacyBundle())).toBe(false);
});

it('freezes both Vikin categories after saving and prevents any later save or supplement', () => {
	const original = salaryCategoryEntries([vikinEmployee('EMP1')]);
	const bundle: SavedSalaryEntryBundle = { ...legacyBundle(), vikin_entries_saved: true, vouchers: [
		...legacyBundle().vouchers,
		savedVoucher(original.categories.adjustmentsVikin[0], 'adjustmentsVikin'),
		savedVoucher(original.categories.bankVikin[0], 'bankVikin')
	] };
	const generated = salaryCategoryEntries([vikinEmployee('EMP1', 5000)]);
	generated.issues.bankVikin.push({ employeeId: 'EMP1', employeeName: 'Missing', messageKey: 'salaryPaymentMissingVikinBank' });
	const view = savedSalaryCategoryEntries(bundle, generated, 'ar');
	for (const category of ['adjustmentsVikin', 'bankVikin'] as const) {
		expect(view.categories[category][0]).toMatchObject({ key: `saved-${category}`, debit: 900, credit: 900, companyId: 2,
			companyName: 'الكفيل المحفوظ', employees: [{ employeeId: 'EMP1', amount: 900 }] });
		expect(view.categories[category][0].lines.every(line => line.amount === '900.00')).toBe(true);
		expect(view.issues[category]).toEqual([]);
	}
	expect(canSaveSalaryEntries(generated, bundle)).toBe(false);
	expect(() => salaryEntrySavePayload(generated, bundle)).toThrow();
});

it('keeps Vikin categories empty after an empty supplement has been saved', () => {
	const bundle = { ...legacyBundle(), vikin_entries_saved: true };
	const view = savedSalaryCategoryEntries(bundle, salaryCategoryEntries([vikinEmployee('EMP1')]));
	expect(view.categories.adjustmentsVikin).toEqual([]);
	expect(view.categories.bankVikin).toEqual([]);
});

import { SALARY_ENTRY_CATEGORIES, type SalaryCategoryVoucher, type SalaryEntryCategory, type salaryCategoryEntries } from './salaryCategoryEntries';
export type SalaryEntryResult = ReturnType<typeof salaryCategoryEntries>;
export type SavedSalaryEntryBundle = { id: string; statement_id: string; vikin_entries_saved?: boolean; vouchers: {
	id: string; category: SalaryEntryCategory; branch_id: number; branch_name: string; employee_id?: string | null; employee_name?: string;
	company_id?: number | null; company_name?: string; company_name_ar?: string; employee_ids?: string[];
	employee_entries?: { employee_id: string; amount: number | string }[];
	voucher_type: 'MJV' | 'CP' | 'JV'; lines: SalaryCategoryVoucher['lines']; debit_total: number; credit_total: number;
	paid_from?: { name: string; code: string }; task_id?: string; task_status: string; assigned_user_name?: string; voucher_date?: string;
}[] };
export const SAVABLE_SALARY_CATEGORIES = SALARY_ENTRY_CATEGORIES;
export const VIKIN_SALARY_CATEGORIES: readonly SalaryEntryCategory[] = ['adjustmentsVikin', 'bankVikin'];
function categoriesToSave(bundle: SavedSalaryEntryBundle | null) {
	return bundle ? bundle.vikin_entries_saved === true ? [] : VIKIN_SALARY_CATEGORIES : SAVABLE_SALARY_CATEGORIES;
}
export function canSaveSalaryEntries(result: SalaryEntryResult | null, bundle: SavedSalaryEntryBundle | null = null) {
	const categories = categoriesToSave(bundle);
	return !!result && categories.length > 0 && categories.every(category => result.issues[category].length === 0)
		&& (!!bundle || categories.some(category => result.categories[category].length > 0));
}
export function salaryEntrySavePayload(result: SalaryEntryResult, bundle: SavedSalaryEntryBundle | null = null) {
	if (!canSaveSalaryEntries(result, bundle)) throw new Error('Fix all entry errors before saving.');
	return categoriesToSave(bundle).flatMap(category => result.categories[category].map(voucher => ({
		category, branch_id: voucher.branchId, branch_name: voucher.branchName,
		voucher_type: voucher.voucherType,
		employee_id: category === 'cash' ? voucher.key : '', employee_name: voucher.employeeName,
		...(VIKIN_SALARY_CATEGORIES.includes(category) ? {
			company_id: voucher.companyId, employee_ids: (voucher.employees || []).map(employee => employee.employeeId),
			employee_entries: (voucher.employees || []).map(employee => ({ employee_id: employee.employeeId, amount: employee.amount }))
		} : {}),
		lines: voucher.lines, paid_from: voucher.paidFrom
	})));
}
export function savedSalaryCategoryEntries(bundle: SavedSalaryEntryBundle, generated: SalaryEntryResult, language = 'en'): SalaryEntryResult {
	const categories = { ...generated.categories };
	const issues = { ...generated.issues };
	for (const category of SAVABLE_SALARY_CATEGORIES) {
		if (VIKIN_SALARY_CATEGORIES.includes(category) && bundle.vikin_entries_saved !== true) continue;
		categories[category] = bundle.vouchers.filter(v => v.category === category).map(v => ({
			key: v.id, branchId: Number(v.branch_id), branchName: v.branch_name, voucherType: v.voucher_type,
			employeeName: v.employee_name, paidFrom: v.paid_from, lines: v.lines,
			companyId: v.company_id == null ? undefined : Number(v.company_id),
			companyName: language === 'ar' ? v.company_name_ar || v.company_name : v.company_name || v.company_name_ar,
			employees: v.employee_entries?.map(employee => ({ employeeId: employee.employee_id, amount: Number(employee.amount) })),
			debit: Number(v.debit_total), credit: Number(v.credit_total)
		}));
		issues[category] = [];
	}
	return { categories, issues };
}

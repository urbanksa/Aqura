import { expect, it } from 'vitest';
import { applySavedSalaryEmployeeNames, type SavedSalaryEmployeeContext } from './savedSalaryEmployeeContext';

const employee: SavedSalaryEmployeeContext = { id: 'EMP23', name_en: 'Rashad', name_ar: 'رشاد', id_number: '123',
	sponsor_id: null, erp_employee_id_mapping: {}, sponsor_name_en: null, sponsor_name_ar: null };

it('restores both language names by employee ID for an older Arabic-only salary snapshot', () => {
	const row = { employeeId: 'EMP23', employeeName: 'رشاد', currentBranchId: 1, netSalary: 1800 };
	const [result] = applySavedSalaryEmployeeNames([row], [employee]);
	expect(result).toEqual({ ...row, employeeNameEn: 'Rashad', employeeNameAr: 'رشاد', idNumber: '123' });
	expect(row).not.toHaveProperty('employeeNameEn');
});

it('keeps saved names when a language is missing and leaves unrelated employees untouched', () => {
	const rows = [{ employeeId: 'EMP23', employeeNameEn: 'Saved name' }, { employeeId: 'EMP24', employeeNameEn: 'Other' }];
	const result = applySavedSalaryEmployeeNames(rows, [{ ...employee, name_en: null }]);
	expect(result[0].employeeNameEn).toBe('Saved name');
	expect(result[1]).toBe(rows[1]);
});

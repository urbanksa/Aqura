export type SavedSalaryEmployeeContext = {
	id: string; name_en: string | null; name_ar: string | null; id_number: string | null;
	sponsor_id: number | null; erp_employee_id_mapping: Record<string, number> | null;
	sponsor_name_en: string | null; sponsor_name_ar: string | null;
};

export function applySavedSalaryEmployeeNames<T extends { employeeId: string; employeeNameEn?: string; employeeNameAr?: string }>(
	rows: T[], employees: SavedSalaryEmployeeContext[]
) {
	const byId = new Map(employees.map(employee => [String(employee.id), employee]));
	return rows.map(row => {
		const employee = byId.get(String(row.employeeId));
		return employee ? { ...row, employeeNameEn: employee.name_en || row.employeeNameEn,
			employeeNameAr: employee.name_ar || row.employeeNameAr, idNumber: employee.id_number } : row;
	});
}

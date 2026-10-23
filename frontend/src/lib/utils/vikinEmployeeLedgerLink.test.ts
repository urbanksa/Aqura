import { describe, expect, it, vi } from 'vitest';
import { loadVikinEmployeeLink, saveVikinEmployeeLink } from './vikinEmployeeLedgerLink';

function context(employeeId = 'EMP15') {
	return {
		employee_id: employeeId,
		company: { id: 2, name_en: 'Sponsor Company', name_ar: 'الشركة' },
		ledgers: [{ id: 'ledger-1', ledger_code: 'EP1', ledger_name: 'Employee Ledger', account_group_name: 'Salary Payable' }],
		link: null
	};
}

describe('Vikin employee ledger links', () => {
	it('loads the selected employee’s company-scoped link context', async () => {
		const expected = context();
		const client = { rpc: vi.fn().mockResolvedValue({ data: expected, error: null }) };
		expect(await loadVikinEmployeeLink(client, 'EMP15')).toEqual(expected);
		expect(client.rpc).toHaveBeenCalledTimes(1);
		expect(client.rpc).toHaveBeenCalledWith('get_vikin_employee_link_context', { p_employee_id: 'EMP15' });
	});

	it('saves only the employee and selected ledger identifiers for planning', async () => {
		const expected = { ...context(), link: { ledger_id: 'ledger-1' } };
		const client = { rpc: vi.fn().mockResolvedValue({ data: expected, error: null }) };
		expect((await saveVikinEmployeeLink(client, 'EMP15', 'ledger-1')).link?.ledger_id).toBe('ledger-1');
		expect(client.rpc).toHaveBeenCalledTimes(1);
		expect(client.rpc).toHaveBeenCalledWith('set_vikin_employee_ledger_link', { p_employee_id: 'EMP15', p_ledger_id: 'ledger-1' });
	});

	it('unlinks without sending or changing existing Polosys mappings', async () => {
		const client = { rpc: vi.fn().mockResolvedValue({ data: context(), error: null }) };
		expect((await saveVikinEmployeeLink(client, 'EMP15', null)).link).toBeNull();
		expect(client.rpc).toHaveBeenCalledTimes(1);
		expect(client.rpc).toHaveBeenCalledWith('set_vikin_employee_ledger_link', { p_employee_id: 'EMP15', p_ledger_id: null });
	});

	it('rejects a stale response for another employee', async () => {
		const client = { rpc: vi.fn().mockResolvedValue({ data: context('EMP70'), error: null }) };
		await expect(loadVikinEmployeeLink(client, 'EMP15')).rejects.toThrow('selected employee');
	});

	it('reports a rejected save rather than returning a successful link', async () => {
		const client = { rpc: vi.fn().mockResolvedValue({ data: null, error: { message: 'Ledger company does not match employee sponsor.' } }) };
		await expect(saveVikinEmployeeLink(client, 'EMP15', 'wrong-company')).rejects.toThrow('company does not match');
	});
});

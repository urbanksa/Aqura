import { afterEach, beforeEach, expect, it, vi } from 'vitest';

const db = vi.hoisted(() => ({ from: vi.fn() }));
vi.mock('@supabase/supabase-js', () => ({ createClient: () => db }));
vi.mock('$env/dynamic/private', () => ({
	env: { VITE_SUPABASE_URL: 'https://database.test', VITE_SUPABASE_SERVICE_KEY: 'test' }
}));
import { GET, POST } from './+server';

beforeEach(() => {
	vi.clearAllMocks();
	const chain: any = {
		select: () => chain,
		eq: () => chain,
		single: async () => ({
			data: { tunnel_url: 'https://bridge.test', erp_branch_id: 4, bridge_api_secret: 'test' },
			error: null
		})
	};
	db.from.mockReturnValue(chain);
});

it('preloads the full employee directory beyond the former 50-result limit', async () => {
	const employees = Array.from({ length: 75 }, (_, index) => ({ EmployeeID: index + 1, EmployeeName: `Employee ${index + 1}` }));
	const bridge = vi.fn().mockResolvedValue(Response.json({ success: true, recordset: employees, rowCount: 75 }));
	vi.stubGlobal('fetch', bridge);
	const response = await GET({ url: new URL('https://aqura.test/api/erp-employee-balance?branchId=3') } as any);
	const sql = JSON.parse(bridge.mock.calls[0][1].body).sql;
	expect(sql).not.toContain('TOP 50');
	expect(sql).toContain('BranchID = 4');
	expect(sql).toContain('IsActive=1');
	expect((await response.json()).employees).toHaveLength(75);
});

it('reports a directory query failure so the client can show partial branch failures', async () => {
	vi.stubGlobal('fetch', vi.fn().mockResolvedValue(Response.json({ success: false, error: 'query failed' })));
	const response = await GET({ url: new URL('https://aqura.test/api/erp-employee-balance?branchId=3') } as any);
	expect(response.status).toBe(502);
	expect((await response.json()).success).toBe(false);
});
afterEach(() => vi.unstubAllGlobals());

it('returns ledger identity and a zero balance for an employee with no transactions', async () => {
	const bridge = vi.fn()
		.mockResolvedValueOnce(Response.json({ success: true, rowCount: 1,
			recordset: [{ EmployeeID: 232, EmployeeName: 'SHANTO 2', EmployeeCode: '10122' }] }))
		.mockResolvedValueOnce(Response.json({ success: true, rowCount: 1,
			recordset: [{ LedgerID: 1195, LedgerCode: '10122', LedgerName: 'SHANTO 2', TotalDebit: 0, TotalCredit: 0, NetBalance: 0 }] }));
	vi.stubGlobal('fetch', bridge);
	const response = await POST({ request: new Request('https://aqura.test/api/erp-employee-balance', {
		method: 'POST', body: JSON.stringify({ branchId: 3, erpEmployeeId: 232 })
	}) } as any);
	const sql = JSON.parse(bridge.mock.calls[1][1].body).sql;
	expect(sql).toContain('OUTER APPLY');
	expect(sql).toContain('COALESCE(t.NetBalance,0)');
	expect(sql).toContain('d.LedgerID=l.LedgerID AND d.BranchID=l.BranchID');
	expect((await response.json()).balance).toEqual({ ledgerCode: '10122', ledgerName: 'SHANTO 2',
		totalDebit: 0, totalCredit: 0, netBalance: 0, direction: 'Nil' });
});

it.each([
	{ debit: 500, credit: 200, amount: 300, direction: 'Dr' },
	{ debit: 200, credit: 500, amount: 300, direction: 'Cr' },
	{ debit: 500, credit: 500, amount: 0, direction: 'Nil' }
])('uses the explicit employee ledger within the ERP branch ($direction)', async ({ debit, credit, amount, direction }) => {
	const bridge = vi.fn()
		.mockResolvedValueOnce(Response.json({
			success: true, rowCount: 1,
			recordset: [{ EmployeeID: 100, EmployeeName: 'YOUSUF(ARD)', EmployeeCode: '1835' }]
		}))
		.mockResolvedValueOnce(Response.json({
			success: true, rowCount: 1,
			recordset: [{ LedgerID: 794, LedgerCode: '1835', LedgerName: 'YOUSUF(ARD)', TotalDebit: debit, TotalCredit: credit, NetBalance: debit - credit }]
		}));
	vi.stubGlobal('fetch', bridge);
	const response = await POST({ request: new Request('https://aqura.test/api/erp-employee-balance', {
		method: 'POST', body: JSON.stringify({ branchId: 3, erpEmployeeId: 100 })
	}) } as any);
	const sql = JSON.parse(bridge.mock.calls[1][1].body).sql;
	// Code 1835 belongs to multiple ledgers: only AccLedgerID identifies the employee's ledger.
	expect(sql).toContain('l.LedgerID=e.AccLedgerID');
	expect(sql).toContain('l.BranchID=e.BranchID');
	expect(sql).toContain('e.BranchID = 4');
	expect(sql).not.toContain('l.LedgerCode=e.EmployeeCode');
	expect(response.status).toBe(200);
	expect((await response.json()).balance).toEqual({
		ledgerCode: '1835', ledgerName: 'YOUSUF(ARD)', totalDebit: debit,
		totalCredit: credit, netBalance: amount, direction
	});
});

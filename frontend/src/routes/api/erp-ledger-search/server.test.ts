import { afterEach, beforeEach, expect, it, vi } from 'vitest';

const db = vi.hoisted(() => ({ from: vi.fn() }));
vi.mock('@supabase/supabase-js', () => ({ createClient: () => db }));
vi.mock('$env/dynamic/private', () => ({ env: { VITE_SUPABASE_URL: 'https://database.test', VITE_SUPABASE_SERVICE_KEY: 'test' } }));
import { GET } from './+server';

beforeEach(() => {
	vi.clearAllMocks();
	const chain: any = { select: () => chain, eq: () => chain, single: async () => ({ data: {
		tunnel_url: 'https://bridge.test', erp_branch_id: 4, bridge_api_secret: 'test'
	}, error: null }) };
	db.from.mockReturnValue(chain);
});
afterEach(() => vi.unstubAllGlobals());

it('limits salary choices to active Indirect Income ledgers within the mapped ERP branch', async () => {
	const ledgers = [{ LedgerID: 20, LedgerCode: '501', LedgerName: 'Salary deductions', AccGroupName: 'Indirect Income' }];
	const bridge = vi.fn().mockResolvedValue(Response.json({ success: true, recordset: ledgers }));
	vi.stubGlobal('fetch', bridge);
	const response = await GET({ url: new URL('https://aqura.test/api/erp-ledger-search?branchId=3&indirectIncomeOnly=true') } as any);
	const sql = JSON.parse(bridge.mock.calls[0][1].body).sql;
	expect(sql).toContain('g.AccGroupID = l.AccGroupID AND g.BranchID = l.BranchID');
	expect(sql).toContain("IN ('indirectincome', 'indirectincomes')");
	expect(sql).toContain('l.BranchID = 4');
	expect(sql).toContain('l.IsActive = 1');
	expect((await response.json()).ledgers).toEqual(ledgers);
});

it('preserves unrestricted searches for other screens', async () => {
	const bridge = vi.fn().mockResolvedValue(Response.json({ success: true, recordset: [] }));
	vi.stubGlobal('fetch', bridge);
	await GET({ url: new URL('https://aqura.test/api/erp-ledger-search?branchId=3') } as any);
	const sql = JSON.parse(bridge.mock.calls[0][1].body).sql;
	expect(sql).not.toContain('JOIN AccGroups');
});

it('preserves bank-only ledger filtering', async () => {
	const bridge = vi.fn().mockResolvedValue(Response.json({ success: true, recordset: [] }));
	vi.stubGlobal('fetch', bridge);
	await GET({ url: new URL('https://aqura.test/api/erp-ledger-search?branchId=3&bankOnly=true') } as any);
	expect(JSON.parse(bridge.mock.calls[0][1].body).sql).toContain("g.AccGroupName LIKE '%bank%'");
});

it('rejects conflicting ledger group filters', async () => {
	const response = await GET({ url: new URL('https://aqura.test/api/erp-ledger-search?branchId=3&bankOnly=true&indirectIncomeOnly=true') } as any);
	expect(response.status).toBe(400);
	expect(db.from).not.toHaveBeenCalled();
});

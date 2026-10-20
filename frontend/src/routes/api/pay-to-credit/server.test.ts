import { beforeEach, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
	user: vi.fn(), from: vi.fn(), delete: vi.fn(), eq: vi.fn(), select: vi.fn(), result: vi.fn()
}));
vi.mock('$lib/server/breakRegisterAuth', () => ({
	requireBreakUser: mocks.user,
	databaseClient: () => ({ from: mocks.from })
}));
import { DELETE } from './+server';

const call = (body: unknown = { id: 'credit-id' }) => DELETE({
	cookies: {},
	request: new Request('https://aqura.test/api/pay-to-credit', {
		method: 'DELETE', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body)
	})
} as any);

beforeEach(() => {
	vi.resetAllMocks();
	mocks.user.mockResolvedValue({ id: 'master', isMasterAdmin: true });
	const chain = { delete: mocks.delete, eq: mocks.eq, select: mocks.select, maybeSingle: mocks.result };
	for (const method of [mocks.from, mocks.delete, mocks.eq, mocks.select]) method.mockReturnValue(chain);
	mocks.result.mockResolvedValue({ data: { id: 'credit-id' }, error: null });
});

it('rejects ordinary admins before accessing transactions', async () => {
	mocks.user.mockResolvedValue({ id: 'admin', isAdmin: true, isMasterAdmin: false });
	expect((await call()).status).toBe(403);
	expect(mocks.from).not.toHaveBeenCalled();
});

it('does not delete without an authenticated session', async () => {
	mocks.user.mockRejectedValue(new Error('Session required'));
	expect((await (await call()).json()).success).toBe(false);
	expect(mocks.from).not.toHaveBeenCalled();
});

it.each([{}, { id: '' }, { id: ' ' }, { id: 42 }, null])('rejects invalid identifiers: %j', async body => {
	expect((await call(body)).status).toBe(400);
	expect(mocks.delete).not.toHaveBeenCalled();
});

it('allows master admins to delete only the identified Pay to Credit record', async () => {
	const response = await call();
	expect(response.status).toBe(200);
	expect(await response.json()).toEqual({ success: true, id: 'credit-id' });
	expect(mocks.from).toHaveBeenCalledWith('pos_scan_requests');
	expect(mocks.delete).toHaveBeenCalledOnce();
	expect(mocks.eq.mock.calls).toEqual([['id', 'credit-id'], ['request_type', 'pay_to_credit_slip']]);
});

it('reports a missing or non-credit record without claiming deletion succeeded', async () => {
	mocks.result.mockResolvedValue({ data: null, error: null });
	expect((await call()).status).toBe(404);
});

it('reports database failures', async () => {
	mocks.result.mockResolvedValue({ data: null, error: { message: 'Deletion failed' } });
	const response = await call();
	expect(response.status).toBe(400);
	expect(await response.json()).toEqual({ success: false, error: 'Deletion failed' });
});

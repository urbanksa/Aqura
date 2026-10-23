import { beforeEach, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({ user: vi.fn(), from: vi.fn(), queries: [] as any[], results: [] as any[] }));
vi.mock('@supabase/supabase-js', () => ({ createClient: () => ({ from: mocks.from }) }));
vi.mock('$env/dynamic/private', () => ({ env: { VITE_SUPABASE_URL: 'https://database.test', SUPABASE_SERVICE_ROLE_KEY: 'test' } }));
vi.mock('$lib/server/breakRegisterAuth', () => ({ requireBreakUser: mocks.user, databaseClient: () => ({ from: mocks.from }) }));
import { GET } from './+server';

const originalId = '33333333-3333-4333-8333-333333333333';
const reversalId = '44444444-4444-4444-8444-444444444444';
const reversal = (payload: Record<string, unknown> = {}) => ({
	id: reversalId, task_type: 'salary_vikin_adjustment_jv', assigned_to: 'current-user', status: 'pending',
	payload: { entry_kind: 'reversal', depends_on_task_id: originalId, lines: [{ ledger_code: 'AL98', side: 'Credit', amount: '2000.00' }], ...payload }
});
const call = () => GET({ cookies: {}, url: new URL('https://aqura.test/api/assistant-tasks') } as any);

beforeEach(() => {
	vi.resetAllMocks();
	mocks.queries.length = 0;
	mocks.results.length = 0;
	mocks.user.mockResolvedValue({ id: 'current-user', isMasterAdmin: false });
	mocks.from.mockImplementation(() => {
		const result = mocks.results.shift() || { data: [], error: null };
		const query: any = {
			select: vi.fn(), eq: vi.fn(), in: vi.fn(), order: vi.fn(),
			then: (resolve: (value: unknown) => unknown) => Promise.resolve(result).then(resolve)
		};
		for (const method of [query.select, query.eq, query.in, query.order]) method.mockReturnValue(query);
		mocks.queries.push(query);
		return query;
	});
});

it('exposes the current completed original status without changing the immutable reversal payload', async () => {
	const task = reversal({ depends_on_status: 'pending' });
	mocks.results.push({ data: [task], error: null }, { data: [{ id: originalId, status: 'completed' }], error: null });
	const response = await call();
	expect(response.status).toBe(200);
	expect(await response.json()).toEqual({ success: true, tasks: [{ ...task, depends_on_task_id: originalId, depends_on_status: 'completed' }] });
	expect(task.payload.depends_on_status).toBe('pending');
	expect(mocks.queries[0].eq).toHaveBeenCalledWith('assigned_to', 'current-user');
	expect(mocks.queries[0].in).toHaveBeenCalledWith('status', ['pending', 'in_progress', 'failed']);
	expect(mocks.queries[1].select).toHaveBeenCalledWith('id,status');
	expect(mocks.queries[1].eq.mock.calls).toEqual([['assigned_to', 'current-user'], ['task_type', 'salary_vikin_adjustment_jv']]);
	expect(mocks.queries[1].in).toHaveBeenCalledWith('id', [originalId]);
});

it.each(['pending', 'in_progress', 'failed', 'cancelled'])('uses authoritative original status %s instead of a payload hint', async status => {
	const task = reversal({ depends_on_status: 'completed' });
	mocks.results.push({ data: [task], error: null }, { data: [{ id: originalId, status }], error: null });
	expect((await (await call()).json()).tasks[0].depends_on_status).toBe(status);
});

it('keeps the reversal blocked when its original is missing or belongs to another assignee', async () => {
	mocks.results.push({ data: [reversal()], error: null }, { data: [], error: null });
	expect((await (await call()).json()).tasks[0].depends_on_status).toBeNull();
	expect(mocks.queries[1].eq).toHaveBeenCalledWith('assigned_to', 'current-user');
});

it('leaves unrelated tasks, original JVs and legacy no-save tasks unchanged without querying parents', async () => {
	const tasks = [
		{ ...reversal(), task_type: 'bank_planner_jv' },
		{ ...reversal(), payload: { entry_kind: 'adjustment' } },
		{ ...reversal(), task_type: 'salary_vikin_adjustment_test_jv' }
	];
	mocks.results.push({ data: tasks, error: null });
	expect(await (await call()).json()).toEqual({ success: true, tasks });
	expect(mocks.from).toHaveBeenCalledOnce();
});

it('loads each original only once when multiple returned reversals refer to it', async () => {
	mocks.results.push({ data: [reversal(), { ...reversal(), id: 'another-reversal' }], error: null },
		{ data: [{ id: originalId, status: 'completed' }], error: null });
	const response = await (await call()).json();
	expect(response.tasks.every((task: any) => task.depends_on_status === 'completed')).toBe(true);
	expect(mocks.queries[1].in).toHaveBeenCalledWith('id', [originalId]);
});

it.each(['not-a-uuid', '', null])('does not send malformed dependency ID %j to the database', async depends_on_task_id => {
	mocks.results.push({ data: [reversal({ depends_on_task_id })], error: null });
	expect((await (await call()).json()).tasks[0].depends_on_status).toBeNull();
	expect(mocks.from).toHaveBeenCalledOnce();
});

it('returns an error rather than claiming a dependency is completed when its query fails', async () => {
	mocks.results.push({ data: [reversal()], error: null }, { data: null, error: { message: 'Parent status unavailable' } });
	const response = await (await call()).json();
	expect(response.success).toBe(false);
	expect(response.tasks).toBeUndefined();
});

it('requires a desktop session before accessing tasks or dependencies', async () => {
	mocks.user.mockRejectedValue(new Error('Desktop session required'));
	expect((await call()).status).toBe(401);
	expect(mocks.from).not.toHaveBeenCalled();
});

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { persistInactivityLock, readInactivityLock, resetInactivityLock } from './inactivityLock';

describe('inactivity lock across history navigation and reloads', () => {
	beforeEach(() => {
		vi.useFakeTimers();
		vi.setSystemTime(10000);
		const values = new Map<string, string>();
		vi.stubGlobal('sessionStorage', {
			getItem: (key: string) => values.get(key) ?? null,
			setItem: (key: string, value: string) => values.set(key, value)
		});
	});
	afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); });

	it.each(['mobile', 'desktop', 'cashier'] as const)('%s keeps its deadline when the screen is recreated', kind => {
		expect(readInactivityLock(kind, 'user', 5000).locked).toBe(false);
		vi.advanceTimersByTime(4000);
		expect(readInactivityLock(kind, 'user', 5000).lastActivity).toBe(10000);
		vi.advanceTimersByTime(1000);
		expect(readInactivityLock(kind, 'user', 5000).locked).toBe(true);
		vi.advanceTimersByTime(1000);
		expect(readInactivityLock(kind, 'user', 5000).locked).toBe(true);
	});

	it('keeps an explicit lock until successful authentication resets it', () => {
		persistInactivityLock('mobile', 'user');
		expect(readInactivityLock('mobile', 'user', 5000).locked).toBe(true);
		resetInactivityLock('mobile', 'user');
		expect(readInactivityLock('mobile', 'user', 5000).locked).toBe(false);
	});

	it('isolates users and interfaces within a tab', () => {
		persistInactivityLock('mobile', 'user');
		expect(readInactivityLock('desktop', 'user', 5000).locked).toBe(false);
		expect(readInactivityLock('mobile', 'other', 5000).locked).toBe(false);
	});
});

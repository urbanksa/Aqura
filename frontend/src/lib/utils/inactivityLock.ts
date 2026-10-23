type Interface = 'mobile' | 'desktop' | 'cashier';
type LockState = { lastActivity: number; locked: boolean };

function key(kind: Interface, userId: string): string {
	return `aqura-inactivity:${kind}:${userId}`;
}

export function readInactivityLock(kind: Interface, userId: string, timeout: number): LockState {
	let state: LockState | null = null;
	try {
		state = JSON.parse(sessionStorage.getItem(key(kind, userId)) || 'null');
	} catch { /* Use a new deadline if storage is unavailable. */ }
	if (!state || !Number.isFinite(state.lastActivity)) {
		state = { lastActivity: Date.now(), locked: false };
	}
	state.locked = state.locked || Date.now() - state.lastActivity >= timeout;
	writeInactivityLock(kind, userId, state);
	return state;
}

function writeInactivityLock(kind: Interface, userId: string, state: LockState): void {
	try { sessionStorage.setItem(key(kind, userId), JSON.stringify(state)); } catch { /* In-memory timer remains active. */ }
}

export function resetInactivityLock(kind: Interface, userId: string): void {
	writeInactivityLock(kind, userId, { lastActivity: Date.now(), locked: false });
}

export function persistInactivityLock(kind: Interface, userId: string): void {
	writeInactivityLock(kind, userId, { lastActivity: Date.now(), locked: true });
}

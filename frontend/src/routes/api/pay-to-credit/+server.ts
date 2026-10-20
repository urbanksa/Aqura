import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { databaseClient, requireBreakUser } from '$lib/server/breakRegisterAuth';

export const DELETE: RequestHandler = async ({ request, cookies }) => {
	try {
		const user = await requireBreakUser(cookies, 'desktop');
		if (!user.isMasterAdmin) {
			return json({ success: false, error: 'Master admin permission required' }, { status: 403 });
		}
		const body = await request.json();
		if (typeof body?.id !== 'string' || !body.id.trim()) {
			return json({ success: false, error: 'Transaction ID is required' }, { status: 400 });
		}
		const { data, error } = await databaseClient().from('pos_scan_requests')
			.delete().eq('id', body.id).eq('request_type', 'pay_to_credit_slip')
			.select('id').maybeSingle();
		if (error) throw error;
		if (!data) return json({ success: false, error: 'Pay to Credit transaction not found' }, { status: 404 });
		return json({ success: true, id: data.id });
	} catch (error: any) {
		return json({ success: false, error: error.message || 'Transaction deletion failed' }, { status: 400 });
	}
};

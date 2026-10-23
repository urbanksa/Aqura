export type VikinLinkLedger = {
	id: string;
	ledger_code: string;
	ledger_name: string;
	account_group_name: string;
};

export type VikinEmployeeLinkContext = {
	employee_id: string;
	company: { id: number; name_en: string | null; name_ar: string | null };
	ledgers: VikinLinkLedger[];
	link: { ledger_id: string; [key: string]: unknown } | null;
};

type RpcClient = { rpc: (name: string, args: Record<string, unknown>) => PromiseLike<{ data: unknown; error: { message: string } | null }> };

function contextResult(data: unknown, employeeId: string): VikinEmployeeLinkContext {
	const context = data as VikinEmployeeLinkContext;
	if (!context || context.employee_id !== employeeId || !context.company?.id || !Array.isArray(context.ledgers)) {
		throw new Error('Could not load the selected employee’s Vikin ledger links.');
	}
	return context;
}

export async function loadVikinEmployeeLink(client: RpcClient, employeeId: string) {
	const { data, error } = await client.rpc('get_vikin_employee_link_context', { p_employee_id: employeeId });
	if (error) throw new Error(error.message);
	return contextResult(data, employeeId);
}

export async function saveVikinEmployeeLink(client: RpcClient, employeeId: string, ledgerId: string | null) {
	const { data, error } = await client.rpc('set_vikin_employee_ledger_link', { p_employee_id: employeeId, p_ledger_id: ledgerId });
	if (error) throw new Error(error.message);
	return contextResult(data, employeeId);
}

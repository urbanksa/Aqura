import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { databaseClient, requireBreakUser } from '$lib/server/breakRegisterAuth';

const headers = { 'Cache-Control': 'no-store' };
const validPrice = (value: unknown): value is number => typeof value === 'number' && Number.isFinite(value) && value >= 0;
type UnitPrice = { unit_id: string; barcode: string; quantity_in_base_units: number; price: number };
type ProductUnit = { unit_id: string; barcode: string; quantity_in_base_units: number; price?: number };

export const GET: RequestHandler = async ({ cookies }) => {
	try {
		const actor = await requireBreakUser(cookies, 'desktop');
		if (!actor.isMasterAdmin) return json({ error: 'Master Admin access is required.' }, { status: 403, headers });
		const db = databaseClient();
		const { data: connections, error } = await db.from('erp_connections').select('branch_id, branch_name, erp_branch_id').eq('is_active', true).order('branch_name');
		if (error) throw error;
		const { data: branches, error: branchError } = await db.from('branches').select('id, name_en, name_ar, location_en');
		if (branchError) throw branchError;
		return json({ branches: (connections || []).map(connection => {
			const branch = branches?.find(item => Number(item.id) === Number(connection.branch_id));
			const name = branch?.name_en || branch?.name_ar || connection.branch_name;
			return { id: Number(connection.branch_id), name: branch?.location_en ? `${name} - ${branch.location_en}` : name };
		}) }, { headers });
	} catch {
		return json({ error: 'Unable to load branches. An active Master Admin desktop session is required.' }, { status: 400, headers });
	}
};

export const POST: RequestHandler = async ({ cookies, request }) => {
	try {
		const actor = await requireBreakUser(cookies, 'desktop');
		if (!actor.isMasterAdmin) return json({ error: 'Master Admin access is required.' }, { status: 403, headers });
		const body = await request.json();
		const branchId = Number(body.branchId);
		if (!Number.isSafeInteger(branchId) || branchId <= 0 || typeof body.productId !== 'string' || !['fetch', 'save'].includes(body.action)) {
			return json({ error: 'Select a valid product and branch.' }, { status: 400, headers });
		}
		const db = databaseClient();
		const { data: connection, error: connectionError } = await db.from('erp_connections')
			.select('branch_id, branch_name, erp_branch_id, tunnel_url, bridge_api_secret').eq('branch_id', branchId).eq('is_active', true).single();
		if (connectionError || !connection?.tunnel_url || !connection.bridge_api_secret) return json({ error: 'No active ERP connection is configured for this branch.' }, { status: 404, headers });
		const erpBranchId = Number(connection.erp_branch_id);
		if (!Number.isSafeInteger(erpBranchId) || erpBranchId <= 0) return json({ error: 'The ERP branch ID must be configured before retrieving prices.' }, { status: 400, headers });
		const { data: product, error: productError } = await db.from('Polosys_products').select('id, data, updated_at').eq('id', body.productId).single();
		if (productError || !product) return json({ error: 'Product not found in Aqura.' }, { status: 404, headers });
		const barcode = typeof product.data?.barcode === 'string' ? product.data.barcode.trim() : '';
		if (!barcode || barcode.length > 100) return json({ error: 'The product needs a valid barcode.' }, { status: 400, headers });
		const additionalUnits: ProductUnit[] = Array.isArray(product.data.multi_units) ? product.data.multi_units : [];
		if (additionalUnits.length > 9 || additionalUnits.some(unit => typeof unit.unit_id !== 'string' || typeof unit.barcode !== 'string' || !unit.barcode.trim() || unit.barcode.length > 100 || !Number.isFinite(unit.quantity_in_base_units) || unit.quantity_in_base_units <= 0)) {
			return json({ error: 'The product has invalid additional unit details.' }, { status: 400, headers });
		}

		if (body.action === 'save') {
			if (body.barcode !== barcode || !validPrice(body.purchasePrice) || !validPrice(body.salesPrice)
				|| typeof body.fetchedAt !== 'string' || !Number.isFinite(Date.parse(body.fetchedAt))) {
				return json({ error: 'Fetch valid prices for this product and branch before saving.' }, { status: 400, headers });
			}
			const suppliedUnits: UnitPrice[] = Array.isArray(body.multiUnits) ? body.multiUnits : [];
			if (suppliedUnits.length !== additionalUnits.length || additionalUnits.some(unit => suppliedUnits.filter(price => price?.unit_id === unit.unit_id && price.barcode === unit.barcode.trim() && price.quantity_in_base_units === unit.quantity_in_base_units && validPrice(price.price)).length !== 1)) {
				return json({ error: 'Fetch and fill prices for every additional unit before saving.' }, { status: 400, headers });
			}
			const multiUnitPrices: UnitPrice[] = additionalUnits.map(unit => {
				const price = suppliedUnits.find(item => item.unit_id === unit.unit_id)!;
				return { unit_id: unit.unit_id, barcode: unit.barcode.trim(), quantity_in_base_units: unit.quantity_in_base_units, price: price.price };
			});
			const branchPrice = { branch_id: branchId, erp_branch_id: erpBranchId, branch_name: connection.branch_name,
				purchase_price: body.purchasePrice, sales_price: body.salesPrice, multi_units: multiUnitPrices, fetched_at: body.fetchedAt, saved_at: new Date().toISOString() };
			const updatedData = { ...product.data, purchase_price: body.purchasePrice, sales_price: body.salesPrice,
				multi_units: additionalUnits.map(unit => ({ ...unit, price: multiUnitPrices.find(price => price.unit_id === unit.unit_id)!.price })),
				selected_branch_id: branchId, branch_prices: { ...(product.data.branch_prices || {}), [String(branchId)]: branchPrice } };
			const { data: saved, error: saveError } = await db.from('Polosys_products').update({ data: updatedData })
				.eq('id', product.id).eq('updated_at', product.updated_at).select('id').maybeSingle();
			if (saveError) throw saveError;
			if (!saved) return json({ error: 'This product changed while saving. Fetch its prices again and retry.' }, { status: 409, headers });
			return json({ branchPrice, selectedBranchId: branchId }, { headers });
		}

		const bridgeUrl = connection.tunnel_url.replace(/\/+$/, '');
		const bridgeSecret = connection.bridge_api_secret;
		async function query(sql: string): Promise<Record<string, unknown>[]> {
			const response = await fetch(`${bridgeUrl}/query`, {
				method: 'POST', headers: { 'Content-Type': 'application/json', 'x-api-secret': bridgeSecret },
				body: JSON.stringify({ sql }), signal: AbortSignal.timeout(20000)
			});
			const result = await response.json().catch(() => null);
			if (!response.ok || !result?.success || !Array.isArray(result.recordset)) throw new Error('The branch ERP could not return standard prices. Check its connection and retry.');
			return result.recordset;
		}
		// The mobile checker uses this bridge, but returns unit selling prices and
		// offers. Read standard ProductBatches prices explicitly for this workflow.
		// OfferCostManager confirms StdPurchasePrice and the branch/barcode joins.
		// Its fallback costs are intentionally excluded: this flow needs standards.
		const escaped = barcode.replace(/'/g, "''");
		const rows = await query(`SELECT TOP 2 pb.ProductBatchID AS batch_id, pb.ProductID AS product_id,
			pb.StdPurchasePrice AS purchase_price, pb.StdSalesPrice AS sales_price
			FROM ProductBatches pb WHERE pb.BranchID = ${erpBranchId} AND (
			pb.MannualBarcode = N'${escaped}' OR CAST(pb.AutoBarcode AS NVARCHAR(100)) = N'${escaped}'
			OR EXISTS (SELECT 1 FROM ProductUnits pu WHERE pu.ProductBatchID = pb.ProductBatchID AND pu.BranchID = pb.BranchID AND pu.BarCode = N'${escaped}' AND pu.MultiFactor = 1)
			OR EXISTS (SELECT 1 FROM ProductBarcodes pbc WHERE pbc.ProductBatchID = pb.ProductBatchID AND pbc.Barcode = N'${escaped}'))
			ORDER BY pb.ProductBatchID DESC`);
		if (!rows.length) return json({ error: 'The product barcode was not found in the selected branch ERP.' }, { status: 404, headers });
		if (rows.length > 1 && String(rows[0].product_id) !== String(rows[1].product_id)) {
			return json({ error: 'This barcode matches conflicting ERP products. Resolve the match before saving.' }, { status: 409, headers });
		}
		const purchasePrice = rows[0].purchase_price == null ? NaN : Number(rows[0].purchase_price);
		const salesPrice = rows[0].sales_price == null ? NaN : Number(rows[0].sales_price);
		if (!validPrice(purchasePrice) || !validPrice(salesPrice)) return json({ error: 'The branch did not return valid standard prices.' }, { status: 422, headers });
		const multiUnits: UnitPrice[] = [];
		if (additionalUnits.length) {
			const productId = Number(rows[0].product_id);
			if (!Number.isSafeInteger(productId) || productId <= 0) throw new Error('The ERP product identity is invalid.');
			const barcodeList = additionalUnits.map(unit => `N'${unit.barcode.trim().replace(/'/g, "''")}'`).join(',');
			// Match the exact barcode and factor in ProductUnits. Sprice is the
			// normal unit selling price used by mobile Price Checker/Offer Cost Manager.
			const unitRows = await query(`SELECT pu.BarCode AS barcode, pu.MultiFactor AS quantity_in_base_units,
				pu.Sprice AS price, pb.ProductBatchID AS batch_id
				FROM ProductUnits pu INNER JOIN ProductBatches pb
				ON pu.ProductBatchID = pb.ProductBatchID AND pu.BranchID = pb.BranchID
				WHERE pb.BranchID = ${erpBranchId} AND pb.ProductID = ${productId} AND pu.BarCode IN (${barcodeList})
				ORDER BY pb.ProductBatchID DESC, pu.Sprice DESC`);
			for (const unit of additionalUnits) {
				const match = unitRows.find(row => String(row.barcode).trim() === unit.barcode.trim() && Number(row.quantity_in_base_units) === unit.quantity_in_base_units);
				const price = match?.price == null ? NaN : Number(match.price);
				if (!validPrice(price)) return json({ error: `No matching sales price was found for additional-unit barcode ${unit.barcode} with quantity ${unit.quantity_in_base_units}. Check this unit in the selected branch.` }, { status: 422, headers });
				multiUnits.push({ unit_id: unit.unit_id, barcode: unit.barcode.trim(), quantity_in_base_units: unit.quantity_in_base_units, price });
			}
		}
		return json({ branchId, barcode, purchasePrice, salesPrice, multiUnits, fetchedAt: new Date().toISOString() }, { headers });
	} catch (error) {
		const message = error instanceof Error && ['TimeoutError', 'AbortError'].includes(error.name) ? 'The branch ERP timed out. Please retry.' : error instanceof Error ? error.message : 'Unable to process branch prices.';
		return json({ error: message }, { status: 400, headers });
	}
};

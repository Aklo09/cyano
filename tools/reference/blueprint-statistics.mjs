// Prototype metadata comes from the matching local Factorio runtime, not renderer sprite bounds.
const TAU = Math.PI * 2;
const EPSILON = 1e-9;
const rounded = (number) => Math.round(number * 1e9) / 1e9;
const list = (value) => (Array.isArray(value) ? value : Object.values(value ?? {}));

function boxAabb(box, rotation = 0) {
	const [[x1, y1], [x2, y2], orientation = 0] = box;
	const cx = (x1 + x2) / 2;
	const cy = (y1 + y2) / 2;
	const turn = rotation * TAU;
	const centerX = cx * Math.cos(turn) - cy * Math.sin(turn);
	const centerY = cx * Math.sin(turn) + cy * Math.cos(turn);
	const angle = (orientation + rotation) * TAU;
	const halfX =
		(Math.abs(Math.cos(angle)) * (x2 - x1)) / 2 + (Math.abs(Math.sin(angle)) * (y2 - y1)) / 2;
	const halfY =
		(Math.abs(Math.sin(angle)) * (x2 - x1)) / 2 + (Math.abs(Math.cos(angle)) * (y2 - y1)) / 2;
	return [centerX - halfX, centerY - halfY, centerX + halfX, centerY + halfY];
}

export function calculateBlueprintStatistics(blueprint, map) {
	if (map.schema !== 2 || !map.gameVersion) throw new Error('Unsupported prototype map');
	const warnings = [];
	let footprintComplete = true;
	let requirementsComplete = true;
	let bounds = null;
	const buckets = Object.fromEntries(
		['placement', 'modules', 'equipment', 'otherInserted', 'equipmentRequests'].map((name) => [
			name,
			new Map()
		])
	);
	const warn = (message, affects = 'requirements') => {
		warnings.push(message);
		if (affects === 'footprint' || affects === 'both') footprintComplete = false;
		if (affects === 'requirements' || affects === 'both') requirementsComplete = false;
	};
	const add = (bucket, name, quality = 'normal', count = 1) => {
		if (!map.items[name]) {
			warn(`Unknown item ${name}`);
			return;
		}
		if (!map.qualities[quality]) {
			warn(`Unknown quality ${quality}`);
			return;
		}
		if (!Number.isSafeInteger(count) || count < 0)
			throw new Error(`Invalid item count for ${name}`);
		const key = `${name}\0${quality}`;
		const previous = buckets[bucket].get(key)?.count ?? 0;
		if (!Number.isSafeInteger(previous + count)) throw new Error(`Item count overflow for ${name}`);
		if (count) buckets[bucket].set(key, { name, quality, count: previous + count });
	};
	const include = (rect) => {
		if (!rect.every(Number.isFinite)) throw new Error('Invalid blueprint position/geometry');
		bounds = bounds
			? [
					Math.min(bounds[0], rect[0]),
					Math.min(bounds[1], rect[1]),
					Math.max(bounds[2], rect[2]),
					Math.max(bounds[3], rect[3])
				]
			: rect;
	};
	const placement = (prototype, quality, label) => {
		const choice = list(prototype.placement)[0];
		if (!choice) warn(`No placement item for ${label}`);
		else add('placement', choice.name, quality, choice.count);
	};
	for (const entity of blueprint.entities ?? []) {
		const prototype = map.entities[entity.name];
		if (!prototype) {
			warn(`Unknown entity ${entity.name}`, 'both');
			continue;
		}
		if (
			prototype.notBlueprintable ||
			['construction-robot', 'logistic-robot'].includes(prototype.type)
		)
			warn(`Entity ${entity.name} is not blueprint-buildable`);
		placement(prototype, entity.quality ?? 'normal', entity.name);
		const direction = entity.direction ?? 0;
		if (!Number.isInteger(direction) || direction < 0 || direction > 15)
			throw new Error(`Invalid direction for ${entity.name}`);
		const shape = prototype.directions[prototype.offGrid ? '0' : String(direction)];
		if (!shape) warn(`Unmeasured geometry for ${entity.name}, direction ${direction}`, 'footprint');
		else {
			const rotation = prototype.orientationAffectsCollision
				? (entity.orientation ?? direction / 16)
				: 0;
			if (!Number.isFinite(rotation) || rotation < 0 || rotation > 1)
				throw new Error(`Invalid orientation for ${entity.name}`);
			for (const box of [shape.collisionBox, shape.secondaryCollisionBox].filter(Boolean)) {
				let [x1, y1, x2, y2] = boxAabb(box, rotation);
				if (!prototype.offGrid) {
					// Snap in the entity's local placement phase, preserving translation invariance.
					const phaseX = (shape.tileWidth % 2) / 2;
					const phaseY = (shape.tileHeight % 2) / 2;
					x1 = Math.floor(x1 + phaseX + EPSILON) - phaseX;
					y1 = Math.floor(y1 + phaseY + EPSILON) - phaseY;
					x2 = Math.ceil(x2 + phaseX - EPSILON) - phaseX;
					y2 = Math.ceil(y2 + phaseY - EPSILON) - phaseY;
				}
				include([
					x1 + entity.position.x,
					y1 + entity.position.y,
					x2 + entity.position.x,
					y2 + entity.position.y
				]);
			}
		}
		if (entity.items && !Array.isArray(entity.items))
			warn(`Unsupported legacy item format on ${entity.name}`);
		else
			for (const request of entity.items ?? []) {
				const name = request.id?.name;
				const quality = request.id?.quality ?? 'normal';
				let count = 0;
				for (const stack of request.items?.in_inventory ?? []) {
					const amount = stack.count ?? 1;
					if (!Number.isSafeInteger(amount) || amount < 0)
						throw new Error(`Invalid inserted count for ${name}`);
					count += amount;
				}
				if (count)
					add(
						map.items[name]?.type === 'module' ? 'modules' : 'otherInserted',
						name,
						quality,
						count
					);
				// Factorio cost_to_build counts installed grid entries, not bare grid_count requests.
				if (request.items?.grid_count)
					add('equipmentRequests', name, quality, request.items.grid_count);
			}
		for (const entry of entity.grid ?? []) {
			const equipment =
				typeof entry.equipment === 'string'
					? { name: entry.equipment }
					: (entry.equipment ?? { name: entry.name, quality: entry.quality });
			const candidates = map.equipmentItems[equipment.name] ?? [];
			if (candidates.length !== 1)
				warn(`Ambiguous or unknown equipment item for ${equipment.name}`);
			else add('equipment', candidates[0], equipment.quality ?? 'normal');
		}
	}
	for (const tile of blueprint.tiles ?? []) {
		if (!map.tiles[tile.name]) warn(`Unknown tile ${tile.name}`);
		else placement(map.tiles[tile.name], 'normal', tile.name);
		include([tile.position.x, tile.position.y, tile.position.x + 1, tile.position.y + 1]);
	}
	const sort = (items) =>
		[...items].sort((a, b) => a.name.localeCompare(b.name) || a.quality.localeCompare(b.quality));
	const groups = Object.fromEntries(
		Object.entries(buckets).map(([key, entries]) => [key, sort(entries.values())])
	);
	const combined = new Map();
	for (const category of ['placement', 'modules', 'equipment', 'otherInserted']) {
		for (const item of groups[category]) {
			const key = `${item.name}\0${item.quality}`;
			const count = (combined.get(key)?.count ?? 0) + item.count;
			if (!Number.isSafeInteger(count))
				throw new Error(`Construction count overflow for ${item.name}`);
			combined.set(key, { ...item, count });
		}
	}
	const knownBounds = bounds
		? Object.fromEntries(
				['minX', 'minY', 'maxX', 'maxY'].map((key, i) => [key, rounded(bounds[i])])
			)
		: null;
	return {
		gameVersion: map.gameVersion,
		basis: 'source-blueprint',
		entities: blueprint.entities?.length ?? 0,
		tiles: blueprint.tiles?.length ?? 0,
		complete: footprintComplete && requirementsComplete,
		requirementsComplete,
		warnings,
		footprint: {
			units: 'game tiles',
			complete: footprintComplete,
			bounds: footprintComplete ? knownBounds : null,
			width: footprintComplete ? rounded(bounds ? bounds[2] - bounds[0] : 0) : null,
			height: footprintComplete ? rounded(bounds ? bounds[3] - bounds[1] : 0) : null,
			...(footprintComplete ? {} : { knownBounds })
		},
		constructionItems: sort(combined.values()),
		...groups
	};
}

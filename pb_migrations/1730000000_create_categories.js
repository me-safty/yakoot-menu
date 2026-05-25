migrate((app) => {
	const collection = new Collection({
		type: 'base',
		name: 'categories',
		listRule: 'isActive = true',
		viewRule: 'isActive = true',
		createRule: null,
		updateRule: null,
		deleteRule: null,
		fields: [
			{
				type: 'text',
				name: 'name',
				required: true,
				presentable: true,
			},
			{
				type: 'text',
				name: 'slug',
				required: true,
			},
			{
				type: 'file',
				name: 'menuImage',
				required: true,
				maxSelect: 1,
				maxSize: 20000000,
				mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
			},
			{
				type: 'number',
				name: 'sort',
			},
			{
				type: 'bool',
				name: 'isActive',
				required: true,
			},
		],
		indexes: ['CREATE UNIQUE INDEX idx_categories_slug ON categories (slug)'],
	});

	app.save(collection);
}, (app) => {
	const collection = app.findCollectionByNameOrId('categories');
	app.delete(collection);
});

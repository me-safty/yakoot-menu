migrate((app) => {
	const collection = new Collection({
		type: 'base',
		name: 'site_settings',
		listRule: '',
		viewRule: '',
		createRule: null,
		updateRule: null,
		deleteRule: null,
		fields: [
			{
				type: 'file',
				name: 'footerLogo',
				maxSelect: 1,
				maxSize: 5000000,
				mimeTypes: ['image/jpeg', 'image/png', 'image/webp', 'image/svg+xml'],
			},
			{
				type: 'text',
				name: 'hours',
				required: true,
			},
			{
				type: 'url',
				name: 'facebookUrl',
			},
			{
				type: 'url',
				name: 'instagramUrl',
			},
		],
		indexes: ['CREATE UNIQUE INDEX idx_site_settings_singleton ON site_settings ((1))'],
	});

	app.save(collection);
}, (app) => {
	const collection = app.findCollectionByNameOrId('site_settings');
	app.delete(collection);
});

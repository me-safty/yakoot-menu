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

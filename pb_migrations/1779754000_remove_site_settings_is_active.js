migrate((app) => {
	const collection = app.findCollectionByNameOrId('site_settings');

	collection.fields.removeByName('isActive');
	collection.listRule = '';
	collection.viewRule = '';
	collection.indexes = ['CREATE UNIQUE INDEX idx_site_settings_singleton ON site_settings ((1))'];

	app.save(collection);
}, (app) => {
	const collection = app.findCollectionByNameOrId('site_settings');

	collection.fields.add(new BoolField({
		name: 'isActive',
		required: true,
	}));
	collection.listRule = 'isActive = true';
	collection.viewRule = 'isActive = true';
	collection.indexes = ['CREATE UNIQUE INDEX idx_site_settings_singleton ON site_settings ((1))'];

	app.save(collection);
});

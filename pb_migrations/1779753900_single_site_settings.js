migrate((app) => {
	const collection = app.findCollectionByNameOrId('site_settings');

	collection.fields.removeByName('key');
	collection.listRule = '';
	collection.viewRule = '';
	collection.indexes = ['CREATE UNIQUE INDEX idx_site_settings_singleton ON site_settings ((1))'];

	app.save(collection);
}, (app) => {
	const collection = app.findCollectionByNameOrId('site_settings');

	collection.fields.add(new TextField({
		name: 'key',
		required: true,
	}));
	collection.fields.add(new BoolField({
		name: 'isActive',
		required: true,
	}));
	collection.listRule = 'key = "main" && isActive = true';
	collection.viewRule = 'key = "main" && isActive = true';
	collection.indexes = ['CREATE UNIQUE INDEX idx_site_settings_key ON site_settings (`key`)'];

	app.save(collection);
});

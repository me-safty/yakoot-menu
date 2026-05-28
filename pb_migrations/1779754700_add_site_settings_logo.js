migrate((app) => {
	const collection = app.findCollectionByNameOrId('site_settings');

	collection.fields.add(new FileField({
		name: 'logo',
		maxSelect: 1,
		maxSize: 5000000,
		mimeTypes: ['image/jpeg', 'image/png', 'image/webp', 'image/svg+xml'],
	}));

	app.save(collection);
}, (app) => {
	const collection = app.findCollectionByNameOrId('site_settings');

	collection.fields.removeByName('logo');

	app.save(collection);
});

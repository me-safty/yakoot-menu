migrate((app) => {
	const collection = app.findCollectionByNameOrId('site_settings');

	collection.fields.add(new BoolField({
		name: 'showFooter',
		required: true,
	}));

	app.save(collection);
}, (app) => {
	const collection = app.findCollectionByNameOrId('site_settings');

	collection.fields.removeByName('showFooter');

	app.save(collection);
});

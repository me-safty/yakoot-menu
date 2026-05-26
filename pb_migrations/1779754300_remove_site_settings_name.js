migrate((app) => {
	const collection = app.findCollectionByNameOrId('site_settings');

	collection.fields.removeByName('name');

	app.save(collection);
}, (app) => {
	const collection = app.findCollectionByNameOrId('site_settings');

	collection.fields.add(new TextField({
		name: 'name',
		required: true,
		presentable: true,
	}));

	app.save(collection);
});

migrate((app) => {
	const collection = app.findCollectionByNameOrId('footer_addresses');

	collection.fields.add(new TextField({
		name: 'description',
	}));

	app.save(collection);
}, (app) => {
	const collection = app.findCollectionByNameOrId('footer_addresses');

	collection.fields.removeByName('description');

	app.save(collection);
});

migrate((app) => {
	const collection = app.findCollectionByNameOrId('categories');
	const field = collection.fields.getByName('menuImage');

	field.maxSelect = 10;

	app.save(collection);
}, (app) => {
	const collection = app.findCollectionByNameOrId('categories');
	const field = collection.fields.getByName('menuImage');

	field.maxSelect = 1;

	app.save(collection);
});

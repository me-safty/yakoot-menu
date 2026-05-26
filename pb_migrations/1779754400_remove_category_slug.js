migrate((app) => {
	const collection = app.findCollectionByNameOrId('categories');

	collection.fields.removeByName('slug');
	collection.indexes = collection.indexes.filter((index) => !index.includes('idx_categories_slug'));

	app.save(collection);
}, (app) => {
	const collection = app.findCollectionByNameOrId('categories');

	collection.fields.add(new TextField({
		name: 'slug',
		required: true,
	}));
	collection.indexes.push('CREATE UNIQUE INDEX idx_categories_slug ON categories (slug)');

	app.save(collection);
});

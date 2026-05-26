migrate((app) => {
	const settings = app.findCollectionByNameOrId('site_settings');
	settings.fields.removeByName('addresses');
	app.save(settings);

	const collection = new Collection({
		type: 'base',
		name: 'footer_addresses',
		listRule: 'isActive = true',
		viewRule: 'isActive = true',
		createRule: null,
		updateRule: null,
		deleteRule: null,
		fields: [
			{
				type: 'text',
				name: 'address',
				required: true,
				presentable: true,
			},
			{
				type: 'text',
				name: 'description',
			},
			{
				type: 'text',
				name: 'phoneNumber',
				required: true,
			},
			{
				type: 'number',
				name: 'sort',
			},
			{
				type: 'bool',
				name: 'isActive',
				required: true,
			},
		],
	});

	app.save(collection);
}, (app) => {
	const collection = app.findCollectionByNameOrId('footer_addresses');
	app.delete(collection);

	const settings = app.findCollectionByNameOrId('site_settings');
	settings.fields.add(new JSONField({
		name: 'addresses',
		required: true,
	}));
	app.save(settings);
});

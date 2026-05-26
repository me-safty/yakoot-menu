migrate((app) => {
	app.findCollectionByNameOrId('site_settings');
}, (app) => {
	app.findCollectionByNameOrId('site_settings');
});

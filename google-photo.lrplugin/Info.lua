return {
	LrSdkVersion = 3.0,
	LrSdkMinimumVersion = 3.0, -- minimum SDK version required by this plug-in

	LrToolkitIdentifier = 'org.stanaka.lightroom-google-photo-plugin',
	LrPluginName = LOC "$$$/GPhoto/PluginName=GooglePhoto",

	LrExportServiceProvider = {
		title = LOC "$$$/GPhoto/GPhoto-title=Google Photo",
		file = 'GPhotoExportServiceProvider.lua',
	},
	LrMetadataProvider = 'GPhotoMetadataDefinition.lua',
	URLHandler = "GPhotoURLHandler.lua",
	VERSION = { major=0, minor=1, revision=0 },
}

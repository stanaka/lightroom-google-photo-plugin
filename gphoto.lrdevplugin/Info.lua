return {
	LrSdkVersion = 3.0,
	LrSdkMinimumVersion = 3.0, -- minimum SDK version required by this plug-in

	LrToolkitIdentifier = 'com.adobe.lightroom.export.googlephoto',
	LrPluginName = LOC "$$$/GPhoto/PluginName=GooglePhoto",

	LrExportServiceProvider = {
		title = LOC "$$$/GPhoto/GPhoto-title=Google Photo",
		file = 'GPhotoExportServiceProvider.lua',
	},
	LrMetadataProvider = 'GPhotoMetadataDefinition.lua',

	VERSION = { major=0, minor=1, revision=0 },
}

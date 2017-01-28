-- Lightroom SDK
local LrDialogs = import 'LrDialogs'
local logger = import 'LrLogger'( 'GPhotoAPI' )
logger:enable('logfile')

-- GPhoto plug-in
require 'GPhotoAPI'

--------------------------------------------------------------------------------

local publishServiceProvider = {}
publishServiceProvider.small_icon = 'gphoto.png'

publishServiceProvider.publish_fallbackNameBinding = 'fullname'
publishServiceProvider.titleForPublishedCollection = LOC "$$$/GPhoto/TitleForPublishedCollection=Album"
publishServiceProvider.titleForPublishedCollection_standalone = LOC "$$$/GPhoto/TitleForPublishedCollection/Standalone=Album"
publishServiceProvider.titleForPublishedSmartCollection = LOC "$$$/GPhoto/TitleForPublishedSmartCollection=Smart Album"
publishServiceProvider.titleForPublishedSmartCollection_standalone = LOC "$$$/GPhoto/TitleForPublishedSmartCollection/Standalone=Smart Album"

function publishServiceProvider.getCollectionBehaviorInfo( publishSettings )
	logger:trace('getCollectionBehaviorInfo')
	return {
		defaultCollectionName = LOC "$$$/GPhoto/DefaultCollectionName/Photostream=Photos",
		defaultCollectionCanBeDeleted = false,
		canAddCollection = true,
		maxCollectionSetDepth = 0,
	}
end

publishServiceProvider.titleForGoToPublishedCollection = "disable"
publishServiceProvider.titleForGoToPublishedPhoto = "disable"

function publishServiceProvider.deletePhotosFromPublishedCollection( publishSettings, arrayOfPhotoIds, deletedCallback )
	logger:trace('deletePhotosFromPublishedCollection')
	for i, photoId in ipairs( arrayOfPhotoIds ) do
		GPhotoAPI.deletePhoto( publishSettings, { photoId = photoId, suppressErrorCodes = { [ 1 ] = true } } )
		deletedCallback( photoId )
	end
end

function publishServiceProvider.metadataThatTriggersRepublish( publishSettings )
	logger:trace('metadataThatTriggersRepublish')

	return {
		default = false,
		title = true,
		caption = true,
		keywords = true,
		gps = true,
		dateCreated = true,

		-- also (not used by Google Photo plug-in):
			-- customMetadata = true,
			-- com.whoever.plugin_name.* = true,
			-- com.whoever.plugin_name.field_name = true,
	}
end

function publishServiceProvider.shouldReverseSequenceForPublishedCollection( publishSettings, collectionInfo )
	logger:trace('shouldReverseSequenceForPublishedCollection')
	return false
end

publishServiceProvider.supportsCustomSortOrder = true
function publishServiceProvider.imposeSortOrderOnPublishedCollection( publishSettings, info, remoteIdSequence )
	logger:trace('imposeSortOrderOnPublishedCollection')
end

function publishServiceProvider.renamePublishedCollection( publishSettings, info )
	logger:trace('renamePublishedCollection')
	if info.remoteId then
		GPhotoAPI.refreshToken(publishSettings)
		GPhotoAPI.updateAlbum(publishSettings, info.remoteId, info.name)
	end
end

function publishServiceProvider.deletePublishedCollection( publishSettings, info )
	logger:trace('deletePublishedCollection')
end

function publishServiceProvider.getCommentsFromPublishedCollection( publishSettings, arrayOfPhotoInfo, commentCallback )
	logger:trace('getCommentsFromPublishedCollection')
end

-- publishServiceProvider.titleForPhotoRating = LOC "$$$/GPhoto/TitleForPhotoRating=Favorite Count"
function publishServiceProvider.getRatingsFromPublishedCollection( publishSettings, arrayOfPhotoInfo, ratingCallback )
	logger:trace('getRatingsFromPublishedCollection')
end

function publishServiceProvider.canAddCommentsToService( publishSettings )
	logger:trace('canAddCommentsToService')
end

function publishServiceProvider.addCommentToPublishedPhoto( publishSettings, remotePhotoId, commentText )
	logger:trace('addCommentToPublishedPhoto')
end

--------------------------------------------------------------------------------

GPhotoPublishSupport = publishServiceProvider

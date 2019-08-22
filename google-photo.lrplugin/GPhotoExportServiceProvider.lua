-- Lightroom SDK
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrView = import 'LrView'

local logger = import 'LrLogger'( 'GPhotoAPI' )
logger:enable('logfile')

-- Common shortcuts
local bind = LrView.bind
local share = LrView.share

-- GPhoto plug-in
require 'GPhotoAPI'
require 'GPhotoPublishSupport'

--------------------------------------------------------------------------------

local exportServiceProvider = {}

-- publish specific hooks are in another file
for name, value in pairs( GPhotoPublishSupport ) do
	exportServiceProvider[ name ] = value
end

local function dumpTable(t)
	for k,v in pairs(t) do
		logger:info(k, type(v), v)
		if type(v) == 'table' then
			for k2,v2 in pairs(v) do
				logger:info(k .. '>' .. k2, type(v2), v2)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- support only publish
-- TODO: support export
exportServiceProvider.supportsIncrementalPublish = 'only'

exportServiceProvider.exportPresetFields = {
	{ key = 'consumer_key', default = '' },
	{ key = 'consumer_secret', default = '' },
	{ key = 'access_token', default = '' },
	{ key = 'refresh_token', default = '' },
	{ key = 'separator', default = '  |  ' },
}

--- photos are always rendered to a temporary location and are deleted when the export is complete
exportServiceProvider.hideSections = { 'exportLocation' }

exportServiceProvider.allowFileFormats = { 'JPEG' }
exportServiceProvider.allowColorSpaces = { 'sRGB' }

-- recommended when exporting to the web
exportServiceProvider.hidePrintResolution = true

-- TODO: should be true
exportServiceProvider.canExportVideo = false -- video is not supported through this sample plug-in

--------------------------------------------------------------------------------
-- Google Photo SPECIFIC: Helper functions and tables.

local function updateCantExportBecause( propertyTable )
	if not propertyTable.validAccount then
		propertyTable.LR_cantExportBecause = LOC "$$$/GPhoto/ExportDialog/NoLogin=You haven't logged in to Google Photo yet."
		return
	end
	propertyTable.LR_cantExportBecause = nil
end

local displayNameForTitleChoice = {
	filename = LOC "$$$/GPhoto/ExportDialog/Title/Filename=Filename",
	title = LOC "$$$/GPhoto/ExportDialog/Title/Title=IPTC Title",
	empty = LOC "$$$/GPhoto/ExportDialog/Title/Empty=Leave Blank",
}

local kSafetyTitles = {
	safe = LOC "$$$/GPhoto/ExportDialog/Safety/Safe=Safe",
	moderate = LOC "$$$/GPhoto/ExportDialog/Safety/Moderate=Moderate",
	restricted = LOC "$$$/GPhoto/ExportDialog/Safety/Restricted=Restricted",
}

local function booleanToNumber( value )
	return value and 1 or 0
end

--------------------------------------------------------------------------------
function exportServiceProvider.startDialog( propertyTable )
	logger:trace('startDialog')

	-- Clear login if it's a new connection.
	--propertyTable.access_token = 'ya29.Ci_UA7aEsvT6-oVI8fjxZvB6i8oO13WgdZUviLaCVtpEPYZqhQcQycR-u2X9xtmYGA'
	if not propertyTable.LR_editingExistingPublishConnection then
		propertyTable.username = nil
		propertyTable.nsid = nil
		propertyTable.auth_token = nil
	end

	-- Can't export until we've validated the login.
	propertyTable:addObserver( 'validAccount', function() updateCantExportBecause( propertyTable ) end )
	updateCantExportBecause( propertyTable )

	-- Make sure we're logged in.
	logger:trace('call updateExportSettings in startDialog')
	require 'GPhotoUser'
	GPhotoUser.verifyLogin( propertyTable )
end


--------------------------------------------------------------------------------

function exportServiceProvider.sectionsForTopOfDialog( f, propertyTable )
	return {
		{
			title = LOC "$$$/GPhoto/ExportDialog/Account=Google Photo Account",
			synopsis = bind 'accountStatus',

			f:row {
				spacing = f:control_spacing(),

				f:static_text {
					title = bind 'accountStatus',
					alignment = 'right',
					fill_horizontal = 1,
				},
				f:push_button {
					width = tonumber( LOC "$$$/locale_metric/GPhoto/ExportDialog/LoginButton/Width=160" ),
					title = bind 'loginButtonTitle',
					enabled = bind 'loginButtonEnabled',
					action = function()
						require 'GPhotoUser'
						GPhotoUser.login( propertyTable )
					end,
				},
			},

			f:row {
				spacing = f:control_spacing(),
				f:separator {
					fill_vertical = 0,
					fill_horizontal = 1,
				},
			},

			f:row {
				spacing = f:control_spacing(),
				f:static_text {
					title = LOC "$$$/GPhoto/ExportDialog/ForDevelopers=for Developers (If you want to use your own API Key)",
					alignment = 'left',
					fill_horizontal = 1,
				},
			},

			f:row {
				spacing = f:control_spacing(),
				f:static_text {
					title = LOC "$$$/GPhoto/ExportDialog/ConsumerKey=Client ID",
					alignment = 'right',
					fill_horizontal = 1,
				},
				f:edit_field {
					immediate = true, -- update value w/every keystroke
					fill_horizontal = 1,
					wraps = false,
					value = bind 'consumer_key_input',
				},
			},

			f:row {
				spacing = f:control_spacing(),
				f:static_text {
					title = LOC "$$$/GPhoto/ExportDialog/ConsumerSecret=Client Secret",
					alignment = 'right',
					fill_horizontal = 1,
				},
				f:password_field {
					immediate = true, -- update value w/every keystroke
					fill_horizontal = 1,
					wraps = false,
					value = bind 'consumer_secret_input',
				},
			},


		},
		{
			title = LOC "$$$/GPhoto/ExportDialog/Settings=Google Photo Settings",

			f:row {
				spacing = f:control_spacing(),
				f:static_text {
					title = LOC "$$$/GPhoto/ExportDialog/Separator=Separator between title and description",
					alignment = 'right',
					fill_horizontal = 1,
				},
				f:edit_field {
					immediate = true, -- update value w/every keystroke
					fill_horizontal = 1,
					wraps = false,
					value = bind 'separator',
				},
			},

		},
	}
end

--------------------------------------------------------------------------------
function exportServiceProvider.updateExportSettings( propertyTable )
	propertyTable.access_token = ''
	logger:trace('updateExportSettings')
	logger:trace("access_token: '" .. propertyTable.access_token .. "'")
	logger:trace("refresh_token: '" .. propertyTable.refresh_token .. "'")

	local access_token = GPhotoAPI.refreshToken(propertyTable)
	if access_token then
		propertyTable.access_token = access_token
	end
	logger:trace('call updateExportSettings in updateExportSettings')
	require 'GPhotoUser'
	GPhotoUser.verifyLogin( propertyTable )

	local prefs = import 'LrPrefs'.prefsForPlugin()
	if not prefs.counter then
		prefs.counter = 1
	else
		prefs.counter = prefs.counter + 1
	end
	logger:trace("counter:", prefs.counter)
end

--------------------------------------------------------------------------------
function exportServiceProvider.processRenderedPhotos( functionContext, exportContext )
	logger:trace('processRenderedPhotos')

	local exportSession = exportContext.exportSession
	local exportSettings = assert( exportContext.propertyTable )
	local nPhotos = exportSession:countRenditions()

	-- Set progress title.
	local progressScope = exportContext:configureProgress {
						title = nPhotos > 1
									and LOC( "$$$/GPhoto/Publish/Progress=Publishing ^1 photos to GPhoto", nPhotos )
									or LOC "$$$/GPhoto/Publish/Progress/One=Publishing one photo to GPhoto",
					}

	-- Save off uploaded photo IDs so we can take user to those photos later.
	local uploadedPhotoIds = {}

	local publishedCollectionInfo = exportContext.publishedCollectionInfo
	local albumId = publishedCollectionInfo.remoteId
	local isDefaultCollection = publishedCollectionInfo.isDefaultCollection
	logger:trace(string.format('processRenderedPhotos albumId:%s, isDefaultCollection: %s', albumId, isDefaultCollection))
	if not albumId and not isDefaultCollection then
		albumId = GPhotoAPI.findOrCreateAlbum(exportSettings, publishedCollectionInfo.name)
	end

	local couldNotPublishBecauseFreeAccount = {}
	local GPhotoPhotoIdsForRenditions = {}

	local cannotRepublishCount = 0

	for i, rendition in exportContext.exportSession:renditions() do
		local GPhotoPhotoId = rendition.publishedPhotoId
		GPhotoPhotoIdsForRenditions[ rendition ] = GPhotoPhotoId
	end

	local photosetUrl
	for i, rendition in exportContext:renditions { stopIfCanceled = true } do
		-- Update progress scope.
		progressScope:setPortionComplete( ( i - 1 ) / nPhotos )

		-- Get next photo.
		local photo = rendition.photo

		-- See if we previously uploaded this photo.
		local GPhotoPhotoId = GPhotoPhotoIdsForRenditions[ rendition ]

		if not rendition.wasSkipped then
			local success, pathOrMessage = rendition:waitForRender()

			-- Update progress scope again once we've got rendered photo.
			progressScope:setPortionComplete( ( i - 0.5 ) / nPhotos )

			-- Check for cancellation again after photo has been rendered.
			if progressScope:isCanceled() then break end

			if success then
				-- Build up common metadata for this photo.
				local title = photo:getFormattedMetadata( 'title' )
				local description = photo:getFormattedMetadata( 'caption' )
				local keywordTags = photo:getFormattedMetadata( 'keywordTagsForExport' )

				local tags

				if keywordTags then
					tags = {}
					local keywordIter = string.gfind( keywordTags, "[^,]+" )

					for keyword in keywordIter do
						if string.sub( keyword, 1, 1 ) == ' ' then
							keyword = string.sub( keyword, 2, -1 )
						end
						if string.find( keyword, ' ' ) ~= nil then
							keyword = '"' .. keyword .. '"'
						end
						tags[ #tags + 1 ] = keyword
					end
				end

				-- Upload or replace the photo.
				GPhotoPhotoId = GPhotoAPI.uploadPhoto( exportSettings, {
										photoId = GPhotoPhotoId,
										albumId = albumId,
										filePath = pathOrMessage,
										title = title,
										description = description,
										tags = table.concat( tags, ',' ),
									} )
				-- delete temp file.
				LrFileUtils.delete( pathOrMessage )

				-- Remember this in the list of photos we uploaded.
				uploadedPhotoIds[ #uploadedPhotoIds + 1 ] = GPhotoPhotoId

				-- Record this GPhoto ID with the photo so we know to replace instead of upload.
				logger:info('recordPublishedPhotoId:"'..tostring(GPhotoPhotoId)..'"')
				rendition:recordPublishedPhotoId( tostring(GPhotoPhotoId) )
			end
		else
			-- To get the skipped photo out of the to-republish bin.
			logger:info('recordPublishedPhotoId2')
			rendition:recordPublishedPhotoId(rendition.publishedPhotoId)
		end
	end

	if #uploadedPhotoIds > 0 then
		if ( not isDefaultCollection ) then
			logger:info('recordRemoteCollectionId')
			exportSession:recordRemoteCollectionId( albumId )
		end
		-- Set up some additional metadata for this collection.
		--exportSession:recordRemoteCollectionUrl( photosetUrl )
	end

	progressScope:done()
end

--------------------------------------------------------------------------------

return exportServiceProvider

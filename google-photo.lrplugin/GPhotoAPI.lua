-- Lightroom SDK
local LrBinding = import 'LrBinding'
local LrDate = import 'LrDate'
local LrDialogs = import 'LrDialogs'
local LrErrors = import 'LrErrors'
local LrFileUtils = import 'LrFileUtils'
local LrFunctionContext = import 'LrFunctionContext'
local LrHttp = import 'LrHttp'
local LrMD5 = import 'LrMD5'
local LrPathUtils = import 'LrPathUtils'
local LrStringUtils = import "LrStringUtils"
local LrView = import 'LrView'
local LrXml = import 'LrXml'

local prefs = import 'LrPrefs'.prefsForPlugin()

local bind = LrView.bind
local share = LrView.share

local logger = import 'LrLogger'( 'GPhotoAPI' )
logger:enable('logfile')

--============================================================================--

local ACCESS_TOKEN_URL = "https://www.googleapis.com/oauth2/v4/token"
local USER_AGENT = "Lightroom Google Photo Plugin 0.2.0"

local CONSUMER_KEY = ""
local CONSUMER_SECRET = ""
local SALT = ""

require "sha1"

GPhotoAPI = {}

--------------------------------------------------------------------------------

local appearsAlive

--------------------------------------------------------------------------------

local function formatError( nativeErrorCode )
	return LOC "$$$/GPhoto/Error/NetworkFailure=Could not connect Google Photo. Please check your Internet connection."
end

--------------------------------------------------------------------------------

local function trim( s )
	return string.gsub( s, "^%s*(.-)%s*$", "%1" )
end

--------------------------------------------------------------------------------

--[[ Some Handy Constants ]]--

-- Cocaoa time of 0 is unix time 978307200
local COCOA_TIMESHIFT = 978307200

--[[ Some Handy Helper Functions ]]--
local function oauth_encode( value )
	return tostring( string.gsub( value, "[^-._~a-zA-Z0-9]",
		function( c )
			return string.format( "%%%02x", string.byte( c ) ):upper()
		end ) )
end

local function unix_timestamp()
	return tostring(COCOA_TIMESHIFT + math.floor(LrDate.currentTime() + 0.5))
end

local function generate_nonce()
	return LrMD5.digest( tostring(math.random())
			.. tostring(LrDate.currentTime())
			.. SALT )
end

--[[ Returns an oAuth athorization header and a query string (or post body). ]]--
local function oauth_sign( consumer_key, consumer_secret, method, url, args )

	assert( method == "GET" or method == "POST" )

	--using default key
	if consumer_key == "" or consumer_key == nil then
		logger:info( "Using default key" )
		consumer_key = CONSUMER_KEY
		consumer_secret = CONSUMER_SECRET
	end

	--common oauth parameters
	args.oauth_consumer_key = consumer_key
	args.oauth_timestamp = unix_timestamp()
	args.oauth_version = "1.0"
	args.oauth_nonce = generate_nonce()
	args.oauth_signature_method = "HMAC-SHA1"

	local oauth_token_secret = args.oauth_token_secret or ""
	args.oauth_token_secret = nil

	local data = ""
	local query_string = ""
	local header = ""

	local data_pattern = "%s%s=%s"
	local query_pattern = "%s%s=%s"
	local header_pattern = "OAuth %s%s=\"%s\""

	local keys = {}
	for key in pairs( args ) do
		table.insert( keys, key )
	end
	table.sort( keys )

	for _, key in ipairs( keys ) do
		local value = args[key]

		-- url encode the value if it's not an oauth parameter
		if string.find( key, "oauth" ) == 1 and key ~= "oauth_callback" then
			value = string.gsub( value, " ", "+" )
			value = oauth_encode( value )
		end

		-- oauth encode everything, non oauth parameters get encoded twice
		value = oauth_encode( value )

		-- build up the base string to sign
		data = string.format( data_pattern, data, key, value )
		data_pattern = "%s&%s=%s"

		-- build up the oauth header and query string
		if string.find( key, "oauth" ) == 1 then
			header = string.format( header_pattern, header, key, value )
			header_pattern = "%s, %s=\"%s\""
		else
			query_string = string.format( query_pattern, query_string, key, value )
			query_pattern = "%s&%s=%s"
		end
	end

	local to_sign = string.format( "%s&%s&%s", method, oauth_encode( url ), oauth_encode( data ) )
	local key = string.format( "%s&%s", oauth_encode( consumer_secret ), oauth_encode( oauth_token_secret ) )
	local hmac_binary = hmac_sha1_binary( key, to_sign )
	local hmac_b64 = LrStringUtils.encodeBase64( hmac_binary )

	data = string.format( "%s&oauth_signature=%s", data, oauth_encode( hmac_b64 ) )
	header = string.format( "%s, oauth_signature=\"%s\"", header, oauth_encode( hmac_b64 ) )

	return query_string, { field = "Authorization", value = header }
end

--------------------------------------------------------------------------------
local function call_it( consumer_key, consumer_secret, method, url, params, rid )
	local query_string, auth_header = oauth_sign( consumer_key, consumer_secret, method, url, params )

	if rid then
		logger:trace( "Query " .. rid .. ": " .. method .. " " .. url .. "?" .. query_string )
	end

	if method == "POST" then
		return LrHttp.post( url, query_string,
			{ auth_header,
				{ field = "Content-Type", value = "application/x-www-form-urlencoded" },
				{ field = "User-Agent", value = USER_AGENT },
				{ field = "Cookie", value = "GARBAGE" }
			}
		)
	else
		return LrHttp.get( url .. "?" .. query_string,
			{ auth_header,
				{ field = "User-Agent", value = USER_AGENT }
			}
		)
	end
end

local function auth_header(propertyTable)
	logger:info("access_token:", propertyTable.access_token)
	return {
		{ field = 'GData-Version', value = '2'},
		{ field = 'Authorization', value = 'Bearer ' .. propertyTable.access_token }
	}
end

--------------------------------------------------------------------------------

function GPhotoAPI.convertIds( photoId )
	local ids = {}
	for id in string.gmatch(photoId, "%d+") do
		ids[#ids+1] = id
	end
	return ids
end

function GPhotoAPI.uploadPhoto( propertyTable, params )
	assert( type( params ) == 'table', 'GPhotoAPI.uploadPhoto: params must be a table' )
	logger:info( 'uploadPhoto: ', params.filePath )
	local postUrlForBytes = 'https://photoslibrary.googleapis.com/v1/uploads'
	local originalParams = params.photoId and table.shallowcopy( params )

	local filePath = assert( params.filePath )
	params.filePath = nil

	local fileName = LrPathUtils.leafName( filePath )
	local headers = auth_header(propertyTable)
	headers[#headers+1] = { field = 'Content-Type', value = 'application/octet-stream'}
	headers[#headers+1] = { field = 'X-Goog-Upload-File-Name', value = fileName }
	headers[#headers+1] = { field = 'X-Goog-Upload-Protocol', value = 'raw' }

	local image = LrFileUtils.readFile( filePath )
	local resultRaw, hdrs
	logger:info("upload(binary) start: ".. fileName .. " url: ".. postUrlForBytes)
	resultRaw, hdrs = LrHttp.post( postUrlForBytes, image, headers)
	logger:info(string.format("upload(binary) end: %s, result: %s", hdrs.status, resultRaw))
	if not resultRaw then
		if hdrs and hdrs.error then
			LrErrors.throwUserError( formatError( hdrs.error.nativeCode ) )
		end
	end
	-- Parse GPhoto response for photo ID.
	local uploadToken = resultRaw

	local postUrlForMeta = 'https://photoslibrary.googleapis.com/v1/mediaItems:batchCreate'
	local meta = {
		albumId = params.albumId,
		newMediaItems = {
			{
				description = "Lightroom Uploaded",
	 			simpleMediaItem = {
					uploadToken = uploadToken
				}
			}
		}
	}
	local json = require 'json'
	local bodyMeta = json.encode(meta)

	local headersMeta = auth_header(propertyTable)
	headersMeta[#headersMeta+1] = { field = 'Content-Type', value = 'application/json'}

	logger:info("upload(meta) start: ".. postUrlForBytes)
	resultRaw, hdrs = LrHttp.post( postUrlForMeta, bodyMeta, headersMeta)
	logger:info(string.format("upload(meta) end: %s, result: %s", hdrs.status, resultRaw))

	local resultMeta = json.decode(resultRaw)
	local photoId = resultMeta["newMediaItemResults"][1]["mediaItem"]["id"]
	if photoId then
		logger:info(string.format("upload successful: Photo ID: %s, Album ID: %s", photoId, params.albumId))
		return photoId
	else
		logger:info("upload end: exception")
		LrErrors.throwUserError( LOC( "$$$/GPhoto/Error/API/Upload=GPhoto API returned an error message (function upload, message ^1)",
			'error message' ) )
	end
	logger:info("upload ended")
end

--------------------------------------------------------------------------------
function GPhotoAPI.refreshToken(propertyTable)
	logger:trace('refreshToken invoked')
	-- get an access token_secret
	local args = {
		client_id = propertyTable.consumer_key,
		client_secret = propertyTable.consumer_secret,
		-- refresh_token = "1/lQTq4grmWmer0PAnveimWjVJ7ZVE482iclp-WJb6Vgc", -- propertyTable.refresh_token,
		refresh_token = propertyTable.refresh_token,
		grant_type = 'refresh_token',
	}

	--using default key
	if propertyTable.consumer_key == "" or propertyTable.consumer_key == nil then
		logger:info( "Using default key" )
		args.client_id = CONSUMER_KEY
		args.client_secret = CONSUMER_SECRET
	end

	logger:info("refresh_token: '" .. args.refresh_token .. "'")
	local response, headers = call_it( args.client_id, args.client_secret, "POST", ACCESS_TOKEN_URL, args, math.random(99999) )
	logger:info("Refresh token response: ", response)
	if not response or not headers.status then
		LrErrors.throwUserError( "Could not connect to Google Photo. Please make sure you are connected to the internet and try again." )
	end
	local json = require 'json'
	local auth = json.decode(response)
	-- auth.access_token = LrStringUtils.trimWhitespace(auth.access_token)
	logger:info("Old access_token: '" .. propertyTable.access_token .. "'")
	logger:info("New access_token: '" .. auth.access_token .. "'")

	prefs.access_token = auth.access_token

	if not auth.access_token then
		LrErrors.throwUserError( "Refresh token failed." )
	end
	logger:info("Refresh token succeeded")
	return auth.access_token
end

--------------------------------------------------------------------------------
function GPhotoAPI.login(context, consumer_key, consumer_secret)
	local redirectURI = 'https://stanaka.github.io/lightroom-google-photo-plugin/redirect'
	--local redirectURI = 'urn:ietf:wg:oauth:2.0:oob'
	--local scope = 'https://picasaweb.google.com/data/'
	local scope = 'https://www.googleapis.com/auth/photoslibrary'

	--using default key
	if consumer_key == "" or consumer_key == nil then
		logger:info( "Using default key" )
		consumer_key = CONSUMER_KEY
		consumer_secret = CONSUMER_SECRET
	end

	local authURL = string.format(
		'https://accounts.google.com/o/oauth2/v2/auth?scope=%s&redirect_uri=%s&response_type=code&prompt=consent&access_type=offline&client_id=%s',
		scope, redirectURI, consumer_key)

	logger:info('openAuthUrl: ', authURL)
	LrHttp.openUrlInBrowser( authURL )

	local properties = LrBinding.makePropertyTable( context )
	local f = LrView.osFactory()
	local contents = f:column {
		bind_to_object = properties,
		spacing = f:control_spacing(),
		f:picture {
			value = _PLUGIN:resourceId( "small_gphoto@2x.png" )
		},
		f:static_text {
			title = "Enter the verification token provided by the website",
			place_horizontal = 0.5,
		},
		f:edit_field {
			width = 300,
			value = bind "verifier",
			place_horizontal = 0.5,
		},
	}

	GPhotoAPI.URLCallback = function( code )
		logger:info("URLCallback2", code)

		properties.verifier = code
		LrDialogs.stopModalWithResult(contents, "ok")
	end

	local action = LrDialogs.presentModalDialog( {
		title = "Enter verification token",
		contents = contents,
		actionVerb = "Authorize"
	} )

	GPhotoAPI.URLCallback = nil

	if action == "cancel" or not properties.verifier then return nil end

	-- get an access token_secret
	local args = {
		client_id = consumer_key,
		client_secret = consumer_secret,
		redirect_uri = redirectURI,
		code = LrStringUtils.trimWhitespace(properties.verifier),
		grant_type = 'authorization_code',
	}

	local response, headers = call_it( consumer_key, consumer_secret, "POST", ACCESS_TOKEN_URL, args, math.random(99999) )
	logger:info(response)
	if not response or not headers.status then
		LrErrors.throwUserError( "Could not connect to googleapis.com. Please make sure you are connected to the internet and try again." )
	end

	local json = require 'json'
	local auth = json.decode(response)
	local access_token = auth.access_token
	-- prefs.access_token = auth.access_token
	local refresh_token = auth.refresh_token

	if not access_token or not refresh_token then
		LrErrors.throwUserError( "Login failed." )
	end
	logger:info("Login succeeded")
	return {
		access_token = access_token,
		refresh_token = refresh_token,
	}

end

function GPhotoAPI.listAlbums(propertyTable)
	logger:trace("listAlbums")
	local url = 'https://photoslibrary.googleapis.com/v1/albums'
	local headers = auth_header(propertyTable)
	local nextPageToken
	local albums = {}

	local count = 0
	repeat
		if nextPageToken then
			url = 'https://photoslibrary.googleapis.com/v1/albums?pageToken=' .. nextPageToken
		end
		logger:info("listAlbums url:", url)
		local result, hdrs = LrHttp.get( url, headers )
		logger:info("listAlbums result:", result)
		local json = require 'json'
		local results = json.decode(result)
		nextPageToken = results["nextPageToken"]
		if not results.albums then
			break
		end
		for i,v in ipairs(results.albums) do
			albums[#albums+1] = v
		end
		count = count + 1
		logger:info("listAlbums nextPageToken:", nextPageToken)
	until not nextPageToken or count > 50

	return albums
end

function GPhotoAPI.findOrCreateAlbum(propertyTable, albumName)
	logger:trace("findOrCreateAlbum")
	local albums = GPhotoAPI.listAlbums(propertyTable)
	-- local entries = albums.albums
	for i, entry in ipairs(albums) do
		local title = entry["title"]
		logger:info("Album:", title)
		if title == albumName then
			local albumId = entry["id"]
			logger:info("Album found:", albumId)
			return albumId
		end
	end

	local url = 'https://photoslibrary.googleapis.com/v1/albums'
	local json = require 'json'
	local body = json.encode({ album = { title = albumName } })
	-- local body = string.format([[{"album": {"title": "%s"}}]], albumName)
	local headers = auth_header(propertyTable)
	headers[#headers+1] = { field = 'Content-Type', value = 'application/json' }

	local result, hdrs = LrHttp.post( url, body, headers )
	logger:trace("findOrCreateAlbum result:", result)
	local entry = json.decode(result)
	local albumId = entry["id"]
	logger:info("Album created:", albumId)
	return albumId
end

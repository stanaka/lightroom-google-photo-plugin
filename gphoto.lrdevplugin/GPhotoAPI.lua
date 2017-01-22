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

local CONSUMER_KEY = "";
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
local function oauth_sign( method, url, args )

	assert( method == "GET" or method == "POST" )

	--common oauth parameters
	args.oauth_consumer_key = CONSUMER_KEY
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
	local key = string.format( "%s&%s", oauth_encode( CONSUMER_SECRET ), oauth_encode( oauth_token_secret ) )
	local hmac_binary = hmac_sha1_binary( key, to_sign )
	local hmac_b64 = LrStringUtils.encodeBase64( hmac_binary )

	data = string.format( "%s&oauth_signature=%s", data, oauth_encode( hmac_b64 ) )
	header = string.format( "%s, oauth_signature=\"%s\"", header, oauth_encode( hmac_b64 ) )

	return query_string, { field = "Authorization", value = header }
end

--------------------------------------------------------------------------------
local function call_it( method, url, params, rid )
	local query_string, auth_header = oauth_sign( method, url, params )

	if rid then
		logger:trace( "Query " .. rid .. ": " .. method .. " " .. url .. "?" .. query_string )
	end

	if method == "POST" then
		return LrHttp.post( url, query_string,
			{ auth_header,
				{ field = "Content-Type", value = "application/x-www-form-urlencoded" },
				{ field = "User-Agent", value = "Lightroom Google Photo Plugin 0.1.0" },
				{ field = "Cookie", value = "GARBAGE" }
			}
		)
	else
		return LrHttp.get( url .. "?" .. query_string,
			{ auth_header,
				{ field = "User-Agent", value = "Lightroom Google Photo Plugin 0.1.0" }
			}
		)
	end
end

local function auth_header(propertyTable)
	logger:info("access_token:", propertyTable.access_token)
	return {
		{ field = 'GData-Version', value = '2'},
		--{ field = 'Authorization', value = 'Bearer ' .. prefs.access_token }
		{ field = 'Authorization', value = 'Bearer ' .. propertyTable.access_token }
	}
end

--------------------------------------------------------------------------------
local function findXMLNodeByName( node, name, namespace, type )
	local nodeType = string.lower( node:type() )

	if nodeType == 'element' then
		local n, ns = node:name()
		if n == name and ((not namespace) or ns == namespace) then
			if type == 'text' then
				return node:text()
			else
				return node
			end
		else
			local count = node:childCount()
			for i = 1, count do
				local result = findXMLNodeByName( node:childAtIndex( i ), name, namespace, type)
				if result then
					return result
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
local function findXMLNodesByName( node, name, namespace, array )
	local nodeType = string.lower( node:type() )
	local ret = array and array or {}

	if nodeType == 'element' then
		local n, ns = node:name()
		if n == name and ((not namespace) or ns == namespace) then
			ret[#ret+1] = node
		else
			local count = node:childCount()
			for i = 1, count do
				findXMLNodesByName( node:childAtIndex( i ), name, namespace, ret)
			end
		end
	end
	return ret
end

--------------------------------------------------------------------------------

function GPhotoAPI.uploadPhoto( propertyTable, params )
	assert( type( params ) == 'table', 'GPhotoAPI.uploadPhoto: params must be a table' )
	logger:info( 'uploadPhoto: ', params.filePath )
	local postUrl = string.format('https://picasaweb.google.com/data/feed/api/user/%s/albumid/%s',
		'default', params.albumId or 'default')
	local originalParams = params.photoId and table.shallowcopy( params )

	local filePath = assert( params.filePath )
	params.filePath = nil

	local fileName = LrPathUtils.leafName( filePath )
	local headers = auth_header(propertyTable)
	headers[#headers+1] = { field = 'Content-Type', value = 'image/jpeg'}
	headers[#headers+1] = { field = 'Slug', value = fileName }

	local image = LrFileUtils.readFile( filePath )
	local method = 'POST'
	-- Post it and wait for confirmation.
	if params.photoId then
		local ids = {}
		for id in string.gmatch(params.photoId, "%d+") do
			ids[#ids+1] = id
		end
		postUrl = string.format( 'https://picasaweb.google.com/data/media/api/user/%s/albumid/%s/photoid/%s', prefs.userId, ids[2], ids[1])
		headers[#headers+1] = { field = 'If-Match', value = '*' }
		method = 'PUT'
	end
	logger:info("upload start: ".. postUrl)
	local result, hdrs = LrHttp.post( postUrl, image, headers, method)
	logger:info("upload end: ", result)
	if not result then
		if hdrs and hdrs.error then
			LrErrors.throwUserError( formatError( hdrs.error.nativeCode ) )
		end
	end

	-- Parse GPhoto response for photo ID.
	local xml = LrXml.parseXml( result )
	local photoId = findXMLNodeByName(xml, 'id', 'http://schemas.google.com/photos/2007', 'text')
	if photoId then
		logger:info("upload successful: ", simpleXml['link:edit-media']['href'], xml)
		local albumId = findXMLNodeByName(xml, 'albumid', 'http://schemas.google.com/photos/2007', 'text')
		logger:info(string.format("Photo ID: %s, Album ID: %s", photoId, albumId))

		return string.format("%s,%s", photoId, albumId)

	elseif params.photoId and simpleXml.err and tonumber( simpleXml.err.code ) == 7 then
		logger:info("upload end: err")

		-- Photo is missing. Most likely, the user deleted it outside of Lightroom. Just repost it.
		originalParams.photoId = nil
		return GPhotoAPI.uploadPhoto( propertyTable, originalParams )
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
		client_id = CONSUMER_KEY,
		client_secret = CONSUMER_SECRET,
		refresh_token = propertyTable.refresh_token,
		grant_type = 'refresh_token',
	}

	local response, headers = call_it( "POST", ACCESS_TOKEN_URL, args, math.random(99999) )
	logger:info("Refresh token response: ", response)
	if not response or not headers.status then
		LrErrors.throwUserError( "Could not connect to 500px.com. Please make sure you are connected to the internet and try again." )
	end
	local json = require 'json'
	local auth = json.decode(response)
	-- auth.access_token = LrStringUtils.trimWhitespace(auth.access_token)
	logger:info("Old access_token: '" .. prefs.access_token .. "'")
	logger:info("New access_token: '" .. auth.access_token .. "'")

	prefs.access_token = auth.access_token

	if not auth.access_token then
		LrErrors.throwUserError( "Refresh token failed." )
	end
	logger:info("Refresh token succeeded")
	return auth.access_token
end

	--------------------------------------------------------------------------------
function GPhotoAPI.login(context)
	-- local redirectURI = 'lightroom:/com.adobe.lightroom.export.gphoto'
	local redirectURI = 'urn:ietf:wg:oauth:2.0:oob'
	local scope = 'https://picasaweb.google.com/data/'
	local authURL = string.format(
		'https://accounts.google.com/o/oauth2/v2/auth?scope=%s&redirect_uri=%s&response_type=code&client_id=%s',
		scope, redirectURI, CONSUMER_KEY)

	logger:info('openAuthUrl: ', authURL)
	LrHttp.openUrlInBrowser( authURL )

	local properties = LrBinding.makePropertyTable( context )
	local f = LrView.osFactory()
	local contents = f:column {
		bind_to_object = properties,
		spacing = f:control_spacing(),
		f:picture {
			value = _PLUGIN:resourceId( "login.png" )
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

	local action = LrDialogs.presentModalDialog( {
		title = "Enter verification token",
		contents = contents,
		actionVerb = "Authorize"
	} )

	if action == "cancel" then return nil end

	-- get an access token_secret
	local args = {
		client_id = CONSUMER_KEY,
		client_secret = CONSUMER_SECRET,
		redirect_uri = redirectURI,
		code = LrStringUtils.trimWhitespace(properties.verifier),
		grant_type = 'authorization_code',
	}

	local response, headers = call_it( "POST", ACCESS_TOKEN_URL, args, math.random(99999) )
	logger:info(response)
	if not response or not headers.status then
		LrErrors.throwUserError( "Could not connect to 500px.com. Please make sure you are connected to the internet and try again." )
	end

	local json = require 'json'
	local auth = json.decode(response)
	local access_token = auth.access_token
	prefs.access_token = auth.access_token
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

function GPhotoAPI.findAlbumById(propertyTable, targetAlbumId)
	logger:trace("findAlbumById:", targetAlbumId)
	local url = string.format('https://picasaweb.google.com/data/entry/api/user/%s/albumid/%s', 'default', targetAlbumId)
	local headers = auth_header(propertyTable)

	local result, hdrs = LrHttp.get( url, headers )
	logger:info("findAlbumById result:", result)
	return result
end

function GPhotoAPI.findOrCreateAlbum(propertyTable, albumName)
	logger:trace("findOrCreateAlbum")
	local url = string.format('https://picasaweb.google.com/data/feed/api/user/%s', 'default')
	local headers = auth_header(propertyTable)

	local result, hdrs = LrHttp.get( url, headers )
	--logger:info("findOrCreateAlbum result:", result)
	local xml = LrXml.parseXml( result )
	local userId = findXMLNodeByName(xml, 'user', 'http://schemas.google.com/photos/2007', 'text')
	prefs.userId = userId
	local entries = findXMLNodesByName(xml, 'entry')
	for k, entry in pairs(entries) do
		local title = findXMLNodeByName(entry, 'title', nil, 'text')
		logger:info("Album:", title)
		if title == albumName then
			local albumId = findXMLNodeByName(entry, 'id', 'http://schemas.google.com/photos/2007', 'text')
			logger:info("Album found:", albumId)
			return albumId
		end
	end

	url = string.format('https://picasaweb.google.com/data/feed/api/user/%s', prefs.userId)
	local body = string.format([[
        <entry xmlns='http://www.w3.org/2005/Atom'
            xmlns:media='http://search.yahoo.com/mrss/'
            xmlns:gphoto='http://schemas.google.com/photos/2007'>
          <title type='text'>%s</title>
          <category scheme='http://schemas.google.com/g/2005#kind'
            term='http://schemas.google.com/photos/2007#album'></category>
        </entry>]], albumName)
	local headers = auth_header(propertyTable)
	headers[#headers+1] = { field = 'Content-Type', value = 'application/atom+xml' }

	local result, hdrs = LrHttp.post( url, body, headers )
	logger:trace("findOrCreateAlbum result:", result)

	local entry = LrXml.parseXml( result )
	local albumId = findXMLNodeByName(entry, 'id', 'http://schemas.google.com/photos/2007', 'text')
	logger:info("Album created:", albumId)
	return albumId
end

--------------------------------------------------------------------------------

function GPhotoAPI.updateAlbum(propertyTable, albumId, albumName)
	logger:trace("updateAlbum:", albumId, albumName)
	local url = string.format('https://picasaweb.google.com/data/entry/api/user/%s/albumid/%s', prefs.userId, albumId)
	local headers = auth_header(propertyTable)
	local album = GPhotoAPI.findAlbumById(propertyTable, albumId)

	local body = string.gsub(album, '<title>.+</title>', '<title>'..albumName..'</title>')
	local method = 'PUT'
	headers[#headers+1] = { field = 'Content-Type', value = 'application/atom+xml' }
	headers[#headers+1] = { field = 'If-Match', value = '*' }

	logger:trace("updateAlbum url:", url)
	logger:trace("updateAlbum body:", body)
	local result, hdrs = LrHttp.post( url, body, headers, method )
	logger:trace("updateAlbum result:", result)
	if not result then
		if hdrs and hdrs.error then
			LrErrors.throwUserError( formatError( hdrs.error.nativeCode ) )
		end
	end
	return true
end


--------------------------------------------------------------------------------

function GPhotoAPI.listPhotosFromAlbum( propertyTable, params )
	logger:trace('GPhotoAPI.listPhotosFromAlbum')

	local results = {}
	local data, response
	local numPages, curPage = 1, 0
	local itemsPerPage = 1000

	local albumId = params.albumId or 'default'
	local headers = auth_header(propertyTable)
	local photos = {}

	while curPage < numPages do
		-- https://picasaweb.google.com/data/feed/api/user/liz/albumid/albumID?start-index=1&amp;max-results=1000&amp;v=2
		local url = string.format('https://picasaweb.google.com/data/feed/api/user/%s/albumid/%s?start-index=%d&max-result=%d&v2',
			prefs.userId, albumId, (curPage * itemsPerPage) + 1, itemsPerPage)
		curPage = curPage + 1

		logger:trace("call API", url)
		local result, hdrs = LrHttp.get( url, headers )
		logger:trace('get list of photos', result)

		local xml = LrXml.parseXml( result )

		local totalResults = findXMLNodeByName(xml, 'totalResults', 'http://a9.com/-/spec/opensearch/1.1/', 'text')
		logger:trace('totalResults', totalResults)
		itemsPerPage = findXMLNodeByName(xml, 'itemsPerPage', 'http://a9.com/-/spec/opensearch/1.1/', 'text')
		logger:trace('itemsPerPage', itemsPerPage)
		local entries = findXMLNodesByName(xml, 'entry')
		logger:trace('entries', entries)
		for k, entry in pairs(entries) do
			local photoId = findXMLNodeByName(entry, 'id', 'http://schemas.google.com/photos/2007', 'text')
			local albumId = findXMLNodeByName(entry, 'albumid', 'http://schemas.google.com/photos/2007', 'text')
			logger:info(string.format("Photo ID: %s, Album ID: %s", photoId, albumId))

			local remoteId =  string.format("%s,%s", photoId, albumId)

			photos[#photos+1] = {
				remoteId = remoteId,
			}
		end
	end

	return photos
end

--------------------------------------------------------------------------------

function GPhotoAPI.deletePhoto( propertyTable, params )
	logger:info("deletePhoto", params.photoId)
	local ids = {}
	for id in string.gmatch(params.photoId, "%d+") do
		ids[#ids+1] = id
	end
	-- 'DELETE https://picasaweb.google.com/data/entry/api/user/userID/albumid/albumID/photoid/photoID'
	local postUrl = string.format( 'https://picasaweb.google.com/data/entry/api/user/%s/albumid/%s/photoid/%s', prefs.userId, ids[2], ids[1])
	local headers = auth_header(propertyTable)
	headers[#headers+1] = { field = 'If-Match', value = '*' }
	local method = 'DELETE'

	logger:info("deletePhoto start: ".. postUrl)
	local result, hdrs = LrHttp.post( postUrl, '', headers, method)
	logger:info("deletePhoto end: ", result, hdrs)
	for k, v in pairs(hdrs) do
		if type(v) == 'table' then
			for k2, v2 in pairs(v) do
				logger:info("deletePhoto hdrs2:", k2, v2)
			end
		else
			logger:info("deletePhoto hdrs:", k, v)
		end
	end

	if not result then
		if hdrs and hdrs.error then
			LrErrors.throwUserError( formatError( hdrs.error.nativeCode ) )
		end
	end
	return true
end

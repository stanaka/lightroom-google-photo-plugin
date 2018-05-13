-- Lightroom SDK
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrTasks = import 'LrTasks'

local logger = import 'LrLogger'( 'GPhotoAPI' )

require 'GPhotoAPI'

--============================================================================--

GPhotoUser = {}

--------------------------------------------------------------------------------

local function storedCredentialsAreValid( propertyTable )
	logger:trace('storedCredentialsAreValid:',
		propertyTable.access_token and propertyTable.access_token ~= ""
			and propertyTable.refresh_token and propertyTable.refresh_token ~= "")
	return propertyTable.access_token and propertyTable.access_token ~= ""
			and propertyTable.refresh_token and propertyTable.refresh_token ~= ""
end

--------------------------------------------------------------------------------

local function notLoggedIn( propertyTable )
	logger:trace("notLoggedIn invoked.")
	propertyTable.token = nil

	propertyTable.username = nil
	propertyTable.fullname = ''
    propertyTable.access_token = nil
    propertyTable.refresh_token = nil

	propertyTable.accountStatus = LOC "$$$/GPhoto/SignIn=Sign in with your Google account."
	propertyTable.loginButtonTitle = LOC "$$$/GPhoto/LoginButton/NotLoggedIn=Log In"
	propertyTable.loginButtonEnabled = true
	propertyTable.validAccount = false
end

--------------------------------------------------------------------------------

local doingLogin = false

function GPhotoUser.login( propertyTable )

	if doingLogin then return end
	doingLogin = true

	LrFunctionContext.postAsyncTaskWithContext( 'GPhoto login',
	function( context )
		if not propertyTable.LR_editingExistingPublishConnection then
			notLoggedIn( propertyTable )
		end

		propertyTable.accountStatus = LOC "$$$/GPhoto/AccountStatus/LoggingIn=Logging in..."
		propertyTable.loginButtonEnabled = false

		LrDialogs.attachErrorDialogToFunctionContext( context )

		-- Make sure login is valid when done, or is marked as invalid.
		context:addCleanupHandler( function()
			doingLogin = false
			if not storedCredentialsAreValid( propertyTable ) then
				notLoggedIn( propertyTable )
			end
		end )

		-- Request the frob that we need for authentication.
		propertyTable.accountStatus = LOC "$$$/GPhoto/AccountStatus/WaitingForGPhoto=Waiting for response..."

		require 'GPhotoAPI'
        local auth = GPhotoAPI.login(context)

		-- If editing existing connection, make sure user didn't try to change user ID on us.
        --[[
		if propertyTable.LR_editingExistingPublishConnection then
			if auth.user and propertyTable.nsid ~= auth.user.nsid then
				LrDialogs.message( LOC "$$$/GPhoto/CantChangeUserID=You can not change GPhoto accounts on an existing publish connection. Please log in again with the account you used when you first created this connection." )
				return
			end
		end
        ]]

		if auth and auth.access_token then
            logger:info("access_token before: ", auth.access_token)
	        propertyTable.access_token = auth.access_token
	        propertyTable.refresh_token = auth.refresh_token
		end
		logger:trace("access_token after: ", propertyTable.access_token)
		logger:trace("refresh_token after: ", propertyTable.refresh_token)
		GPhotoUser.updateUserStatusTextBindings( propertyTable )
	end )
end

--------------------------------------------------------------------------------
function GPhotoUser.verifyLogin( propertyTable )

	-- Observe changes to prefs and update status message accordingly.
	local function updateStatus()
		logger:trace( "verifyLogin: updateStatus() was triggered." )
		LrTasks.startAsyncTask( function()
			logger:trace( "verifyLogin: updateStatus() is executing." )
			if storedCredentialsAreValid( propertyTable ) then
				propertyTable.loginButtonTitle = LOC "$$$/GPhoto/LoginButton/LoggedIn=Switch Account"
				propertyTable.loginButtonEnabled = true
				propertyTable.validAccount = true
			else
				notLoggedIn( propertyTable )
			end
			GPhotoUser.updateUserStatusTextBindings( propertyTable )
		end )
	end
	propertyTable:addObserver( 'access_token', updateStatus )
	updateStatus()
end

--------------------------------------------------------------------------------

function GPhotoUser.updateUserStatusTextBindings( settings )
    if storedCredentialsAreValid(settings) then
        settings.accountStatus = LOC( "$$$/GPhoto/AccountStatus/LoggedIn=Logged in" )
    else
        settings.accountStatus = LOC( "$$$/GPhoto/SignIn=Sign in with your Google account." )
    end
end

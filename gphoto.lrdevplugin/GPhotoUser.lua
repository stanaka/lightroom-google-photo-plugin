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
		propertyTable.access_token ~= nil and propertyTable.refresh_token ~= nil)
    return propertyTable.access_token ~= nil and propertyTable.refresh_token ~= nil

end

--------------------------------------------------------------------------------

local function notLoggedIn( propertyTable )
	propertyTable.token = nil

	propertyTable.username = nil
	propertyTable.fullname = ''
    propertyTable.access_token = nil
    propertyTable.refresh_token = nil

	propertyTable.accountStatus = LOC "$$$/GPhoto/AccountStatus/NotLoggedIn=Not logged in"
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

		-- Clear any existing login info, but only if creating new account.
		-- If we're here on an existing connection, that's because the login
		-- token was rejected. We need to retain existing account info so we
		-- can cross-check it.

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

		-- Show request for authentication dialog.
        --[[
		local authRequestDialogResult = LrDialogs.confirm(
			LOC "$$$/GPhoto/AuthRequestDialog/Message=Lightroom needs your permission to upload images to GPhoto.",
			LOC "$$$/GPhoto/AuthRequestDialog/HelpText=If you click Authorize, you will be taken to a web page in your web browser where you can log in. When you're finished, return to Lightroom to complete the authorization.",
			LOC "$$$/GPhoto/AuthRequestDialog/AuthButtonText=Authorize",
			LOC "$$$/LrDialogs/Cancel=Cancel" )
		if authRequestDialogResult == 'cancel' then
			return
		end
        ]]--

		-- Request the frob that we need for authentication.
		propertyTable.accountStatus = LOC "$$$/GPhoto/AccountStatus/WaitingForGPhoto=Waiting for response from GPhoto.com..."

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

        logger:info("access_token before: ", auth.access_token)
        propertyTable.access_token = auth.access_token
        propertyTable.refresh_token = auth.refresh_token
        logger:info("access_token after: ", propertyTable.access_token)

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

                if propertyTable.LR_editingExistingPublishConnection then
					propertyTable.loginButtonTitle = LOC "$$$/GPhoto/LoginButton/LogInAgain=Log In"
					propertyTable.loginButtonEnabled = false
					propertyTable.validAccount = true
                else
					propertyTable.loginButtonTitle = LOC "$$$/GPhoto/LoginButton/LoggedIn=Switch Account?"
					propertyTable.loginButtonEnabled = true
					propertyTable.validAccount = true
                end
                propertyTable.changeAccountButtonTitle = LOC "$$$/GPhoto/LoginButton/LogInAgain=Change Account"
                propertyTable.changeAccountButtonEnabled = true
                propertyTable.revokeAccountButtonTitle = LOC "$$$/GPhoto/LoginButton/LogInAgain=Revoke Account"
                propertyTable.revokeAccountButtonEnabled = true
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
        settings.accountTypeMessage = LOC( "$$$/GPhoto/SignIn=Sign in with your Google account." )
    end
end

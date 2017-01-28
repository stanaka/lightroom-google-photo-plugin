local LrDialogs = import "LrDialogs"

require "GPhotoAPI"
local logger = import 'LrLogger'( 'GPhotoAPI' )
logger:enable('logfile')


return {
    URLHandler = function ( url )
        logger:info("URLCallback", url)
        if GPhotoAPI.URLCallback then
            GPhotoAPI.URLCallback( url:match( "code=([^&]+)" ) )
        end
    end
}

class SitesController < ApplicationController
    def create
        @site = Site.create(site_params)
        redirect_to @site
    end

    private

    def site_params
        params.require(:site).permit(:url)
    end
end

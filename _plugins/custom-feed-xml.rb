require "jekyll-feed"

Jekyll.logger.info "Monkey-patching jekyll-feed"

module JekyllFeed
  class Generator < Jekyll::Generator
    def feed_source_path
      @feed_source_path ||= @site.in_source_dir("_layouts", "feed.xml")
    end
  end
end

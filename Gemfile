source "https://rubygems.org"

# This site is built on this computer (or by Cloudflare) and served by Cloudflare,
# not by GitHub Pages. So instead of the big "github-pages" bundle, we list only
# the pieces the site uses, pinned to the versions it already built with.
#
# Why not "github-pages"? It locks jekyll-remote-theme to 0.4.3, which only allows
# rubyzip below 3.0, and rubyzip below 3.4.0 has a known security hole
# (GitHub alert #65). The layouts and styles live in this repo (_layouts,
# _includes, _sass), so the downloaded remote theme was never needed.
#
# After changing this file, run `bundle install`, then `./scripts/build`.

gem "jekyll", "3.10.0"

# Markdown: GitHub-style Markdown, the same reader GitHub Pages used.
gem "kramdown-parser-gfm", "1.1.0"
gem "jekyll-commonmark-ghpages", "0.5.1"

# Needed to run `jekyll serve` on Ruby 3+.
gem "webrick", "~> 1.9"

# Plugins. The first group is named in _config.yml; the second group is what
# GitHub Pages switched on behind the scenes, kept so the output stays identical.
group :jekyll_plugins do
  gem "jekyll-feed", "0.17.0"
  gem "jekyll-gist", "1.5.0"
  gem "jekyll-octicons", "11.2.0"
  gem "jekyll-github-metadata", "2.16.1"
  gem "jekyll-sitemap", "1.4.0"
  gem "jekyll-redirect-from", "0.16.0"
  gem "jekyll-seo-tag", "2.8.0"   # the {% seo %} tag in _includes/head.html

  gem "jekyll-coffeescript", "1.2.2"
  gem "jekyll-paginate", "1.1.0"
  gem "jekyll-relative-links", "0.6.1"
  gem "jekyll-optional-front-matter", "0.3.2"
  gem "jekyll-readme-index", "0.3.0"
  gem "jekyll-default-layout", "0.1.5"
  gem "jekyll-titles-from-headings", "0.5.3"
end

# Windows and JRuby do not include zoneinfo files, so bundle the tzinfo-data gem.
install_if -> { RUBY_PLATFORM =~ %r!mingw|mswin|java! } do
  gem "tzinfo", "~> 2.0", ">= 2.0.5"
  gem "tzinfo-data"
end

# Faster folder watching on Windows.
gem "wdm", "~> 0.1.1", :install_if => Gem.win_platform?

# Kept from before: minimum safe versions of these two.
gem "activesupport", "~> 7.2", ">= 7.2.3.1"
gem "faraday", "~> 1.10", ">= 1.10.6"

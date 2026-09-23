# Build restricted directory resources without changing their source files.
require 'cgi'
require 'base64'
require 'digest'
require 'kramdown'
require 'kramdown-parser-gfm'

module PrivateResources
  def self.front_matter(text)
    return [{}, text] unless text.start_with?("---\n")
    parts = text.split(/^---\s*$\n?/, 3)
    [YAML.safe_load(parts[1], permitted_classes: [Date, Time]) || {}, parts[2] || '']
  end

  def self.build(private_root, stage)
    files = %w[references presentations].flat_map { |dir| Dir[private_root.join(dir, '**/*').to_s].select { |p| File.file?(p) } }
    routes = {}
    files.each do |file|
      relative = Pathname.new(file).relative_path_from(private_root).to_s
      if File.extname(file).downcase == '.md'
        metadata, = front_matter(File.read(file))
        routes[relative] = metadata['permalink'] || '/' + relative.sub(/\.md$/, '.html')
      else
        routes[relative] = '/' + relative
      end
      abort "Resource URL must stay local: #{relative}" unless routes[relative].start_with?('/') && !routes[relative].start_with?('//') && !routes[relative].split('/').include?('..')
    end
    resources = []
    files.each do |file|
      relative = Pathname.new(file).relative_path_from(private_root).to_s
      target = File.join(stage, relative)
      FileUtils.mkdir_p(File.dirname(target))
      extension = File.extname(file).downcase
      title = File.basename(file)
      if extension == '.md'
        metadata, body = front_matter(File.read(file))
        title = metadata['title'] || body[/^#\s+(.+)$/, 1] || title
        # Resolve local Markdown links before rendering. Code samples remain literal.
        body = body.gsub(/\]\(([^\s)]+)\)/) do |match|
          href = Regexp.last_match(1)
          path, fragment = href.split('#', 2)
          resolved = Pathname.new(File.join(File.dirname(relative), path)).cleanpath.to_s
          routes.key?(resolved) ? "](#{routes[resolved]}#{fragment ? '#' + fragment : ''})" : match
        end
        html = Kramdown::Document.new(body, input: 'GFM', syntax_highlighter: 'rouge').to_html
        # User-authored templates inside reference documents are text, not build instructions.
        html = html.gsub('{', '&#123;').gsub('}', '&#125;')
        data = { 'layout' => 'page', 'title' => title, 'permalink' => routes[relative], 'noindex' => true, 'sitemap' => false }
        File.write(target.sub(/\.md$/, '.html'), data.to_yaml + "---\n" + html)
      elsif %w[.html .htm].include?(extension)
        text = File.read(file)
        title = text[/<title[^>]*>(.*?)<\/title>/im, 1] || title
        # Preserve image bytes; split embedded images out only in deployment output.
        text = text.gsub(%r{data:image/(png|jpeg|jpg|webp|gif);base64,([A-Za-z0-9+/=\r\n]+)}) do
          type = Regexp.last_match(1)
          bytes = Base64.strict_decode64(Regexp.last_match(2).delete("\r\n"))
          name = "#{Digest::SHA256.hexdigest(bytes)}.#{type}"
          asset = File.join(stage, 'assets', 'restricted-media', name)
          FileUtils.mkdir_p(File.dirname(asset))
          File.binwrite(asset, bytes) unless File.exist?(asset)
          "/assets/restricted-media/#{name}"
        end
        File.write(target, text)
      else
        FileUtils.cp(file, target)
      end
      resources << { 'title' => title, 'url' => routes[relative], 'group' => relative.split('/').first,
                     'download' => extension == '.md' ? '/downloads/' + relative : nil }
    end
    resources.group_by { |item| item['group'] }.each do |group, items|
      page = "<header class=\"browse-heading\"><h1>#{CGI.escapeHTML(group.capitalize)}</h1><p>Available to approved readers.</p></header>\n<ul class=\"restricted-resource-list\">"
      items.each do |item|
        page += "<li><a href=\"#{CGI.escapeHTML(item['url'])}\">#{CGI.escapeHTML(item['title'])}</a>"
        page += " · <a href=\"#{CGI.escapeHTML(item['download'])}\">Source</a>" if item['download']
        page += '</li>'
      end
      page += '</ul>'
      directory = File.join(stage, group)
      FileUtils.mkdir_p(directory)
      File.write(File.join(directory, 'index.html'), { 'layout' => 'default', 'title' => group.capitalize, 'noindex' => true }.to_yaml + "---\n" + page)
    end
    resources
  end
end

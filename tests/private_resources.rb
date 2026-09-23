require 'tmpdir'
require 'fileutils'
require 'pathname'
require 'yaml'
require 'date'
require_relative '../scripts/private_resources'
Dir.mktmpdir do |root|
  private_root = Pathname.new(File.join(root, 'private'))
  stage = File.join(root, 'stage')
  FileUtils.mkdir_p(private_root.join('references/nested'))
  FileUtils.mkdir_p(private_root.join('presentations'))
  FileUtils.mkdir_p(stage)
  body = "# Resource title\n\n[Another](nested/other.md)\n\n```yaml\n{% if dangerous %}{{ value }}{% endif %}\n```\n"
  File.write(private_root.join('references/test.md'), body)
  File.write(private_root.join('references/nested/other.md'), "---\ntitle: Another\npermalink: /references/another/\n---\n# Another\n")
  bytes = 'original-image-bytes'
  File.write(private_root.join('presentations/deck.html'), "<title>Test deck</title><img src=\"data:image/png;base64,#{Base64.strict_encode64(bytes)}\">")
  files = PrivateResources.build(private_root, stage)
  abort 'Resource count mismatch' unless files.size == 3
  rendered = File.read(File.join(stage, 'references/test.html'))
  abort 'Relative Markdown link not resolved' unless rendered.include?('href="/references/another/"')
  abort 'Liquid not preserved as literal content' if rendered.include?('{% if') || rendered.include?('{{ value }}')
  abort 'Original changed' unless File.read(private_root.join('references/test.md')) == body
  extracted = Dir[File.join(stage, 'assets/restricted-media/*')]
  abort 'Image bytes changed' unless extracted.size == 1 && File.binread(extracted.first) == bytes
  abort 'Embedded image not replaced' if File.read(File.join(stage, 'presentations/deck.html')).include?('base64,')
  %w[references presentations].each { |group| abort 'Missing private index' unless File.file?(File.join(stage, group, 'index.html')) }
end
puts 'Private resource tests passed: nested links, literal template examples, indexes, and exact image/source preservation.'

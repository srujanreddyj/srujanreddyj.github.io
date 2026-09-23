require 'tmpdir'
require 'fileutils'
require 'open3'
require 'yaml'
require 'date'
root = File.expand_path('..', __dir__)
Dir.mktmpdir do |stage|
  FileUtils.mkdir_p(File.join(stage, 'scripts'))
  FileUtils.mkdir_p(File.join(stage, '_data'))
  FileUtils.mkdir_p(File.join(stage, '_posts'))
  FileUtils.cp(File.join(root, 'scripts/validate_content'), File.join(stage, 'scripts/validate_content'))
  FileUtils.cp(File.join(root, '_data/topics.yml'), File.join(stage, '_data/topics.yml'))
  valid = { 'visibility' => 'public', 'published' => true, 'content_type' => 'article', 'topics' => ['data-platforms'], 'summary' => 'A test summary.' }
  [[:public, valid, true], [:draft, valid.merge('published' => false), true],
   [:restricted, valid.merge('visibility' => 'restricted'), false],
   [:missing_visibility, valid.reject { |k,_| k == 'visibility' }, false],
   [:unknown_topic, valid.merge('topics' => ['invented-topic']), false],
   [:missing_publication, valid.reject { |k,_| k == 'published' }, false]].each do |name, metadata, expected|
    File.write(File.join(stage, '_posts/2026-01-01-test.md'), metadata.to_yaml + "---\nSENTINEL\n")
    output, status = Open3.capture2e('ruby', File.join(stage, 'scripts/validate_content'))
    abort "#{name} failed: #{output}" unless status.success? == expected
  end
  File.write(File.join(stage, '_posts/2026-01-01-test.md'), valid.to_yaml + "---\nSENTINEL\n")
  %w[references presentations].each do |folder|
    FileUtils.mkdir_p(File.join(stage, folder))
    output, status = Open3.capture2e('ruby', File.join(stage, 'scripts/validate_content'))
    abort "Restricted folder accepted: #{folder}" if status.success? || !output.include?("#{folder}/ is restricted")
    FileUtils.rmdir(File.join(stage, folder))
  end
end
puts 'Content policy tests passed: public and draft accepted; restricted or invalid metadata rejected.'

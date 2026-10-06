require 'yaml'
require 'uri'
require 'date'
require 'json'

module Resources
  ROOT = File.expand_path('..', __dir__)
  COLLECTION = '3-Resources/Articles-Blogs/Engineering AI Agents and Career Resource Collection.md'
  STATUSES = %w[to-read reading read deprioritized].freeze
  PURPOSES = %w[learning reference interview-prep career leadership finance unspecified].freeze
  TYPES = %w[book guide repository directory article documentation unspecified].freeze
  TOPICS = ['ML engineering', 'LLMOps', 'training', 'inference', 'debugging', 'Python', 'PyTorch', 'developer tools', 'AI agents', 'use cases', 'automation', 'agent orchestration', 'software delivery', 'developer platform', 'multi-agent systems', 'tooling', 'interview prep', 'AI engineering', 'career', 'software engineering', 'systems design', 'career development', 'technical leadership', 'CTO', 'engineering management', 'options', 'investing', 'finance'].freeze

  def self.url(value)
    uri = URI.parse(value.to_s.strip)
    raise ArgumentError, 'URL must be an absolute HTTP(S) URL without credentials' unless %w[http https].include?(uri.scheme&.downcase) && uri.host && !uri.userinfo
    uri.scheme = uri.scheme.downcase
    uri.host = uri.host.downcase
    uri.path = '/' if uri.path.empty?
    # Preserve paths, fragments and queries: they can identify distinct documents.
    uri.to_s
  rescue URI::InvalidURIError => e
    raise ArgumentError, e.message
  end

  def self.validate(entries)
    raise ArgumentError, 'Resources must be a nonempty array' unless entries.is_a?(Array) && !entries.empty?
    seen = {}
    entries.each_with_index do |r, i|
      raise ArgumentError, "Entry #{i + 1} must be an object" unless r.is_a?(Hash)
      title = r['title']
      raise ArgumentError, "Entry #{i + 1}: missing title" unless title.is_a?(String) && !title.strip.empty?
      key = url(r['url'])
      raise ArgumentError, "Duplicate URL: #{key} (#{seen[key]} and #{title})" if seen[key]
      seen[key] = title
      raise ArgumentError, "#{title}: URL is not normalized" unless key == r['url']
      {'status' => STATUSES, 'purpose' => PURPOSES, 'type' => TYPES}.each do |field, allowed|
        raise ArgumentError, "#{title}: unsupported #{field}: #{r[field].inspect}" unless allowed.include?(r[field])
      end
      topics = r['topics']
      raise ArgumentError, "#{title}: missing topics" unless topics.is_a?(Array) && !topics.empty?
      raise ArgumentError, "#{title}: unknown or duplicate topics #{topics.inspect}" unless (topics - TOPICS).empty? && topics.uniq == topics
      %w[summary source_collection].each { |k| raise ArgumentError, "#{title}: missing #{k}" unless r[k].is_a?(String) }
      raise ArgumentError, "#{title}: missing added_at key" unless r.key?('added_at')
      if r['added_at']
        d = Date.iso8601(r['added_at'])
        raise ArgumentError, "#{title}: date must be YYYY-MM-DD" unless d.to_s == r['added_at']
      end
      raise ArgumentError, "#{title}: notes must be text" if r.key?('notes') && !r['notes'].is_a?(String)
    end
    entries
  end

  def self.parse(text, collection: COLLECTION)
    entries = []
    warnings = []
    section = ''
    current = nil
    text.each_line.with_index(1) do |line, number|
      if line.start_with?('## ')
        section = line.delete_prefix('## ').strip
        current = nil
      elsif (match = line.match(/^\s*- \*\*\[([^\]]+)\]\((https?:\/\/\S+)\)\*\*\s*(?:—|–|-)\s*(.*?)\s*$/))
        title, address, summary = match.captures
        topics = []
        current = {'title'=>title, 'url'=>url(address), 'summary'=>summary, 'status'=>nil, 'topics'=>topics, 'purpose'=>'unspecified', 'type'=>'unspecified', 'source_collection'=>collection, 'added_at'=>nil}
        if summary.include?('[[')
          current['notes'] = summary
          current['summary'] = ''
        end
        current['purpose'] = case section
        when 'AI Engineering and Developer Practice', 'Multi-Agent Orchestration' then 'learning'
        when 'Career and Technical Leadership' then 'career'
        when 'Finance' then 'finance'
        else 'unspecified'
        end
        current['type'] = if title.match?(/Open Book/i) then 'book'
        elsif summary.match?(/\b(directory|list of)\b/i) then 'directory'
        elsif title.match?(/\bGuide\b/) then 'guide'
        elsif URI.parse(address).path.start_with?('/docs/') then 'documentation'
        elsif URI.parse(address).host == 'github.com' then 'repository'
        else 'unspecified'
        end
        entries << current
      elsif line.match?(/^\s*- .*(?:\]\(|https?:\/\/)/)
        raise ArgumentError, "Line #{number}: malformed resource; expected - **[Title](URL)** — Summary"
      elsif current && !line.strip.empty?
        line.strip.split(/\s*·\s*/).each do |part|
          match = part.match(/\A(Status|Topics|Purpose|Type|Added|Notes):\s*(.*)\z/)
          raise ArgumentError, "Line #{number}: unrecognized metadata #{part.inspect}" unless match
          label, value = match.captures
          key = {'Status'=>'status','Topics'=>'topics','Purpose'=>'purpose','Type'=>'type','Added'=>'added_at','Notes'=>'notes'}.fetch(label)
          current['_explicit_purpose'] = true if key == 'purpose'
          current[key] = key == 'topics' ? value.split(',').map { |v| v.strip.delete('`') } : (key == 'notes' ? value.strip : value.delete('`').strip)
        end
      end
    end
    entries.each do |r|
      explicit_purpose = r.delete('_explicit_purpose')
      r['purpose'] = 'interview-prep' if !explicit_purpose && r['purpose'] == 'career' && r['topics'].include?('interview prep')
      r['purpose'] = 'leadership' if !explicit_purpose && r['purpose'] == 'career' && r['topics'].include?('technical leadership')
      missing = %w[summary purpose type added_at].select { |k| r[k].nil? || r[k] == '' || r[k] == 'unspecified' }
      warnings << "#{r['title']}: review #{missing.join(', ')}" unless missing.empty?
    end
    [validate(entries), warnings]
  end
end

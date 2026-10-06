require 'minitest/autorun'
require_relative '../scripts/resources'

class ResourcesTest < Minitest::Test
  def source(extra = '')
    "## AI Engineering and Developer Practice\n- **[Sample Guide](https://EXAMPLE.com)** — A useful guide.\n  Status: `to-read` · Topics: `AI agents`, `automation`\n#{extra}"
  end
  def test_normalization_and_idempotence
    a, warnings = Resources.parse(source)
    b, = Resources.parse(source)
    assert_equal JSON.generate(a), JSON.generate(b)
    assert_equal 'https://example.com/', a.first['url']
    assert_nil a.first['added_at']
    assert warnings.any? { |w| w.include?('added_at') }
    assert_equal 2, a.first['topics'].size
  end
  def test_explicit_purpose_wins_over_inference
    entries, = Resources.parse(File.read(File.join(__dir__, 'fixtures/resources.md')))
    assert_equal 'career', entries.first['purpose']
  end
  def test_duplicate_normalized_urls_fail
    assert_raises(ArgumentError) { Resources.parse(source + source) }
  end
  def test_invalid_metadata_and_malformed_entries
    ['Status: `done` · Topics: `AI agents`', 'Status: `read` · Topics:', 'Status: `read` · Topics: `unknown`'].each do |meta|
      assert_raises(ArgumentError) { Resources.parse(source.sub(/Status:.*$/, meta)) }
    end
    assert_raises(ArgumentError) { Resources.parse('- [Missing syntax](https://example.com)') }
    assert_raises(ArgumentError) { Resources.parse(source + "\n- **[Unsafe](javascript:alert(1))** — Bad") }
    assert_raises(ArgumentError) { Resources.parse(source.sub('[Sample Guide]', '[]')) }
  end
  def test_explicit_metadata_and_notes
    entries, = Resources.parse(source("  Purpose: `reference` · Type: `documentation` · Added: `2026-10-06`\n  Notes: Keep for later.\n"))
    assert_equal 'reference', entries.first['purpose']
    assert_equal '2026-10-06', entries.first['added_at']
    assert_equal 'Keep for later.', entries.first['notes']
  end
  def test_private_wikilinks_are_preserved_without_fabricating_summary
    entries, warnings = Resources.parse(source.sub('A useful guide.', 'Also listed in [[Other note]].'))
    assert_equal '', entries.first['summary']
    assert_equal 'Also listed in [[Other note]].', entries.first['notes']
    assert warnings.first.include?('summary')
  end
  def test_dangerous_urls_and_dates_rejected
    entry = Resources.parse(source).first.first
    entry['url'] = 'javascript:alert(1)'
    assert_raises(ArgumentError) { Resources.validate([entry]) }
    entry['url'] = 'https://example.com/'
    entry['added_at'] = '2026-02-30'
    assert_raises(ArgumentError) { Resources.validate([entry]) }
  end
end

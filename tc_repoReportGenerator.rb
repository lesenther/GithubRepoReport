require_relative 'repoReportGenerator'
require 'minitest/autorun'

class TestRepoReportGenerator < MiniTest::Test

  def setup
    @repoGen = RepoReportGenerator.new()
    # 'apple', 'swift', 'https://hooks.slack.com/services/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'
  end

  def test_query
    assert_raises(MissingUser){ @repoGen.query }
    @repoGen.setUser('apple')
    assert_raises(MissingRepo){ @repoGen.query }
    @repoGen.setRepo('swift')
    assert_raises(MissingRepo){ @repoGen.query }
    @repoGen.setWebhook('https://hooks.slack.com/services/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')
    assert_equal true, @repoGen.query
  end

end
#-------------------------------------------------------------------------------
# Required Libraries
#-------------------------------------------------------------------------------
require "net/https"
require "openssl"
require "uri"
require "json"
require "date"

#-------------------------------------------------------------------------------
# RepoReportGenerator Class
#-------------------------------------------------------------------------------
class RepoReportGenerator

  def initialize(user, repo, webhook)
    setUser(user)
    setRepo(repo)
    setWebhook(webhook)
  end

  def setUser(user)
    raise unless user.is_a?(String)
    @ghUser = user
  end

  def setRepo(repo)
    raise unless repo.is_a?(String)
    @ghRepo = repo
  end

  def setWebhook(webhook)
    raise unless webhook.is_a?(String)
    @slackWebhook = webhook
  end

  #-----------------------------------------------------------------------------
  # Call the github api for the specific user and repo
  #-----------------------------------------------------------------------------
  def queryGithub(endpoint, queryParams = {})
    if @ghUser.nil? || @ghRepo.nil?
      raise "Error querying Github: Missing user/repo"
    end

    # had to add token after getting cut off by github - should not be necessary for tests
    queryParams['access_token'] = '945d48f2d9285aa94caef99686470aaf3fd618be'

    uri = URI.parse('https://api.github.com/repos/'+@ghUser+'/'+@ghRepo+'/'+
      endpoint)
    uri.query = URI.encode_www_form(queryParams)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    request = Net::HTTP::Get.new(uri.request_uri)
    response = http.request(request)

    if response.kind_of? Net::HTTPSuccess
      return JSON.parse(response.body)
    elsif response.message
      raise response.message
    else
      raise 'Error querying Github: An unknown error occurred'
    end
  end

  #-----------------------------------------------------------------------------
  # Send a message to a user on slack
  #
  # See:  https://api.slack.com/incoming-webhooks
  #-----------------------------------------------------------------------------
  def postToSlack(message)
    if message.nil?
      raise "Error posting to Slack: Message cannot be blank"
      return false
    elsif @slackWebhook.empty?
      raise "Error posting to Slack: Missing webhook url"
      return false
    end

    uri = URI.parse(@slackWebhook)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    request = Net::HTTP::Post.new(uri.request_uri, {'Content-Type' =>'application/json'})
    request.body = { text: message, username: 'SushBot', mrkdwn: true }.to_json
    response = http.request(request)

    return response.body
  end

  #-----------------------------------------------------------------------------
  # Generate statistics for a repository on github and post to slack
  #-----------------------------------------------------------------------------
  def generateReport
    if @ghUser.empty? || @ghRepo.empty?
      raise "Cannot generate a report: Missing user/repo"
    end

    output = "# Report for the repository "+@ghUser+'/'+@ghRepo+"\n"

    #---------------------------------------------------------------------------
    # Get open/closed pull requests in the last 30 days
    #---------------------------------------------------------------------------
    # See: https://developer.github.com/v3/pulls/#list-pull-requests
    #
    # Endpoint: GET /repos/:owner/:repo/pulls
    #
    # Useful parameters:
    #  - state : all | open (default) | closed
    #  - sort : long-running (filtering by pulls updated in the last month)
    #---------------------------------------------------------------------------
    pullRequests = queryGithub('pulls', {
      'state' => 'all',
      'sort'  => 'long-running'
    })

    if pullRequests.class == Hash
      && pullRequests.has_key?('message')
      && pullRequests['message'] === 'Not Found'
      raise 'Error generating report: User/repo was not found'
    end

    output += "\n\nPull Requests Summary:\n"+
      (pullRequests.length == 0 ? '   No pull requests' : '')

    pullRequests.each do |pullRequest|
      output += ' - '+pullRequest['title']+' ('+pullRequest['state']+') on '+
        pullRequest['created_at']+"\n"
    end

    #---------------------------------------------------------------------------
    # Get open/closed issues in the last 30 days
    #---------------------------------------------------------------------------
    # See:  https://developer.github.com/v3/issues/#list-issues
    #
    # Endpoint:  GET /repos/:owner/:repo/issues
    #
    # Useful parameters:
    #  - state : all | open (default) | closed
    #  - since : timestamp ISO 8601 (YYYY-MM-DDTHH:MM:SSZ)
    #---------------------------------------------------------------------------
    issues = queryGithub('issues', {
      'state' => 'all',
      'since' => (Date.today - 30).iso8601
    })

    output += "\n\nIssues Summary:\n"
    hasIssues = false

    issues.each do |issue|
      output += issue.key?('pull_request') ? '' # exclude pull requests
        : ' - '+issue['title']+' ('+issue['state']+') on '+ issue['created_at']+"\n"
      hasIssues = hasIssues ? true : (issue.key?('pull_request') ? false : true)
    end

    output += hasIssues ? '' : '   No issues'

    #---------------------------------------------------------------------------
    # Get list of committers ordered by number of commits in the last 30 days
    #---------------------------------------------------------------------------
    # See:  https://developer.github.com/v3/repos/commits/
    #
    # Endpoint:  GET /repos/:owner/:repo/commits
    #
    # Useful parameters:
    #  - since : timestamp ISO 8601 (YYYY-MM-DDTHH:MM:SSZ)
    #---------------------------------------------------------------------------
    committers = queryGithub('commits', {'since' => (Date.today - 30).iso8601})

    output += "\n\nCommitters Summary:\n"+
      (committers.length == 0 ? '   No committers' : '')

    committers_hash = Hash.new(0)
    total_commits = 0

    committers.each do |committer|
      committers_hash[committer['commit']['author']['name']] += 1
    end

    sorted_committers = committers_hash.sort_by { |user, count| count }.reverse.to_h

    sorted_committers.each do |committer, commit_count|
      output += ' - '+committer+' ('+commit_count.to_s+
        ' commit'+(commit_count>1?'s':'')+')'+"\n"
      total_commits += commit_count
    end

    #---------------------------------------------------------------------------
    # Get total number of commits in the last 30 days
    #---------------------------------------------------------------------------
    # See:  https://developer.github.com/v3/repos/statistics/#contributors
    #
    # Endpoint:   GET /repos/:owner/:repo/stats/contributors
    #
    # Note: We should be able to get the total number of commits as we iterate
    # through the list of committers instead of doing a separate API call
    #
    #---------------------------------------------------------------------------
    output += "\n\nTotal Commits:  "+total_commits.to_s+"\n"

    #---------------------------------------------------------------------------
    # Send report to user via Slack
    #---------------------------------------------------------------------------
    postToSlack(output)
  end

end

a = RepoReportGenerator.new('apple', 'swift', 'https://hooks.slack.com/services/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')

a.generateReport

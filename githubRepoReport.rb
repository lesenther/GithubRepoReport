#-------------------------------------------------------------------------------
# Required Libraries
#-------------------------------------------------------------------------------
require "net/https"
require "openssl"
require "uri"
require "json"
require "date"

#-------------------------------------------------------------------------------
# Config
#-------------------------------------------------------------------------------
@ghUser = 'apple' # Username / owner of the repo
@ghRepo = 'swift'  # Repository name
@slackWebHook = 'https://hooks.slack.com/services/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' # See:  https://api.slack.com/incoming-webhooks

#-------------------------------------------------------------------------------
# Call the github api for the specific user and repo
#-------------------------------------------------------------------------------
def queryGithub(endpoint, queryString = false)
  if @ghUser.empty? || @ghRepo.empty?
    puts "Error querying Github: Missing user/repo"
    return false
  end

  queryString = (queryString === false) ? '' : queryString+'&'
  # queryString += 'access_token=e273c11feda9abf8c8688761caba7d3635d76220' # had to add token after getting cut off by github - should not be necessary for tests
  # {"message"=>"API rate limit exceeded for 50.141.xx.xx. (But here's the good news: Authenticated requests get a higher rate limit. Check out the documentation for more details.)", "documentation_url"=>"https://developer.github.com/v3/#rate-limiting"}
  uri = URI.parse('https://api.github.com/repos/'+@ghUser+'/'+@ghRepo+'/'+
    endpoint+'?'+queryString)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  request = Net::HTTP::Get.new(uri.request_uri)
  response = http.request(request)

  return JSON.parse(response.body)
end

#-------------------------------------------------------------------------------
# Send a message to a user on slack
#
# See:  https://api.slack.com/incoming-webhooks
#-------------------------------------------------------------------------------
def postToSlack(message)
  if message.empty?
    puts "Error posting to Slack: Message cannot be blank"
    return false
  elsif @slackWebHook.empty?
    puts "Error posting to Slack: Missing webhook url"
    return false
  end

  uri = URI.parse(@slackWebHook)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  request = Net::HTTP::Post.new(uri.request_uri, {'Content-Type' =>'application/json'})
  request.body = { text: message, username: 'SushBot', mrkdwn: true }.to_json
  response = http.request(request)

  return response.body
end

#-------------------------------------------------------------------------------
# Generate statistics for a repository on github and post to slack
#-------------------------------------------------------------------------------
def generateReport
  if @ghUser.empty? || @ghRepo.empty?
    puts "Cannot generate a report: Missing user/repo"
    return false
  end

  output = '*Report for the repository '+@ghUser+'/'+@ghRepo+'*'

  #-----------------------------------------------------------------------------
  # Get open/closed pull requests in the last 30 days
  #-----------------------------------------------------------------------------
  # See: https://developer.github.com/v3/pulls/#list-pull-requests
  #
  # Endpoint: GET /repos/:owner/:repo/pulls
  #
  # Useful parameters:
  #  - state : all | open (default) | closed
  #  - sort : long-running (filtering by pulls updated in the last month)
  #-----------------------------------------------------------------------------
  pullRequests = queryGithub('pulls', 'state=all&sort=long-running')

  if pullRequests.class == Hash && pullRequests.has_key?('message') && pullRequests['message'] === 'Not Found'
    puts 'Error generating report: User/repo was not found'
    return false
  end

  output += "\n\nPull Requests Summary:\n"+
    (pullRequests.length == 0 ? '   No pull requests' : '')

  pullRequests.each do |pullRequest|
    output += ' - '+pullRequest['title']+' ('+pullRequest['state']+') on '+
      pullRequest['created_at']+"\n"
  end

  #-----------------------------------------------------------------------------
  # Get open/closed issues in the last 30 days
  #-----------------------------------------------------------------------------
  # See:  https://developer.github.com/v3/issues/#list-issues
  #
  # Endpoint:  GET /repos/:owner/:repo/issues
  #
  # Useful parameters:
  #  - state : all | open (default) | closed
  #  - since : timestamp ISO 8601 (YYYY-MM-DDTHH:MM:SSZ)
  #-----------------------------------------------------------------------------
  issues = queryGithub('issues', 'state=all&since='+(Date.today - 30).iso8601)

  output += "\n\nIssues Summary:\n"
  hasIssues = false

  issues.each do |issue|
    output += issue.key?('pull_request') ? '' # exclude pull requests
      : ' - '+issue['title']+' ('+issue['state']+') on '+ issue['created_at']+"\n"
    hasIssues = hasIssues ? true : (issue.key?('pull_request') ? false : true)
  end

  output += hasIssues ? '' : '   No issues'

  #-----------------------------------------------------------------------------
  # Get list of committers ordered by number of commits in the last 30 days
  #-----------------------------------------------------------------------------
  # See:  https://developer.github.com/v3/repos/commits/
  #
  # Endpoint:  GET /repos/:owner/:repo/commits
  #
  # Useful parameters:
  #  - since : timestamp ISO 8601 (YYYY-MM-DDTHH:MM:SSZ)
  #-----------------------------------------------------------------------------
  committers = queryGithub('commits', 'since='+(Date.today - 30).iso8601)

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

  #-----------------------------------------------------------------------------
  # Get total number of commits in the last 30 days
  #-----------------------------------------------------------------------------
  # See:  https://developer.github.com/v3/repos/statistics/#contributors
  #
  # Endpoint:   GET /repos/:owner/:repo/stats/contributors
  #
  # Note: We should be able to get the total number of commits as we iterate
  # through the list of committers instead of doing a separate API call
  #
  #-----------------------------------------------------------------------------
  output += "\n\nTotal Commits:  "+total_commits.to_s+"\n"

  #-----------------------------------------------------------------------------
  # Send report to user via Slack
  #-----------------------------------------------------------------------------
  postToSlack(output)
end

#-------------------------------------------------------------------------------
# Automatically generate a report
#-------------------------------------------------------------------------------
generateReport

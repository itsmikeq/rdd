%w(ostruct optparse optparse/date optparse/time gcloud date time).each do |_req|
  begin
    require _req
  rescue LoadError => e
    puts "Yo - you need to install #{_req} 'gem install #{_req}'"
    raise e
  end
end


# Extend string so i dont have to retype this_method -> ThisMethod
class String
  def camelize
    split('_').map { |w| w.capitalize }.join
  end
end

# Connect to google and run some queries
class Query
  attr_accessor :gcloud, :bigquery

  def initialize
    @gcloud = Gcloud.new "github-memikequinn-parsing"
    @bigquery = @gcloud.bigquery
  end

  def execute(query)
    job = bigquery.query_job query, cache: true
    job.wait_until_done!


    if job.failed?
      raise job.error['message']
    else
      job
    end
  end
end


# This class may seem dumb - and it would be but it allows me to visually compare two differing datasets that
# need to be visualized as one.
# For example, I'm able to look at both the older and newer data sets to see that they both have the same constraints
# without having to flip back and forth through a class
class Points
  # Event types, really just used for visualization
  def all_event_types
    {"type": "MemberEvent"}
    {"type": "WatchEvent"}
    {"type": "ReleaseEvent"}
    {"type": "PullRequestEvent"}
    {"type": "IssuesEvent"}
    {"type": "CreateEvent"}
    {"type": "GistEvent"}
    {"type": "PushEvent"}
    {"type": "GollumEvent"}
    {"type": "PullRequestReviewCommentEvent"}
    {"type": "DeleteEvent"}
    {"type": "CommitCommentEvent"}
    {"type": "ForkEvent"}
    {"type": "IssueCommentEvent"}
    {"type": "PublicEvent"}
  end

  def query_types
    (Points.new.public_methods - [:points, :types])- Object.methods
  end

  private :query_types, :all_event_types

  def create_event
    ::OpenStruct.new({points: 10,
                      type: __method__.to_s.camelize,
                      older: "payload_ref is null",
                      newer: "JSON_EXTRACT(payload, '$.ref') = 'null'"
                     })
  end

  def fork_event
    ::OpenStruct.new({points: 5,
                      type: __method__.to_s.camelize,
                      older: "repository_fork = 'true'",
                      newer: "JSON_EXTRACT(payload, '$.forkee.fork') = 'true'"
                     })
  end

  def member_event
    ::OpenStruct.new({points: 3,
                      type: __method__.to_s.camelize,
                      older: "payload_action = 'added'",
                      newer: "JSON_EXTRACT(payload, '$.action') = 'added'"
                     })
  end

  def pull_request_event
    ::OpenStruct.new({points: 2,
                      type: "PullRequestEvent",
                      older: "payload_pull_request_merged = 'true' and payload_pull_request_state = 'closed'",
                      newer: "JSON_EXTRACT(payload, '$.pull_request.merged') = 'true' and JSON_EXTRACT(payload, '$.action') = 'true'"
                     })
  end

  def watch_event
    ::OpenStruct.new({points: 1,
                      type: __method__.to_s.camelize,
                      older: "payload_action = 'started'",
                      newer: "JSON_EXTRACT(payload, '$.action') = 'started'"
                     })
  end

  def issues_event
    ::OpenStruct.new({points: 1,
                      type: __method__.to_s.camelize,
                      older: "payload_action = 'opened'",
                      newer: "JSON_EXTRACT(payload, '$.action') = 'opened'"
                     })
  end

  def types
    query_types.collect { |e| send(e).send(:type) }.uniq
  end

  # get some ratings
  def points
    query_types.collect { |e| {e => send(e).send(:points)} }.inject(:merge)
  end
end

# Timeline records:
# 2007-10-29 14:37:16	2015-01-01 18:05:48
# Purpose is to assign points to projects
class QueryBuilder
  attr_accessor :pointer, :before, :after, :top

  def initialize(before, after, top = 20)
    @pointer = Points.new
    @before = before
    @after = after
    @top = top
  end

  # used to query data after the timeline api expired
  def after_timeline
    @base_query = <<END
SELECT
  /* create event */
  SUM(
  case
    when (type = '#{pointer.create_event.type}' and #{pointer.create_event.newer})
    then #{pointer.create_event.points}
    /* Forked */
    when (type = '#{pointer.fork_event.type}' and #{pointer.fork_event.newer})
      then #{pointer.fork_event.points}
    /* Member added */
    when (type = '#{pointer.member_event.type}' and #{pointer.member_event.newer})
      then #{pointer.member_event.points}
    when (type = '#{pointer.pull_request_event.type}' and #{pointer.pull_request_event.newer})
      then #{pointer.pull_request_event.points}
    WHEN (type = '#{pointer.watch_event.type}' and #{pointer.watch_event.newer})
      THEN #{pointer.watch_event.points}
    WHEN (type = '#{pointer.issues_event.type}' and #{pointer.issues_event.newer})
      THEN #{pointer.issues_event.points}
  end ) as points,
  repo.name as repo_name
  FROM ( TABLE_DATE_RANGE([githubarchive:day.events_],
  TIMESTAMP('#{after.to_time.strftime('%Y-%m-%d')}'), TIMESTAMP('#{before.to_time.strftime('%Y-%m-%d')}') ))
  WHERE
  type in ('#{pointer.types.join("','")}')
  and repo.name is not null
  group by repo_name
  order by points desc
  limit #{top}


END
  end

  # used when the before is < 2015-01-01
  # after = (Time.now - (2.419e+6*14))
  # before = Time.parse('2014-10-29 23:45:12 -0700')
  def timeline
    @timeline_query = <<END
    SELECT
    SUM(
    CASE
    WHEN (type = '#{pointer.create_event.type}' and #{pointer.create_event.older})
      THEN #{pointer.fork_event.points}
    WHEN (type = '#{pointer.fork_event.type}' and #{pointer.fork_event.older})
      THEN #{pointer.fork_event.points}
    WHEN (type = '#{pointer.member_event.type}' and #{pointer.member_event.older})
      THEN #{pointer.member_event.points}
    WHEN (type = '#{pointer.pull_request_event.type}' and #{pointer.pull_request_event.older})
      THEN #{pointer.pull_request_event.points}
    WHEN (type = '#{pointer.watch_event.type}' and #{pointer.watch_event.older})
      THEN #{pointer.watch_event.points}
    WHEN (type = '#{pointer.issues_event.type}' and #{pointer.issues_event.older})
      THEN #{pointer.issues_event.points}
    END) as points,
    repository_url
      FROM ([githubarchive:github.timeline])
       where created_at >= '#{after.to_time}'
        and created_at <= '#{before.to_time}'
        AND type in ('#{pointer.types.join("','")}')
        AND repository_url is not null
        /* Clear out some junk so its not counted on my bill */
      GROUP BY repository_url
    ORDER BY points desc
    limit #{top}
END

  end
end

class GnuPlot
  attr_accessor :results

  def initialize(results)
    @results = results
  end

  def formatter
    @file ||= begin
      out = "'Repo Name', 'Score', 'Points'"
      results.each_with_index { |r, i| out << "#{r['repo_name']||r['repository_url'].split('/').last(2).join('/')},#{r['points']},#{i}\n" }
      out
    end
  end

  def execute
    `mkdir -p plot/img`
    gnuplot = <<END
#!/usr/bin/env gnuplot
reset
set terminal png font ",8"
set output 'plot/img/github.png'
set style data histograms
set xlabel "Repos"
set ylabel "Popularity"
set title "Github popular repos"
set boxwidth 0.5
set style fill solid 1.0 border -1
set yrange [:]
set datafile separator ","
set xtics rotate by -45
set bmargin 10
set rmargin 10
set key left
set grid y
plot 'plot/data.dat' using 2:xticlabels(1) notitle

END
    File.write('plot/data.dat', formatter)
    File.write('plot/gnu.plot', gnuplot)
    r = `gnuplot ./plot/gnu.plot`
    `open ./plot/img/github.png`
    File.delete('./plot/gnu.plot')
    File.delete('./plot/data.dat')
    r.empty?
  end
end


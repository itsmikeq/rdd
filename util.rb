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

# Timeline records:
# 2007-10-29 14:37:16	2015-01-01 18:05:48
# Purpose is to assign points to projects
class QueryBuilder
  attr_accessor :before, :after, :top, :base_query

  def initialize(before, after, top = 20)
    @before = before
    @after = after
    @top = top
    @base_query = if before.to_time.to_i > Time.parse("2015-01-01").to_time.to_i
                    after_timeline_base_table
                  else
                    timeline_base_table
                  end
  end

  def wheres_and_whens
    @wheres_and_whens ||= <<END
    WHERE
    type in ('CreateEvent',
        'ForkEvent',
        'MemberEvent',
        'PullRequestEvent',
        'WatchEvent',
        'IssuesEvent')
    and created_at >= '#{after.to_datetime.to_s}'
    and created_at <= '#{before.to_datetime.to_s}'
END
  end

  def after_timeline_base_table
    @after_timeline_base_table ||= <<END
SELECT
  type,
  REPLACE(repo.url, 'https://api.github.com/repos/', 'https://github.com/') as repository_url,
  JSON_EXTRACT(payload, '$.action') as payload_action,
  JSON_EXTRACT(payload, '$.pull_request.merged') as payload_pull_request_merged,
  JSON_EXTRACT(payload, '$.pull_request.state') as payload_pull_request_state,
  JSON_EXTRACT(payload, '$.ref') as payload_ref
FROM ( TABLE_DATE_RANGE([githubarchive:day.events_],
  TIMESTAMP('#{after.to_time.strftime('%Y-%m-%d')}'), TIMESTAMP('#{before.to_time.strftime('%Y-%m-%d')}')
))
#{wheres_and_whens} AND repo.url IS NOT NULL
END
  end

  def timeline_base_table
    tables = [after, before].collect { |d| "[githubarchive:year.#{d.strftime('%Y')}]" }.uniq.join(',')
    @timeline_base_table ||= <<END
  SELECT
    type,
    payload_ref,
    payload_pull_request_merged,
    payload_pull_request_state,
    payload_action,
    repository_url
  FROM (#{tables})
    #{wheres_and_whens}
    AND repository_url IS NOT NULL
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
    WHEN (type = 'CreateEvent' and payload_ref is null)
      THEN 10
    WHEN (type = 'ForkEvent')
      THEN 5
    WHEN (type = 'MemberEvent')
      THEN 3
    WHEN (type = 'PullRequestEvent'and payload_pull_request_merged = 'true' and payload_pull_request_state = 'closed')
      THEN 2
    WHEN (type = 'WatchEvent')
      THEN 1
    WHEN (type = 'IssuesEvent' and payload_action = 'opened')
      THEN 1
    ELSE
      0
    END
  ) as points,
REPLACE(repository_url, 'https://github.com/', '') repo_name
FROM (
  #{base_query}
)
GROUP BY
  type,
  payload_action,
  payload_pull_request_merged,
  payload_pull_request_state,
  repository_url,
  payload_ref,
  repo_name
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
      results.each_with_index { |r, i| out << "#{r['repo_name']},#{r['points']},#{i}\n" }
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


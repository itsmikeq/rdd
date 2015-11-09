# Go through and require each of the require gems/libraries
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
    @gcloud = Gcloud.new
    @bigquery = @gcloud.bigquery
  end

  def execute(query)
    job = bigquery.query_job query, cache: true
    begin
      job.wait_until_done!
    rescue => e
      if e.message.match(/Access Denied: Job/)
        puts "You need to log in first"
        puts "Please run gcloud auth --account <your gmail account> --project #{ENV['GCLOUD_PROJECT']} and try again"
        exit 1
      end
    end


    if job.failed?
      raise job.error['message']
    else
      job
    end
  end
end

# Timeline records:
# 2007-10-29 14:37:16	2015-01-01 18:05:48
# Builds queries used by the commandline rdd.rb.
# .execute runs the sql
class Querier
  attr_accessor :before, :after, :top, :base_query

  def initialize(before, after, top = 20)
    @before = before
    @after = after
    @top = top
    @base_query = if before.strftime('%Y').to_i >= 2015 && after.strftime('%Y').to_i >= 2015
                    after_timeline_base_table
                  elsif before.strftime('%Y').to_i < 2015 && after.strftime('%Y').to_i < 2015
                    timeline_base_table
                  end
  end

  def execute
    if base_query
      done_job = Query.new.execute(timeline)
      # Note if the query was cached because these are free queries
      {results: done_job.query_results, cached: done_job.cache_hit?, bytes: done_job.bytes_processed}
    else
      puts "No base table"
      a = begin
        @base_query = after_timeline_base_table
        Query.new.execute(timeline)
      end
      b = begin
        @base_query = timeline_base_table
        Query.new.execute(timeline)
      end
      results = a.query_results
      results += b.query_results
      results.flatten!
      cached = !!(a.cache_hit? && b.cache_hit?)
      h = {}
      # deduplicate array of hashes keys
      results.each do |e|
        if h.has_key?(e['repo_name'])
          h.merge!(e['repo_name'] => (e['points'] + h[e['repo_name']]))
        else
          h.merge!(e['repo_name'] => e['points'])
        end
      end
      # Back into an array of hashes
      results = h.collect do |k, v|
        {'repo_name' => k, 'points' => v}
      end
      # Sort by points, ascending
      results.sort_by! { |e| e['points'] }.reverse!
      {results: results.first(top), cached: cached, bytes: (a.bytes_processed.to_i + b.bytes_processed.to_i)}
    end

  end

  # Set shared where/when clauses
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

  # for queries > Dec 31, 2014
  # Base table is set so that we can use the same detail queries later
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

  # for queries < Jan 1, 2015
  # Base table is set so that we can use the same detail queries later
  def timeline_base_table
    tables = [after, before].collect { |d| next unless d.strftime('%Y').to_i < 2015; "[githubarchive:year.#{d.strftime('%Y')}]" }.compact.uniq.join(',')
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


  # Since all queries look the same as the < 2015 table (timeline)
  # We can use the same master query to resolve data
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

# Creates a gnuplot output of requested data
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


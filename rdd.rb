#!/usr/bin/env ruby
# Load up my helper
load File.join(File.dirname(__FILE__), 'util.rb')
# Require google cloud environment file or 
ENV['GCLOUD_KEYFILE'] ||= File.join(File.dirname(__FILE__), Dir.glob('*@*.json').first) rescue nil
# Sign in with the SDK via gcloud auth
if !ENV['GCLOUD_PROJECT'] || ENV['GCLOUD_PROJECT'].empty?
  puts "Please set your google cloud project name with 'export GCLOUD_PROJECT=my-project-name'"
  exit 1
end

# This is the main parsing class 
# Options are 
# -a| --after : defines a time after which github will be queried
# -b| --before : defines a time before which github will be queried, defaults to today (rounded to day)
# -g| --gnuplot : plots popularity over time
# -w| --answer : Answer questions in the original RDD
class ElParso
  def self.parse(args)
    options = ::OpenStruct.new
    # use a rounded time, so we can cache the result
    options.after = DateTime.parse((Time.now - (60*60*24*20)).to_datetime.strftime('%Y-%m-%d'))
    options.before = DateTime.parse(DateTime.now.strftime('%Y-%m-%d'))
    options.top = 20

    opt_parser = OptionParser.new do |opts|
      opts.banner = "Usage: rrd.rb [options]"

      opts.on("-a", "--after [Date]", DateTime, "Date to start search at, ISO8601 or YYYY-MM-DD format.",
              "Default: 28 days ago") do |after|
        options.after = after if after
      end

      opts.on("-b", "--before [Date]", DateTime, "ISO8601 Date to end search at, ISO8601 or YYYY-MM-DD format.",
              "Default: Now") do |before|
        options.before = before if before
      end

      opts.on("-t", "--top TOP", Integer, "The number of repos to show.",
              "Default: 20") do |top|
        options.top = top if top
      end

      opts.on("-g", "--gnuplot", "Plot this",
              "Plot the numbers with gnuplot") do |gnu|
        options.gnuplot = gnu
        `which gnuplot > /dev/null 2>&1`
        if $?.exitstatus != 0 && gnu
          puts 'you cannot use GNUPlot, its not installed'
          options.gnuplot = false
        end
      end

      opts.on("-w", "--answer", "Answers the questions",
              "Default: 20") do
        printf("%80s", File.read(File.join(File.dirname(__FILE__), 'answers.txt')))
        exit 0
      end
    end
    opt_parser.parse!(args)
    options
  end
end
# Parse options
options = ElParso.parse(ARGV)
# We want to keep the timeline straight
if options.before < options.after
  raise "#{options.before.to_s} should be after #{options.after.to_s} -- Check --before/-b and --after/-a options"
end
# Since the API changed between 2014 and 2015, only allow before/after both before or both after 2014
if options.before.year <= 2014 && options.after >= 2015
  puts "Cannot span 2014 -> 2015 in request query"
  exit 1
end

sql = QueryBuilder.new(options.before, options.after, options.top).timeline
puts "Getting Github statistics for #{options.after} - #{options.before}"
start = Time.now
done_job = Query.new.execute sql
results = done_job.query_results
finish = Time.now
# Note if the query was cached because these are free queries
cached = done_job.cache_hit? ? '[cached]' : ''
puts "Results (#{(finish - start).to_i} seconds, searching #{done_job.bytes_processed} bytes #{cached})"
# Used by the formatter.  We need to have the longest line so that subsequent items line up correctly
longest = results.collect { |r| (r['repo_name']).length rescue 0 }.max
format = "%d.\t%#{longest}s -- %d points\n"

begin
  # Print results
  results.each_with_index { |r, i|
    printf(format, i + 1, (r['repo_name']), r['points'])
  }

  if options.gnuplot
    # need to add a fake header row
    GnuPlot.new(results.unshift({'repo_name' => '', 'points' => 0})).execute
  end
rescue => e
  puts "Error: #{e.message}"
end


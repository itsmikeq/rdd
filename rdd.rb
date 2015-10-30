#!/usr/bin/env ruby
# builtins: ostruct optparse optparse/date optparse/time
# Password is notasecret
# Creds are needed for a successful connection, this is sloppy but functional
creds_file = File.join(File.dirname(__FILE__), Dir.glob('*.json').first)
raise "json encoded google apps file needed, put it in the current directory.
It needs to be the json formatted one from https://console.developers.google.com/project" unless creds_file
ENV['GOOGLE_APPLICATION_CREDENTIALS'] = creds_file

# Load up my helper
load File.join(File.dirname(__FILE__), 'util.rb')

%w(ostruct optparse optparse/date optparse/time gcloud).each do |_req|
  begin
    require _req
  rescue LoadError => e
    puts "Yo - you need to install #{_req} 'gem install #{_req}'"
    raise e
  end
end

class ElParso
  def self.parse(args)
    options = ::OpenStruct.new
    options.after = (Time.now - (60*60*24*20)).to_datetime
    options.before = DateTime.now
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

options = ElParso.parse(ARGV)
if options.before < options.after
  raise "#{options.before.to_s} should be after #{options.after.to_s} -- Check --before/-b and --after/-a options"
end

sql = if options.before.to_time.to_i > Time.parse("2015-01-01").to_time.to_i # if its after 2015, then
        QueryBuilder.new(options.before, options.after, options.top).after_timeline
      else
        QueryBuilder.new(options.before, options.after, options.top).timeline
      end
# puts sql
puts "Getting Github statistics for #{options.after} - #{options.before}"
start = Time.now
# puts sql
results = Query.new.execute sql
finish = Time.now
# puts results.inspect

puts "Results (#{(finish - start).to_i } seconds)"

# Going old school here with some line formatting
longest = results.collect { |r| (r['repo_name'] || r['repository_url'].split('/').last(2).join('/')).length rescue 0 }.max

format = "%d.\t%#{longest}s -- %d points\n"

begin
  results.each_with_index { |r, i|
    printf(format, i + 1, (r['repo_name'] || r['repository_url'].split('/').last(2).join('/') rescue ''), r['points'])
  }

  if options.gnuplot
    # need to add a fake header row
    GnuPlot.new(results.unshift({'repo_name' => '', 'points' => 0})).execute
  end
rescue => e
  puts "Error: #{e.message}"
end


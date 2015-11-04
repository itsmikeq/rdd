## RDD 

### Setup

Requires you to have a [json formatted development key](https://console.developers.google.com/project) from google cloud
You can put this file anywhere and export its location, or place it in `.`

Alternatively you can use the gcloud SDK and run `gcloud auth --account you@gmail.com --project your-project login`

You'll also need to export your project with `export GCLOUD_PROJECT=my-project-name`

### Usage

> Example: `./rdd.rb --after 2015-08-05T20:10:02-00:00 --top 20`

```
Usage: rrd.rb [options]
    -a, --after [Date]               Date to start search at, ISO8601 or YYYY-MM-DD format.
                                     Default: 28 days ago
    -b, --before [Date]              ISO8601 Date to end search at, ISO8601 or YYYY-MM-DD format.
                                     Default: Now
    -t, --top TOP                    The number of repos to show.
                                     Default: 20
    -g, --gnuplot                    Plot this
                                     Plot the numbers with gnuplot
    -w, --answer                     Answers the questions
                                     Default: 20
```                                   

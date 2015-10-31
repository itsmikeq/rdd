## RDD 

>hopefully stands for resume driven development and not really dumb design

Requires you to have a [json formatted development key](https://console.developers.google.com/project) from google cloud in '.'

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
                                     
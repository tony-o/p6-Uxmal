# Uxmal

Analyses the an array of META6.json-ish hashes to determine the required build order and also provides a control mechanism for building as efficiently as possible.

## `depends-tree(@meta)`

Really only needs an array of `{ :name, :depends([]) }` of all of the dependencies required

## `depends-channel(%tree, $concurrency = 3)`

Returns a `Channel` you can use for flow control for whatever you're doing.

Example:

```perl6
my %tree = depends-tree(@list-of-metas);
my $flow = depends-channel(%tree);

loop {
  if $flow.poll -> $key {
    # do something with %tree{$k}
    %tree{$k}<promise>.keep; # this is important so the controller
                             # knows it can send the next item to be
                             # built
  }
  if $flow.closed { last }
  sleep .5;
};
```

Check out `t/build-order.t:32` for a more complex example.


## `generate-dot(%tree)`

Returns a very simply graphviz dot format string that you can use to write to a file and generate a chart.

## `attempt-full-dot-gen(%tree, :$force = False)`

Will `die` if `$force ~~ False` or if `which dot` does not return the path to graphviz's `dot`.  

This method attempts to generate the dot file, runs `dot -T png -o <tmp-file.png> <tmp-file.dot>` and returns the string path to the png file.

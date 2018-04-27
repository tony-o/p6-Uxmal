use Uxmal;
use Test;

plan 3;

my @tdata = ( 
  { :name<A>, :depends(qw<B C>) },
  { :name<B>, :depends(qw<C>)   },
  { :name<C>, :depends()        },
);
my %tdata-tree = depends-tree @tdata;

my $s = depends-channel(%tdata-tree, 1);
my @build-order;
loop {
  if $s.poll -> $key {
    CATCH { default { .say; } }
    @build-order.push($key<name>);
    sleep rand;
    $key<promise>.keep;
  };
  if $s.closed  { last };
  sleep 0.1;
}


is-deeply ['C', 'B', 'A'], @build-order, 'should build simple deps in C, B, A order';


## do a more complicated example;

@tdata = (
  { :name<A>, :depends(qw<B C D E F>) },
  { :name<B>, :depends()              }, #this can build right away
  { :name<C>, :depends(qw<D>)         },
  { :name<D>, :depends(qw<E F>)       },
  { :name<E>, :depends()              },
  { :name<F>, :depends()              },
);

my %sleep-times = ( #control the order in which the build operates for testing
  A => 0,
  B => 4,
  C => 0,
  D => 0,
  E => 1,
  F => .5,
);

%tdata-tree = depends-tree @tdata;
@build-order = ();
$s = depends-channel(%tdata-tree, 3);
# note if the concurrency here is 1 then the order *could* be any combination
# of B/E/F starting first

loop {
  if $s.poll -> $key {
    start {
      CATCH { default { .say; } }
      "Building $key<name> (waiting: {%sleep-times{$key<name>}})".say;
      sleep %sleep-times{$key<name>} // 1;
      "Completing $key<name>".say;
      @build-order.push($key<name>);
      $key<promise>.keep;
    }
  }
  if $s.closed  { last };
  sleep 0.1;
}

is-deeply ['F', 'E', 'D', 'C', 'B', 'A'], @build-order, 'more complex builds with start {} should order well';

# end of complex example

# check for circulars:
dies-ok -> {
  (depends-tree @(
    { :name<A>, depends => [qw<B>] },
    { :name<B>, depends => [qw<A>] },
  ));
}, 'circular reference should die';

unit module Uxmal;
use Data::Dump;

sub build($name) {
  %*tree{$name} = {
    children => [],
    parents  => [],
    status   => 'prepared',
    promise  => Promise.new,
    name     => $name,
  } if !%*tree{$name}.defined;
}

sub depends-tree(@metas where {
  $_.grep({$_<depends>.defined && $_<name>.defined}).elems == $_.elems
}) is export {
  my %*tree;
  for @metas.grep(*.defined) -> $m {
    build $m<name>;
    for @($m<depends>) -> $dep {
      build $dep;
      %*tree{$m<name>}<children>.push(%*tree{$dep});
      %*tree{$dep}<parents>.push(%*tree{$m<name>});
      die "Circular reference on $dep and {$m<name>}"
        if %*tree{$dep}<children>.grep({$_<name> eq $m<name>});
    }
  }
  %*tree;
}

sub depends-channel(%tree, $concurrency = 3) is export {
  my $channel = Channel.new;
  start {
    my ($added, $kept, @promises, %started);
    repeat {
      $added = 0;
      $kept = 0;
      for %tree.keys -> $k {
        my $e = %tree{$k};
        CATCH { default { .say; } }
        $kept++ if $e<promise>.status ~~ Kept;
        if    $e<children>.grep({$_<promise>.status !~~ Kept}).elems == 0
           && $e<promise>.status ~~ Planned
           && !%started{$k}
        {
          %started{$k} = True;
          $channel.send($k);
          @promises.push($e<promise>);
          $added = 0;
          last if @promises.grep(*.status !~~ Kept).elems >= $concurrency;
        }
      }
      if $added == 0 || @promises.grep(*.status !~~ Kept).elems >= $concurrency {
        while @promises.grep(*.status !~~ Kept).elems >= $concurrency {
          await Promise.anyof(@promises) if @promises.elems;
          @promises.=grep({.status !~~ Kept});
        }
      }
      $added = -1 if $kept == %tree.keys.elems;
    } while $added != -1;
    CATCH { default { .say; } } 
    $channel.close;
  };

  $channel;
};

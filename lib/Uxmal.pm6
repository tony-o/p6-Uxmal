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

sub generate-dot(%tree) is export {
  my $dot = "digraph G \{\n";
  for %tree.keys -> $k {
    for @(%tree{$k}<parents>) -> $par {
      $dot ~= "\t\"$par<name>\" -> \"$k\"\n";
    }
  }
  $dot ~= "\}";
  $dot;
}

sub attempt-full-dot-gen(%tree, :$force = False) is export {
  my $cmd = $force || qx{which dot}.lines[0];
  die 'Could not find `which dot`' if !$cmd;
  my $f-data = generate-dot %tree;
  my $f-name = ("A".."Z").roll(32).join;
  my $temp-file = "{$*TMPDIR}{$f-name}.dot".IO;
  $temp-file.spurt($f-data);
  my $out-file = "{$*TMPDIR}{$f-name}.png".IO.absolute;
  $temp-file .=absolute;
  qqx{dot -T png -o $out-file $temp-file};
  $out-file;
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

sub depends-channel(%tree, $concurrency = $*SCHEDULER.max_threads/2) is export {
  my $channel = Channel.new;
  warn "Dead lock may occur (concurrency={$concurrency}, max-threads={$*SCHEDULER.max_threads})"
    if 1+$concurrency >= $*SCHEDULER.max_threads-1;
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

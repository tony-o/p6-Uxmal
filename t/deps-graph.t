use Uxmal;
use Test;

plan 2;

my @tdata = ( 
  { :name<A>, :depends(qw<B C>) },
  { :name<B>, :depends(qw<C>)   },
  { :name<C>, :depends()        },
);

lives-ok -> {
  depends-tree(@tdata);
}, 'depends-tree constraint lives ok';
dies-ok -> {
  @tdata[*-1]<depends> = qw<A>;
  depends-tree(@tdata, :kill-circles);
}, 'depends-tree constraint dies ok';

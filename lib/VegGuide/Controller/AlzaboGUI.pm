package VegGuide::Controller::AlzaboGUI;

use strict;
use warnings;
use namespace::autoclean;

use Alzabo::Config;
use File::Basename qw( basename );
use File::Spec;
use VegGuide::Config;
use VegGuide::View::AlzaboGUI;

use Moose;

BEGIN { extends 'Catalyst::Controller'; }

my $ShareDir = '/usr/local/share/alzabo/schema';

sub schema : Regex('^schema(/[^/]+)?') {
    my $self = shift;
    my $c    = shift;
    my $path = $c->request()->captures()->[0] || '/index.mhtml';

    unless ( -d $ShareDir
        && !VegGuide::Config->IsProduction() ) {
        $c->response()->status(404);
        return;
    }

    require Alzabo::Create::Schema;

    if ( $path =~ /\.jpg$/ ) {
        my $file = File::Spec->catfile( $ShareDir, basename($path) );
        my $fh = IO::File->new( $file, 'r' )
            or die "Cannot read $file: $!";

        $c->response()->content_type('image/jpeg');
        $c->response()->body($fh);

        return;
    }

    my $p = $c->request()->parameters();
    while ( my ( $k, $v ) = each %{$p} ) {
        $c->stash()->{$k} = $v;
    }

    $c->stash()->{template} = $path;
}

# Not sure why this is necessary
sub process { }

sub end : Private {
    my $self = shift;
    my $c    = shift;

    if (   ( !$c->response()->status() || $c->response()->status() == 200 )
        && !$c->response()->body()
        && !@{ $c->error() || [] } ) {
        $c->forward( $c->view('AlzaboGUI') );
    }

    return;
}

__PACKAGE__->meta()->make_immutable();

1;

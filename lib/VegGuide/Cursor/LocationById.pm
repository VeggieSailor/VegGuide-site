package VegGuide::Cursor::LocationById;

use strict;
use warnings;

use parent 'Class::AlzaboWrapper::Cursor';

sub next {
    my $self = shift;

    my ($location_id) = $self->{cursor}->next
        or return;

    return VegGuide::Location->new( location_id => $location_id );
}

1;

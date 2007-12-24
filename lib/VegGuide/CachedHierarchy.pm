package VegGuide::CachedHierarchy;

use strict;
use warnings;

use File::Spec;

use VegGuide::Validate qw( validate validate_with SCALAR_TYPE ARRAYREF_TYPE OBJECT ARRAYREF );


# needs to be a global so we can use local()
use vars qw( $Checked );

my %Meta;
my %Cache;
my %Times;

{
    my $spec = { parent   => SCALAR_TYPE,
                 roots    => SCALAR_TYPE,
                 id       => SCALAR_TYPE,
                 order_by => { type => OBJECT | ARRAYREF,
                               optional => 1 },
                 flags    => ARRAYREF_TYPE( default => [] ),
                 first    => SCALAR_TYPE( default => 0 ),
               };
    sub _build_cache
    {
        my $class = shift;
        my %p     = validate( @_, $spec );

        my $first = delete $p{first};

        my $r = $p{roots};

        my $roots = $class->$r();

        $Cache{$class} = { roots => [] };
        $Meta{$class}{params} = \%p;

        my $clean = $class;
        $clean =~ s/::/-/g;
        $Meta{$class}{file} =
            File::Spec->catfile( File::Spec->tmpdir, $clean );

        $class->_add_nodes($roots);

        my $f = $Meta{$class}{file};

        _touch_file($f) if $first && $ENV{MOD_PERL};

        $Meta{$class}{last_build} = (stat $f)[9];

        #    $class->_dump( '_cached_roots', 0 );
    }
}

sub _touch_file
{
    my $file = shift;

    open my $fh, ">$file" or die "Cannot write to $file";
    # The contents don't matter, only the last mod time.
    print $fh "1\n";
    close $fh;

    unless ( $> || $< )
    {
        my ( $uid, $gid ) = _get_uid_gid();

        chown $uid, $gid, $file
            or die "Cannot chown $file to Apache server uid/gid: $!";
    }
}

# Copied from Mason's ApacheHandler
sub _get_uid_gid
{
    # Apache2 lacks $s->uid.
    # Workaround by searching the config tree.
    require Apache2::Directive;

    my $conftree = Apache2::Directive::conftree();
    my $user = $conftree->lookup('User');
    my $group = $conftree->lookup('Group');

    $user =~ s/^["'](.*)["']$/$1/;
    $group =~ s/^["'](.*)["']$/$1/;

    my $uid = $user ? getpwnam($user) : $>;
    my $gid = $group ? getgrnam($group) : $);

    return ( $uid, $gid );
}

sub _dump
{
    my $thing = shift;
    my $meth = shift;
    my $i = shift;

    foreach my $n ( $thing->$meth() )
    {
        print ' ' x $i;
        print '- ';
        print $n->name;
        print "\n";

        $n->_dump( 'children', $i + 2 );
    }
}

sub _add_nodes
{
    my $class = shift;
    my $cursor = shift;
    my $parent = shift;
    my $children = shift;

    my $table = $class->table;
    my $parent_col = $table->column( $Meta{$class}{params}{parent} );

    my $id = $Meta{$class}{params}{id};

    while ( my $node = $cursor->next )
    {
        if ($children)
        {
            push @$children, $node;
        }
        else
        {
            push @{ $Cache{$class}{roots} }, $node;
        }

        my $id_val = $node->$id();

        $Cache{$class}{by_id}{$id_val} = $node;

        foreach my $flag ( @{ $Meta{$class}{params}{flags} } )
        {
            $Cache{$class}{nodes}{$id_val}{flags}{$flag} = $node->$flag();
        }

        $Cache{$class}{nodes}{$id_val}{parent} = $parent;

        my $cursor =
            $table->rows_where
                ( where =>
                  [ $parent_col, '=', $id_val ],
                  ( $Meta{$class}{params}{order_by} ?
                    ( order_by => $Meta{$class}{params}{order_by} ) :
                    ()
                  )
                );

        my $children =
            Class::AlzaboWrapper::Cursor->new( cursor => $cursor );

        my @children;
        $Cache{$class}{nodes}{$id_val}{children} = \@children;

        $class->_add_nodes( $children, $node, \@children );
    }
}

sub _cached_roots
{
    my $class = shift;

    $class->_check_cache_time;

    return @{ $Cache{$class}{roots} };
}

sub all
{
    my $class = shift;

    $class->_check_cache_time;

    local $Checked = 1;

    return map { $_, $_->descendants } @{ $Cache{$class}{roots} };
}
*All = \&all;

sub all_with_flag
{
    my $class = shift;
    my $flag = shift;
    my $val = shift;

    $class->_check_cache_time;

    my $id = $Meta{$class}{params}{id};

    local $Checked = 1;

    return
        ( grep { $Cache{$class}{nodes}{ $_->$id() }{flags}{$flag} == $val }
          map { $_, $_->descendants }
          grep { $Cache{$class}{nodes}{ $_->$id() }{flags}{$flag} == $val }
          @{ $Cache{$class}{roots} }
        );
}

sub ByID
{
    my $class = shift;
    my $id = shift;

    return $Cache{$class}{by_id}{$id};
}

sub parent
{
    my $self = shift;
    my $class = ref $self;

    $class->_check_cache_time unless $Checked;

    my $id = $Meta{$class}{params}{id};

    return $Cache{$class}{nodes}{ $self->$id() }{parent};
}

sub children
{
    my $self = shift;
    my $class = ref $self;

    my $id = $Meta{$class}{params}{id};

    return $class->children_of( $self->$id() );
}

sub children_of
{
    my $class = shift;
    my $id_val = shift;

    return $class->_cached_roots unless defined $id_val;

    $class->_check_cache_time unless $Checked;

    return ( $Cache{$class}{nodes}{$id_val}{children} ?
             @{ $Cache{$class}{nodes}{$id_val}{children} } :
             ()
           );
}

sub _cached_children_with_flag
{
    my $self = shift;
    my $flag = shift;
    my $val = shift;
    my $class = ref $self;

    $class->_check_cache_time;

    my $id = $Meta{$class}{params}{id};

    return
        ( grep { $Cache{$class}{nodes}{ $_->$id() }{flags}{$flag} == $val }
          @{ $Cache{$class}{nodes}{ $self->$id() }{children} }
        );
}

sub child_count
{
    my $self = shift;
    my $class = ref $self;

    $class->_check_cache_time;

    my $id = $Meta{$class}{params}{id};

    # potential rows
    return 0 unless defined $self->$id();

    return 0 unless defined $Cache{$class}{nodes}{ $self->$id() }{children};

    return scalar @{ $Cache{$class}{nodes}{ $self->$id() }{children} };
}

sub _cached_child_count_with_flag
{
    my $self = shift;
    my $flag = shift;
    my $val = shift;
    my $class = ref $self;

    $class->_check_cache_time;

    my $id = $Meta{$class}{params}{id};

    return
        scalar ( grep { $Cache{$class}{nodes}{ $_->$id() }{flags}{$flag} == $val }
                 @{ $Cache{$class}{nodes}{ $self->$id() }{children} }
               );
}

sub _cached_ancestors
{
    my $self = shift;
    my $class = ref $self;

    my @a;

    $class->_check_cache_time;

    local $Checked = 1;

    my $node = $self;
    while ( $node = $node->parent )
    {
        unshift @a, $node;
    }

    return @a;
}

sub _cached_descendants
{
    my $self = shift;
    my $class = ref $self;

    $class->_check_cache_time unless $Checked;

    local $Checked = 1;

    my @d = $self->children;

    my @c = @d;

    while ( my $node = shift @c )
    {
        my @c1 = $node->children;

        push @d, @c1;

        push @c, @c1;
    }

    return @d;
}

sub descendants { $_[0]->_cached_descendants }

sub descendant_ids
{
    my $self = shift;
    my $class = ref $self;

    my $id = $Meta{$class}{params}{id};

    return map { $_->$id() } $self->descendants;
}

sub ancestors { $_[0]->_cached_ancestors }

sub ancestor_ids
{
    my $self = shift;
    my $class = ref $self;

    my $id = $Meta{$class}{params}{id};

    return map { $_->$id() } $self->ancestors;
}

sub _check_cache_time
{
    my $class = shift;

    return unless $ENV{MOD_PERL};

    my $last_mod = (stat $Meta{$class}{file})[9];

    if ( $last_mod > $Meta{$class}{last_build} )
    {
        $class->_rebuild_cache;
    }
}

sub _rebuild_cache
{
    my $class = shift;

    my %p = %{ $Meta{$class}{params} };

    $class->_build_cache(%p);
}

sub _cached_data_has_changed
{
    my $class = ref $_[0] || $_[0];

    $class->_rebuild_cache;

    _touch_file( $Meta{$class}{file} );
}

1;

__END__


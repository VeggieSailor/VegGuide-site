package VegGuide::Client;

use strict;
use warnings;

use Encode 2.23 ();

use VegGuide::Validate
    qw( validate validate_with validate_pos UNDEF SCALAR BOOLEAN ARRAYREF HASHREF );


BEGIN
{
    foreach my $meth ( qw( show_localized_content encoding show_utf8 preferred_locale ) )
    {
        no strict 'refs';
        *{$meth} = sub { $_[0]->{$meth} };
    }
}

sub new
{
    my $class   = shift;
    my $request = shift;
    my $locale  = shift;

    my $self = bless {}, $class;

    $self->_get_encodings($request);
    $self->_get_languages($request);

    if ($locale)
    {
        my ( $encoding, $transcoder ) =
            $self->_encoding_for_locale($locale);

        $self->{encoding} = $encoding;

        if ( $locale->language_code ne 'en'
             &&
             $self->{possible_languages}{ $locale->language_code }
           )
        {
            $self->{show_localized_content} = 1;
        }
    }

    $self->{encoding} ||= 'utf-8-strict';
    $self->{show_utf8} = $self->_client_accepts_utf8;

    return $self;
}

sub new_from_params
{
    my $class = shift;
    my %p = validate( @_,
                      { show_localized_content => { type => BOOLEAN },
                        encoding               => { type => SCALAR },
                        show_utf8              => { type => BOOLEAN },
                        preferred_locale       => { type => SCALAR },
                      },
                    );

    my $self = bless \%p, $class;

    $self->{possible_encodings} = { $self->{encoding} => 1 };
    $self->{possible_languages} = { $self->{preferred_locale} => 1 };

    return $self;
}

sub charset
{
    my $self = shift;

    return 'utf-8' if $self->encoding eq 'utf-8-strict';
    return 'big5' if $self->encoding =~ /^big5/i;

    return $self->encoding;
}

sub encode
{
    my $self = shift;

    return $_[0] if $self->encoding eq 'utf-8-strict';

    return Encode::encode( $self->encoding, $_[0] );
}

sub decode
{
    my $self = shift;

    return $_[0] if Encode::is_utf8( $_[0] );

    return Encode::decode( $self->encoding, $_[0] );
}

sub accepts_language { $_[0]->{possible_languages}{ $_[1] } }

sub localize_for_location
{
    my $self = shift;
    my $location = shift;

    my $locale = $location->locale
        or return;

    return 1
        if $self->show_utf8 && $self->accepts_language( $locale->language_code );
}

sub _encoding_for_locale
{
    my $self   = shift;
    my $locale = shift;

    foreach my $e ( 'utf-8-strict', $locale->encodings )
    {
        return $e if $self->{possible_encodings}{$e};
    }

    return;
}

sub _get_encodings
{
    my $self    = shift;
    my $request = shift;

    if ( my $charsets = $request->header('Accept-Charset') )
    {
        $self->{possible_encodings} = 
            { map { my ( $c, undef ) = split /\s*;\s*q=\s*/;
                    my $a = Encode::resolve_alias($c);
                    $a ? ( $a => 1 ) : () }
              split /\s*,\s*/, $charsets
            };
    }
    else
    {
        $self->{possible_encodings} = { 'utf-8-strict' => 1 };
    }
}

sub _get_languages
{
    my $self    = shift;
    my $request = shift;

    my $highest_w = 0;
    if ( my $languages = $request->header('Accept-Language') )
    {
        foreach my $lang ( split /\s*,\s*/, $languages )
        {
            my ( $l, $w ) = split /\s*;\s*q=\s*/, $lang;

            $w ||= 1;

            next if $l eq '*';

            $l =~ s/-/_/g;

            if ( $w > $highest_w )
            {
                $self->{preferred_locale} = $l;
                $highest_w = $w;
            }

            $l =~ s/_\w+$//;

            $self->{possible_languages}{$l} = 1;
        }
    }

    $self->{possible_languages} ||= { 'en' => 1 };
    $self->{preferred_locale}   ||= 'en_US';
}

sub _client_accepts_utf8 { $_[0]->{possible_encodings}{'utf-8-strict'} }


1;

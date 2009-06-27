package Net::Termcast;
use Moose;
use MooseX::AttributeHelpers;

use IO::Socket::Telnet;
use Term::VT102;

has host => (
    is      => 'ro',
    isa     => 'Str',
    default => 'termcast.org',
);

has port => (
    is      => 'ro',
    isa     => 'Int',
    default => 23,
);

has rows => (
    is      => 'ro', # should be rw at some point
    isa     => 'Int',
    default => 24,
);

has cols => (
    is      => 'ro', # should be rw at some point
    isa     => 'Int',
    default => 80,
);

has in_menu => (
    is       => 'rw',
    isa      => 'Bool',
    default  => 0,
    init_arg => undef,
);

has sessions => (
    traits   => ['Collection::ImmutableHash'],
    is       => 'ro',
    isa      => 'HashRef[Net::Termcast::Session]',
    default  => sub { {} },
    init_arg => undef,
    provides => {
        get    => 'session',
        exists => 'has_session',
    },
);

has _vt => (
    is      => 'ro',
    isa     => 'Term::VT102',
    lazy    => 1,
    default => sub {
        my $self = shift;
        my $vt = Term::VT102->new(cols => $self->cols, rows => $self->rows);
        $vt->option_set(LINEWRAP => 1);
        $vt->option_set(LFTOCRLF => 1);
        return $vt;
    },
    init_arg => undef,
);

has _sock => (
    is       => 'ro',
    isa      => 'IO::Socket::Telnet'
    lazy     => 1,
    default  => sub {
        my $self = shift;
        my $socket = IO::Socket::Telnet->new(
            PeerAddr => $self->host,
            PeerPort => $self->port,
        );
        die "Unable to connect to " . $self->host . ": $!"
            if !defined($socket);
        return $socket;
    },
    init_arg => undef,
);

sub BUILD {
    my $self = shift;
    $self->_get_menu;
    $self->in_menu(1);
}

sub refresh {
    $self->sock->send(' ', 0);
    $self->_get_menu;
}

sub select_session {
    my $self = shift;
    my ($session) = @_;
    return unless exists $self->sessions->{$session};
    $self->sock->send('q', 0) if $self->in_menu;
    $self->sock->send($session, 0);
    $self->_get_screen;
    $self->in_menu(0);
}

# XXX: these two should use color at some point
sub rows {
    my $self = shift;
    my @rows;
    push @rows, $self->row_plaintext($_) for 1..$self->rows;
    return @rows;
}

sub screen {
    my $self = shift;
    return join "\n", $self->rows;
}

sub _get_screen {
    my $self = shift;
    my $screen;
    $self->sock->recv($screen, 4096, 0);
    $self->vt->process($screen);
}

sub _get_menu {
    my $self = shift;
    return unless $self->in_menu;
    $self->_get_screen;
    $self->_parse_menu;
}

# XXX: need to handle multiple pages
sub _parse_menu {
    my $self = shift;
    my %sessions;
    for my $row ($self->rows) {
        next unless $row =~ /^ ([a-z])\) (\w+) \(idle ([^,]+), connected ([^,]+), (\d+) viewers?, (\d+) bytes?\)/;
        my ($session, $name, $idle, $connected, $viewers, $bytes) = ($1, $2, $3, $4, $5, $6);
        $sessions{$session} = Net::Termcast::Session->new(
            name      => $name,
            idle      => $idle,
            connected => $connected,
            viewers   => $viewers,
            bytes     => $bytes,
        );
    }
    return \%sessions;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

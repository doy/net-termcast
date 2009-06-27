package Net::Termcast;
use Moose;
use MooseX::AttributeHelpers;
use Net::Termcast::Session;

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

has location => (
    is       => 'rw',
    isa      => 'Str',
    default  => 'menu',
    init_arg => undef,
);

has sessions => (
    traits   => ['Collection::Hash'],
    is       => 'ro',
    isa      => 'HashRef[Net::Termcast::Session]',
    default  => sub { {} },
    init_arg => undef,
    provides => {
        get    => 'session',
        exists => 'has_session',
        keys   => 'session_ids',
        set    => '_set_session',
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
    isa      => 'IO::Socket::Telnet',
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
}

sub refresh_menu {
    my $self = shift;
    my $name;
    if ($self->location ne 'menu') {
        $name = $self->session($self->location)->name;
        $self->_sock->send('q', 0);
        $self->location('menu');
    }
    $self->_sock->send(' ', 0);
    $self->_get_menu;
    return unless $name;
    for my $session ($self->session_ids) {
        if ($self->session($session)->name eq $name) {
            $self->select_session($session);
            return;
        }
    }
}

sub select_session {
    my $self = shift;
    my ($session) = @_;
    return unless $self->session($session);
    $self->_sock->send('q', 0) unless $self->location eq 'menu';
    $self->_sock->send($session, 0);
    $self->location($session);
}

# XXX: these two should use color at some point
sub screen_rows {
    my $self = shift;
    $self->_get_screen;
    return map { $self->_vt->row_plaintext($_) } 1..$self->rows;
}

sub screen {
    my $self = shift;
    return join "\n", $self->screen_rows;
}

sub _get_screen {
    my $self = shift;
    my $screen;
    $self->_sock->recv($screen, 4096, 0);
    $self->_vt->process($screen);
}

sub _get_menu {
    my $self = shift;
    return unless $self->location eq 'menu';
    $self->_get_screen;
    $self->_parse_menu;
}

# XXX: need to handle multiple pages
sub _parse_menu {
    my $self = shift;
    my %sessions;
    for my $row ($self->screen_rows) {
        next unless $row =~ /^ ([a-z])\) (\w+) \(idle ([^,]+), connected ([^,]+), (\d+) viewers?, (\d+) bytes?\)/;
        my ($session, $name, $idle, $connected, $viewers, $bytes) = ($1, $2, $3, $4, $5, $6);
        $self->_set_session($session,
                            Net::Termcast::Session->new(
                                name      => $name,
                                idle      => $idle,
                                connected => $connected,
                                viewers   => $viewers,
                                bytes     => $bytes,
                            ));
    }
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

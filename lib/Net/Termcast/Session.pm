package Net::Termcast::Session;
use Moose;

has name => (
    is  => 'ro',
    isa => 'Str',
);

has idle => (
    is  => 'ro',
    isa => 'Str',
);

has connected => (
    is  => 'ro',
    isa => 'Str',
);

has viewers => (
    is  => 'ro',
    isa => 'Int',
);

has bytes => (
    is  => 'ro',
    isa => 'Int',
);

__PACKAGE__->meta->make_immutable;
no Moose;

1;

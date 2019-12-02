package Smokeping::probes::OpenSSHMikrotikRouterOSPing;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command

C<smokeping -man Smokeping::probes::OpenSSHMikrotikRouterOSPing>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::OpenSSHMikrotikRouterOSPing>

to generate the POD document.

=cut

use strict;

use base qw(Smokeping::probes::basefork);
use Net::OpenSSH;
use Carp;

my $e = "=";
sub pod_hash {
	return {
		name => <<DOC,
Smokeping::probes::OpenSSHMikrotikRouterOSPing - Mikrotik RouterOS SSH Probe for SmokePing
DOC
		description => <<DOC,
Connect to Mikrotik Router Device via OpenSSH to run ping commands.
This probe uses the "ping" cli of the Mikrotik RouterOS.  You have
the option to specify which interface the ping is sourced from as well.
DOC
		notes => <<DOC,
${e}head2 Mikrotik RouterOS configuration

The Mikrotik RouterOS device should have a username/password configured, and
the ssh server must not be disabled.

Make sure to connect to the remote host once from the commmand line as the
user who is running smokeping. On the first connect ssh will ask to add the
new host to its known_hosts file. This will not happen automatically so the
script will fail to login until the ssh key of your Mikrotik RouterOS box is in the
known_hosts file.

${e}head2 Requirements

This module requires the  L<Net::OpenSSH> and L<IO::Pty> perl modules.
DOC
		authors => <<'DOC',
Tony DeMatteis E<lt>tonydema@gmail.comE<gt>

based on L<Smokeping::Probes::OpenSSHJunOSPing> by Tobias Oetiker E<lt>tobi@oetiker.chE<gt>,
which itself is
based on L<Smokeping::probes::TelnetJunOSPing> by S H A N E<lt>shanali@yahoo.comE<gt>.
DOC
	}
}

sub new($$$)
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new(@_);

    $self->{pingfactor} = 1000; # Gives us a good-guess default

    return $self;
}

sub ProbeDesc($){
    my $self = shift;
    my $bytes = $self->{properties}{packetsize};
    return "Arista EOS - ICMP Echo Pings ($bytes Bytes)";
}

sub pingone ($$){
  my $self = shift;
  my $target = shift;
  my $source = $target->{vars}{source};
  my $dest = $target->{vars}{host};
  my $psource = $target->{vars}{psource};
  my @output = ();
  my $login = $target->{vars}{routerosuser};
  my $password = $target->{vars}{routerospass};
  my $bytes = $self->{properties}{packetsize};
  my $pings = $self->pings($target);
  my $ssh_cmd = $target->{vars}{ssh_binary_path};

  # do NOT call superclass ... the ping method MUST be overwriten
  my %upd;
  my @args = ();

  my $ssh = Net::OpenSSH->new(
      $source,
      $login ? ( user => $login ) : (),
      $password ? ( password => $password ) : (),
      timeout => 60,
	    strict_mode => 0,
  		kill_ssh_on_timeout => 1,
  		ctl_dir => "/tmp/.libnet-openssh-perl",
 			master_opts => [-o => "StrictHostKeyChecking=no", "-vvv"],
	    $ssh_cmd ? (ssh_cmd => $ssh_cmd) : (ssh_cmd => '/usr/bin/ssh')
  );

  if ($ssh->error) {
      $self->do_log( "OpenSSHMikrotikRouterOSPing connecting $source: ".$ssh->error );
      return ();
  };

  # Debug
  # $self->do_log("ping $dest count=$pings size=$bytes src-address=$psource");

  if ( $psource ) {
     @output = $ssh->capture("ping $dest count=$pings size=$bytes src-address=$psource");
  } else {
     @output = $ssh->capture("ping $dest count=$pings size=$bytes");
  }

  if ($ssh->error) {
      $self->do_log( "OpenSSHMikrotikRouterOSPing running commands on $source: ".$ssh->error );
      return ();
  };

  pop @output;
  pop @output;

  # Debug
  # $self->do_log(Dumper \@output);

  my @times = ();

  while (@output) {
		my $outputline = shift @output;
		chomp($outputline);
    next if ($outputline =~ m/(sent|recieved|packet\-loss|min\-rtt|avg\-rtt)/);
		$outputline =~ /(\d)ms/ && push(@times,$1);
  }

  @times = map {sprintf "%.10e", $_ / $self->{pingfactor}} sort {$a <=> $b} @times;

  # Debug
  # $self->do_log(Dumper \@times);
  # my $length = @times;
  # $self->do_log("Length of times: $length");

  return @times;
}

sub probevars {
	my $class = shift;
	return $class->_makevars($class->SUPER::probevars, {
		packetsize => {
			_doc => <<DOC,
The (optional) packetsize option lets you configure the packetsize for
the pings sent.  You cannot ping with packets larger than the MTU of
the source interface, so the packet size should always be equal or less than MTU
DOC
			_default => 100,
			_re => '\d+',
			_sub => sub {
				my $val = shift;
				return "ERROR: packetsize must be between 12 and 1600"
					unless $val >= 12 and $val <= 1600;
				return undef;
			},
		},
	});
}

sub targetvars {
	my $class = shift;
	return $class->_makevars($class->SUPER::targetvars, {
		_mandatory => [ 'routerosuser', 'routerospass', 'source' ],
		source => {
			_doc => <<DOC,
The source option specifies the Mikrotik RouterOS device that is going to run
the ping commands.  This address will be used for the ssh connection.
DOC
			_example => "192.168.2.1",
		},
		psource => {
			_doc => <<DOC,
The (optional) psource option specifies an alternate IP address or
Interface from which you wish to source your pings from.  Mikrotik routers
can have many many IP addresses, and interfaces.  When you ping from a
router you have the ability to choose which interface and/or which IP
address the ping is sourced from.  Specifying an IP/interface does not
necessarily specify the interface from which the ping will leave, but
will specify which address the packet(s) appear to come from.  If this
option is left out the Mikrotik RouterOS Device will source the packet
automatically based on routing and/or metrics.  If this doesn't make sense
to you then just leave it out.
DOC
			_example => "192.168.2.129",
		},
		routerosuser => {
			_doc => <<DOC,
The routerosuser option allows you to specify a username that has ping
capability on the Mikrotik RouterOS Device.
DOC
			_example => 'user',
		},
		routerospass => {
			_doc => <<DOC,
The routerospass option allows you to specify the password for the username
specified with the option routerosuser.
DOC
			_example => 'password',
		},
    ssh_binary_path => {
      _doc => <<DOC,
The ssh_binary_path option specifies the path for the ssh client binary.
This option will specify the path to the OpenSSH host connector.  To find the
path use "which ssh".
DOC
      _example => "/usr/bin/ssh"
    }
	});
}

1;

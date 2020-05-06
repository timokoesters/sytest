# Copyright 2017 New Vector Ltd
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

use strict;
use warnings;

use Future;

package SyTest::Homeserver::Conduit::Base;
use base qw( SyTest::Homeserver );

use Carp;
use POSIX qw( WIFEXITED WEXITSTATUS );

sub _init
{
   my $self = shift;
   my ( $args ) = @_;

   $self->{$_} = delete $args->{$_} for qw(
       bindir pg_db pg_user pg_pass
   );

   defined $self->{bindir} or croak "Need a bindir";

   $self->{paths} = {};

   $self->SUPER::_init( $args );
}

sub start
{
   my $self = shift;

   my $hs_dir = $self->{hs_dir};

   # generate TLS key / cert
   # ...
   $self->{paths}{tls_cert} = "$hs_dir/server.crt";
   $self->{paths}{tls_key} = "$hs_dir/server.key";
   $self->{paths}{matrix_key} = "$hs_dir/matrix_key.pem";


   return $self->_generate_keyfiles;
}


sub http_api_host
{
   my $self = shift;
   return $self->{bind_host};
}

# run the process to generate the key files
sub _generate_keyfiles
{
   my $self = shift;

   my @args = ();

   if( ! -f $self->{paths}{matrix_key} ) {
      push @args, '--private-key', $self->{paths}{matrix_key};
   }

   if( ! -f $self->{paths}{tls_cert} || ! -f $self->{paths}{tls_key} ) {
      push @args, '--tls-cert', $self->{paths}{tls_cert},
         '--tls-key', $self->{paths}{tls_key},
   }

   if( ! scalar @args ) {
      # nothing to do here.
      return Future->done;
   }

   $self->{output}->diag( "Generating key files" );

   return $self->_run_command(
      command => [
         $self->{bindir} . '/generate-keys',
         @args,
      ],
   )->on_done( sub {
      $self->{output}->diag( "Generated key files" );
   });
}


package SyTest::Homeserver::Conduit::Monolith;
use base qw( SyTest::Homeserver::Conduit::Base SyTest::Homeserver::ProcessManager );

use Carp;

sub _init
{
   my $self = shift;
   my ( $args ) = @_;

   $self->SUPER::_init( $args );

   my $idx = $self->{hs_index};
   $self->{ports} = {
      monolith                 => main::alloc_port( "monolith[$idx]" ),
   };
}

sub configure
{
   my $self = shift;
   my %params = @_;

   $self->SUPER::configure( %params );
}

sub server_name
{
   my $self = shift;
   return $self->{bind_host} . ":" . $self->secure_port;
}

sub federation_port
{
   my $self = shift;
   return $self->secure_port;
}

sub secure_port
{
   my $self = shift;
   return $self->{ports}{monolith};
}

# sub unsecure_port
# {
#    my $self = shift;
#    return $self->{ports}{monolith_unsecure};
# }

sub start
{
   my $self = shift;

   return $self->SUPER::start->then(
      $self->_capture_weakself( '_start_monolith' )
   );
}

sub _get_config
{
   my $self = shift;
 
   return (version => 0);
}

# start the monolith binary, and return a future which will resolve once it is
# reachable.
sub _start_monolith
{
   my $self = shift;

   my $output = $self->{output};
   my $loop = $self->loop;

   $output->diag( "Starting monolith server" );
   my @command = (
      $self->{bindir} . '/conduit',
      '--registration_shared_secret', "reg_secret",
   );

   return $self->_start_process_and_await_connectable(
      setup => [
         env => {
            LOG_DIR => $self->{hs_dir},
            RUST_LOG=debug,
            ROCKET_ENV=production,
            ROCKET_HOSTNAME=$self->server_name,
            ROCKET_PORT=$self->secure_port,
            ROCKET_TLS={certs=\"$self->{paths}{tls_cert}\",key=\"$self->{paths}{tls_key}"}"
         },
      ],
      command => [ @command ],
      connect_host => $self->{bind_host},
      connect_port => $self->secure_port,
   )->else( sub {
      die "Unable to start dendrite monolith: $_[0]\n";
   })->on_done( sub {
      $output->diag( "Started monolith server" );
   });
}

# override for Homeserver::kill_and_await_finish: delegate to
# ProcessManager::kill_and_await_finish
sub kill_and_await_finish
{
   my $self = shift;
   return $self->SyTest::Homeserver::ProcessManager::kill_and_await_finish();
}

1;

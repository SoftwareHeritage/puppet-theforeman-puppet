require 'spec_helper_acceptance'

describe 'Scenario: install puppetserver (latest):', unless: unsupported_puppetserver do
  before(:all) do
    if check_for_package(default, 'puppetserver')
      on default, puppet('resource package puppetserver ensure=purged')
      on default, 'rm -rf /etc/sysconfig/puppetserver /etc/puppetlabs/puppetserver'
      on default, 'find /etc/puppetlabs/puppet/ssl/ -type f -delete'
    end

    # puppetserver won't start with lower than 2GB memory
    memoryfree_mb = fact('memoryfree_mb').to_i
    raise 'At least 2048MB free memory required' if memoryfree_mb < 256
  end

  context 'default options' do
    it_behaves_like 'an idempotent resource' do
      let(:manifest) do
        <<-EOS
        class { 'puppet':
          server => true,
        }
        EOS
      end
    end
  end

  describe 'server_max_open_files' do
    it_behaves_like 'an idempotent resource' do
      let(:manifest) do
        <<-MANIFEST
        class { 'puppet':
          server                => true,
          server_max_open_files => 32143,
        }

        # Puppet 5 + puppet/systemd 3 workaround
        # Also a possible systemd bug on Ubuntu 20.04
        # https://github.com/theforeman/puppet-puppet/pull/779#issuecomment-886847275
        if $puppet::server_max_open_files and (versioncmp($facts['puppetversion'], '6.1') < 0 or $facts['os']['name'] == 'Ubuntu' and $facts['os']['release']['major'] == '20.04') {
          exec { 'puppetserver-systemctl-daemon-reload':
            command     => 'systemctl daemon-reload',
            refreshonly => true,
            path        => $facts['path'],
            subscribe   => File['/etc/systemd/system/puppetserver.service.d/limits.conf'],
          }
        }
        MANIFEST
      end
    end

    # pgrep -f java.*puppetserver would be better. But i cannot get it to work. Shellwords.escape() seems to break something
    describe command("grep '^Max open files' /proc/`cat /var/run/puppetlabs/puppetserver/puppetserver.pid`/limits"), :sudo => true do
      its(:exit_status) { is_expected.to eq 0 }
      its(:stdout) { is_expected.to match %r{^Max open files\s+32143\s+32143\s+files\s*$} }
    end
  end
end

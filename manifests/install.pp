# == Class: docker
#
# Module to install an up-to-date version of Docker from a package repository.
# The use of this repository means, this module works only on Debian and Red
# Hat based distributions.  If $docker::params::ensure is set to absent or purge,
# then docker and its dependencies will be uninstalled.
#
class docker::install {
  validate_string($docker::version)
  validate_re($::osfamily, '^(Debian|RedHat)$', 'This module only works on Debian and Red Hat based systems.')
  validate_string($::kernelrelease)
  validate_bool($docker::use_upstream_package_source)

  $prerequired_packages = $::operatingsystem ? {
    'Debian' => ['apt-transport-https'],
    #'Debian' => ['apt-transport-https', 'cgroupfs-mount'],
    'Ubuntu' => ['apt-transport-https', 'cgroup-lite'],
    default  => '',
  }

  case $::osfamily {
    'Debian': {

      if member(['present','installed','latest'], $docker::ensure) {
          ensure_resource('package',$prerequired_packages,{ ensure => $docker::ensure })
      }
      if $docker::manage_package {
        Package['apt-transport-https'] -> Package['docker']
      }

      if ($docker::use_upstream_package_source) {

        if $docker::version {
          $dockerpackage = "lxc-docker-${docker::version}"
        } else {
          $dockerpackage = 'lxc-docker'
        }

        include apt
        apt::source { 'docker':
          location          => $docker::package_source_location,
          release           => 'docker',
          repos             => 'main',
          required_packages => 'debian-keyring debian-archive-keyring',
          key               => 'A88D21E9',
          key_source        => 'http://get.docker.io/gpg',
          pin               => '10',
          include_src       => false,
        }
        if $docker::manage_package {
          Apt::Source['docker'] -> Package['docker']
        }
      } else {
        $dockerpackage = 'docker.io'

        if $docker::version and $docker::ensure != 'absent' {
          $ensure = $docker::version
        } else {
          $ensure = $docker::ensure
        }
      }

      if $::operatingsystem == 'Ubuntu' {
        $install_init_d_script = false
        case $::operatingsystemrelease {
          # On Ubuntu 12.04 (precise) install the backported 13.04 (raring) kernel
          '12.04': { $kernelpackage = [
                                        'linux-image-generic-lts-raring',
                                        'linux-headers-generic-lts-raring'
                                      ]
          }
          # determine the package name for 'linux-image-extra-$(uname -r)' based
          # on the $::kernelrelease fact
          default: { $kernelpackage = "linux-image-extra-${::kernelrelease}" }
        }

        $manage_kernel = $docker::manage_kernel
      } else {
        # Debian does not need extra kernel packages
        $manage_kernel = false
        $install_init_d_script = true
      }
    }
    'RedHat': {
      if versioncmp($::operatingsystemrelease, '6.5') < 0 {
        fail('Docker needs RedHat/CentOS version to be at least 6.5.')
      }

      $manage_kernel = false

      if $docker::version {
        $dockerpackage = "docker-io-${docker::version}"
      } else {
        $dockerpackage = 'docker-io'
      }

      if ($docker::use_upstream_package_source) {
        include 'epel'
        if $docker::manage_package {
          Class['epel'] -> Package['docker']
        }
      }
    }
  }

  if $manage_kernel {
    package { $kernelpackage:
      ensure => $docker::ensure,
    }
    if $docker::manage_package {
      Package[$kernelpackage] -> Package['docker']
    }
  }

  if $docker::manage_package {
    package { 'docker':
      ensure => $docker::ensure,
      name   => $dockerpackage,
    }
  }

  if member(['absent','purged'], $docker::ensure) {

    ensure_resource('package',$prerequired_packages,{ ensure => $docker::ensure })

    file { '/etc/init.d/docker':
      ensure => 'absent',
    }

  } elsif $install_init_d_script == false {

    file { '/etc/init.d/docker':
      ensure => 'absent',
      notify => Service['docker'],
    }

  } elsif $install_init_d_script == true {

    file { '/etc/init.d/docker':
      source => 'puppet:///modules/docker/etc/init.d/docker',
      owner  => root,
      group  => root,
    }

  }

}

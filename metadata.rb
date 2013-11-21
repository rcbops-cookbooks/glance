name              "glance"
maintainer        "Rackspace US, Inc."
license           "Apache 2.0"
description       "Installs and configures the Glance Image Registry and Delivery Service"
long_description  IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version           IO.read(File.join(File.dirname(__FILE__), 'VERSION'))
recipe            "glance::setup", "Handles glance keystone registration and database creation"
recipe            "glance::api", "Installs packages required for a glance api server"
recipe            "glance::registry", "Installs packages required for a glance registry server"
recipe            "glance::replicator", "Drops in cronjobs to sync glance images when running 2 node HA setup w/ file storage"
recipe            "glance::glance-config", "abstracts all config setup to be called by other recipes"

%w{ centos ubuntu }.each do |os|
  supports os
end

%w{ database dsh mysql openssl osops-utils apache2 ceph }.each do |dep|
  depends dep
end

depends "keystone", ">= 1.0.20"

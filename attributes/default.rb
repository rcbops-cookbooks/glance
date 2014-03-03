#
# Cookbook Name:: glance
# Attributes:: default
#
# Copyright 2012-2013, Rackspace US, Inc.
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
#

########################################################################
# Toggles - These can be overridden at the environment level
########################################################################

# Define the ha policy for queues.  If you change this to true
# after you have already deployed you will need to wipe the RabbitMQ
# database by stopping rabbitmq, removing /var/lib/rabbitmq/mnesia
# and starting rabbitmq back up.  Failure to do so will cause the
# OpenStack services to fail to connect to RabbitMQ.
default["glance"]["rabbitmq"]["use_ha_queues"] = false
# ** NOTE: Unfortunately this isn't in glance yet and probably won't be
# until the Icehouse release: https://review.openstack.org/#/c/37511/
#

default["glance"]["use_debug"] = "False"

default["glance"]["services"]["api"]["scheme"] = "http"
default["glance"]["services"]["api"]["network"] = "public"
default["glance"]["services"]["api"]["port"] = 9292
default["glance"]["services"]["api"]["path"] = ""

default["glance"]["services"]["admin-api"]["scheme"] = "http"
default["glance"]["services"]["admin-api"]["network"] = "management"
default["glance"]["services"]["admin-api"]["port"] = 9292
default["glance"]["services"]["admin-api"]["path"] = ""

default["glance"]["services"]["internal-api"]["scheme"] = "http"
default["glance"]["services"]["internal-api"]["network"] = "management"
default["glance"]["services"]["internal-api"]["port"] = 9292
default["glance"]["services"]["internal-api"]["path"] = ""

default["glance"]["services"]["api"]["cert_file"] = "glance.pem"
default["glance"]["services"]["api"]["key_file"] = "glance.key"
default["glance"]["services"]["api"]["chain_file"] = ""
default["glance"]["services"]["api"]["wsgi_file"] = "glance-api"

default["glance"]["services"]["registry"]["scheme"] = "http"
default["glance"]["services"]["registry"]["network"] = "public"
default["glance"]["services"]["registry"]["port"] = 9191
default["glance"]["services"]["registry"]["path"] = ""

default["glance"]["services"]["registry"]["cert_file"] = "glance.pem"
default["glance"]["services"]["registry"]["key_file"] = "glance.key"
default["glance"]["services"]["registry"]["chain_file"] = ""
default["glance"]["services"]["registry"]["wsgi_file"] = "glance-registry"

default["glance"]["db"]["name"] = "glance"
default["glance"]["db"]["username"] = "glance"

# TODO: These may need to be glance-registry specific.. and looked up by glance-api
default["glance"]["service_tenant_name"] = "service"
default["glance"]["service_user"] = "glance"
default["glance"]["service_role"] = "admin"
default["glance"]["api"]["default_store"] = "file"
default["glance"]["api"]["swift"]["store_container"] = "glance"
default["glance"]["api"]["swift"]["store_large_object_size"] = "200"
default["glance"]["api"]["swift"]["store_large_object_chunk_size"] = "200"
default["glance"]["api"]["swift"]["enable_snet"] = "False"
default["glance"]["api"]["swift"]["store_region"] = nil
default["glance"]["api"]["rbd"]["rbd_store_ceph_conf"] = "/etc/ceph/ceph.conf"
default["glance"]["api"]["rbd"]["rbd_store_user"] = "glance"
default["glance"]["api"]["rbd"]["rbd_store_pool"] = "images"
default["glance"]["api"]["rbd"]["rbd_store_chunk_size"] = "8"
default["glance"]["api"]["cache"]["image_cache_max_size"] = "10737418240"
default["glance"]["api"]["notifier_strategy"] = "noop"
default["glance"]["api"]["notification_topic"] = "notifications"
default["glance"]["api"]["workers"] = [8, node["cpu"]["total"].to_i].min
default["glance"]["api"]["show_image_direct_url"] = "True"

# Partial name of a pipeline in your paste configuration file with the service name removed.
default["glance"]["api"]["flavor"] = "keystone"

# Default Image Locations
default["glance"]["image_upload"] = false
default["glance"]["images"] = []
default["glance"]["image"]["precise"] = "http://cloud-images.ubuntu.com/precise/current/precise-server-cloudimg-amd64-disk1.img"
default["glance"]["image"]["cirros"] = "http://download.cirros-cloud.net/0.3.1/cirros-0.3.1-x86_64-disk.img"
default["glance"]["image"]["fedora"] = "http://download.fedoraproject.org/pub/fedora/linux/releases/19/Images/x86_64/Fedora-x86_64-19-20130627-sda.qcow2"

# replicator attributes
default["glance"]["replicator"]["interval"] = 5
default["glance"]["replicator"]["checksum"] = "971b7cec95105747e77088e3e0853a636a120383"
default["glance"]["replicator"]["rsync_user"] = "glance"
default["glance"]["replicator"]["enabled"] = true

# Generic regex for process pattern matching (to be used as a base pattern).
# Works for both Grizzly and Havana packages on Ubuntu and CentOS.
procmatch_base = '^((/usr/bin/)?python\d? )?(/usr/bin/)?'

# platform-specific settings
case platform
  when "fedora", "redhat", "centos"
    default["glance"]["platform"] = {
      "supporting_packages" => ["MySQL-python", "python-keystone", "curl",
                                "python-glanceclient", "python-warlock",
                                "python-migrate"],
      "glance_packages" => ["openstack-glance", "python-swiftclient", "cronie",
                            "python-prettytable", "python-kombu",
                            "python-anyjson", "python-amqplib", "python-lockfile"],
      "glance_api_service" => "openstack-glance-api",
      "glance_api_procmatch" => procmatch_base + 'glance-api\b',
      "glance_registry_service" => "openstack-glance-registry",
      "glance_registry_procmatch" => procmatch_base + 'glance-registry\b',
      "package_options" => ""
    }
    default["glance"]["ssl"]["dir"] = "/etc/pki/tls"
  when "ubuntu"
    default["glance"]["platform"] = {
      "supporting_packages" => ["python-mysqldb", "python-keystone", "curl",
                                "python-glanceclient", "python-warlock"],
      "glance_packages" => ["glance", "python-swift", "python-prettytable", "python-lockfile"],
      "glance_api_service" => "glance-api",
      "glance_api_procmatch" => procmatch_base + 'glance-api\b',
      "glance_registry_service" => "glance-registry",
      "glance_registry_procmatch" => procmatch_base + 'glance-registry\b',
      "package_options" => "-o Dpkg::Options::='--force-confold' -o Dpkg::Options::='--force-confdef'"
    }
    default["glance"]["ssl"]["dir"] = "/etc/ssl"
end

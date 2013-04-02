#
# Cookbook Name:: glance
# Recipe:: api
#
# Copyright 2012, Rackspace US, Inc.
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

# die early if we are trying HA with local file store
glance_api_count = get_realserver_endpoints("glance-api", "glance", "api").length

if node["glance"]["api"]["default_store"] == "file"
  # this is really only needed when glance::replicator is included, however we
  # want to install early on to minimize number of chef-client runs needed
  dsh_group "glance" do
    user "root"
    admin_user "root"
    group "root"
  end

  if glance_api_count == 2
    node.set["glance"]["api"]["notifier_strategy"] = "rabbit"
    include_recipe "glance::replicator"
  elsif glance_api_count > 2
    Chef::Application.fatal! "Local file store not supported with multiple glance-api nodes>
    Change file store to 'swift' or 'cloudfiles' or remove additional glance-api nodes"
  end
end

include_recipe "glance::glance-rsyslog"
include_recipe "monitoring"

if not node['package_component'].nil?
    release = node['package_component']
else
    release = "folsom"
end

platform_options = node["glance"]["platform"][release]

package "curl" do
  action :install
end

platform_options["mysql_python_packages"].each do |pkg|
  package pkg do
    action :install
  end
end

package "python-keystone" do
    action :install
end

platform_options["glance_packages"].each do |pkg|
  package pkg do
    action :install
    options platform_options["package_overrides"]
  end
end

service "glance-api" do
  service_name platform_options["glance_api_service"]
  supports :status => true, :restart => true
  action :enable
end

unless node.run_list.expand(node.chef_environment).recipes.include?("glance::registry")
  service "glance-registry" do
    service_name platform_options["glance_registry_service"]
    supports :status => true, :restart => true
    action [ :stop, :disable ]
  end
end

monitoring_procmon "glance-api" do
  sname = platform_options["glance_api_service"]
  pname = platform_options["glance_api_process_name"]
  process_name pname
  script_name sname
end

monitoring_metric "glance-api-proc" do
  type "proc"
  proc_name "glance-api"
  proc_regex platform_options["glance_api_service"]

  alarms(:failure_min => 2.0)
end

directory "/etc/glance" do
  action :create
  group "glance"
  owner "glance"
  mode "0700"
end

# FIXME: seems like misfeature
template "/etc/glance/policy.json" do
  source "policy.json.erb"
  owner "glance"
  group "glance"
  mode "0600"
  notifies :restart, resources(:service => "glance-api"), :immediately
  not_if do
    File.exists?("/etc/glance/policy.json")
  end
end

rabbit_info = get_access_endpoint("rabbitmq-server", "rabbitmq", "queue")
mysql_info = get_access_endpoint("mysql-master", "mysql", "db")

ks_admin_endpoint = get_access_endpoint("keystone-api", "keystone", "admin-api")
ks_service_endpoint = get_access_endpoint("keystone-api", "keystone","service-api")
keystone = get_settings_by_role("keystone", "keystone")
glance = get_settings_by_role("glance-api", "glance")
settings = get_settings_by_role("glance-setup", "glance")
registry_endpoint = get_access_endpoint("glance-registry", "glance", "registry")
api_endpoint = get_bind_endpoint("glance", "api")

# Possible combinations of options here
# - default_store=file
#     * no other options required
# - default_store=swift
#     * if swift_store_auth_address is not defined
#         - default to local swift
#     * else if swift_store_auth_address is defined
#         - get swift_store_auth_address, swift_store_user, swift_store_key, and
#           swift_store_auth_version from the node attributes and use them to connect
#           to the swift compatible API service running elsewhere - possibly
#           Rackspace Cloud Files.
if glance["api"]["swift_store_auth_address"].nil?
    swift_store_auth_address="http://#{ks_admin_endpoint["host"]}:#{ks_service_endpoint["port"]}/v2.0"
    swift_store_user="#{glance["service_tenant_name"]}:#{glance["service_user"]}"
    swift_store_key=settings["service_pass"]
    swift_store_auth_version=2
else
    swift_store_auth_address=settings["api"]["swift_store_auth_address"]
    swift_store_user=settings["api"]["swift_store_user"]
    swift_store_key=settings["api"]["swift_store_key"]
    swift_store_auth_version=settings["api"]["swift_store_auth_version"]
end

# Only use the glance image cacher if we aren't using file for our backing store.
if glance["api"]["default_store"]=="file"
  glance_flavor="keystone"
else
  glance_flavor="keystone+cachemanagement"
end

template "/etc/glance/logging.conf" do
  source "glance-logging.conf.erb"
  owner "glance"
  group "glance"
  mode "0640"
  variables(
    "use_syslog" => node["glance"]["syslog"]["use"],
    "log_facility" => node["glance"]["syslog"]["facility"]
  )
  notifies :restart, resources(:service => "glance-api"), :delayed
end

template "/etc/glance/glance-api.conf" do
  source "#{release}/glance-api.conf.erb"
  owner "glance"
  group "glance"
  mode "0600"
  variables(
    "api_bind_address" => api_endpoint["host"],
    "api_bind_port" => api_endpoint["port"],
    "registry_ip_address" => registry_endpoint["host"],
    "registry_port" => registry_endpoint["port"],
    "use_syslog" => node["glance"]["syslog"]["use"],
    "log_facility" => node["glance"]["syslog"]["facility"],
    "rabbit_ipaddress" => rabbit_info["host"],
    "rabbit_port" => rabbit_info["port"],
    "default_store" => glance["api"]["default_store"],
    "notifier_strategy" => glance["api"]["notifier_strategy"],
    "glance_flavor" => glance_flavor,
    "swift_store_key" => swift_store_key,
    "swift_store_user" => swift_store_user,
    "swift_store_auth_address" => swift_store_auth_address,
    "swift_store_auth_version" => swift_store_auth_version,
    "swift_large_object_size" => glance["api"]["swift"]["store_large_object_size"],
    "swift_large_object_chunk_size" => glance["api"]["swift"]["store_large_object_chunk_size"],
    "swift_store_container" => glance["api"]["swift"]["store_container"],
    "db_ip_address" => mysql_info["host"],
    "db_user" => settings["db"]["username"],
    "db_password" => settings["db"]["password"],
    "db_name" => settings["db"]["name"]
  )
  notifies :restart, resources(:service => "glance-api"), :immediately
end

template "/etc/glance/glance-api-paste.ini" do
  source "#{release}/glance-api-paste.ini.erb"
  owner "glance"
  group "glance"
  mode "0600"
  variables(
    "keystone_api_ipaddress" => ks_admin_endpoint["host"],
    "keystone_service_port" => ks_service_endpoint["port"],
    "keystone_admin_port" => ks_admin_endpoint["port"],
    "keystone_admin_token" => keystone["admin_token"],
    "service_tenant_name" => settings["service_tenant_name"],
    "service_user" => settings["service_user"],
    "service_pass" => settings["service_pass"]
  )
  notifies :restart, resources(:service => "glance-api"), :immediately
end

template "/etc/glance/glance-cache.conf" do
  source "glance-cache.conf.erb"
  owner "glance"
  group "glance"
  mode "0600"
  variables(
    "registry_ip_address" => registry_endpoint["host"],
    "registry_port" => registry_endpoint["port"],
    "use_syslog" => node["glance"]["syslog"]["use"],
    "log_facility" => node["glance"]["syslog"]["facility"],
    "image_cache_max_size" => node["glance"]["api"]["cache"]["image_cache_max_size"]
  )
  notifies :restart, resources(:service => "glance-api"), :delayed
end

template "/etc/glance/glance-cache-paste.ini" do
  source "glance-cache-paste.ini.erb"
  owner "glance"
  group "glance"
  mode "0600"
  notifies :restart, resources(:service => "glance-api"), :delayed
end

template "/etc/glance/glance-scrubber.conf" do
  source "glance-scrubber.conf.erb"
  owner "glance"
  group "glance"
  mode "0600"
  variables(
    "registry_ip_address" => registry_endpoint["host"],
    "registry_port" => registry_endpoint["port"]
  )
end

# Configure glance-cache-pruner to run every 30 minutes
cron "glance-cache-pruner" do
  minute "*/30"
  command "/usr/bin/glance-cache-pruner"
end

# Configure glance-cache-cleaner to run at 00:01 everyday
cron "glance-cache-cleaner" do
  minute "01"
  hour "00"
  command "/usr/bin/glance-cache-cleaner"
end

template "/etc/glance/glance-scrubber-paste.ini" do
  source "glance-scrubber-paste.ini.erb"
  owner "glance"
  group "glance"
  mode "0600"
end

# Register Image Service
keystone_service "Register Image Service" do
  auth_host ks_admin_endpoint["host"]
  auth_port ks_admin_endpoint["port"]
  auth_protocol ks_admin_endpoint["scheme"]
  api_ver ks_admin_endpoint["path"]
  auth_token keystone["admin_token"]
  service_name "glance"
  service_type "image"
  service_description "Glance Image Service"
  action :create
end

# Register Image Endpoint
keystone_endpoint "Register Image Endpoint" do
  auth_host ks_admin_endpoint["host"]
  auth_port ks_admin_endpoint["port"]
  auth_protocol ks_admin_endpoint["scheme"]
  api_ver ks_admin_endpoint["path"]
  auth_token keystone["admin_token"]
  service_type "image"
  endpoint_region "RegionOne"
  endpoint_adminurl api_endpoint["uri"]
  endpoint_internalurl api_endpoint["uri"]
  endpoint_publicurl api_endpoint["uri"]
  action :create
end

if node["glance"]["image_upload"]
  node["glance"]["images"].each do |img|
    Chef::Log.info("Checking to see if #{img.to_s}-image should be uploaded.")

    keystone_admin_user = keystone["admin_user"]
    keystone_admin_password = keystone["users"][keystone_admin_user]["password"]
    keystone_tenant = keystone["users"][keystone_admin_user]["default_tenant"]

    glance_image "Image setup for #{img.to_s}" do
      image_url node["glance"]["image"][img.to_sym]
      image_name img
      keystone_user keystone_admin_user
      keystone_pass keystone_admin_password
      keystone_tenant keystone_tenant
      keystone_uri ks_admin_endpoint["uri"]
      action :upload
    end

  end
end

# set up glance api monitoring (bytes/objects per tentant, etc)
monitoring_metric "glance-api" do
  type "pyscript"
  script "glance_plugin.py"
  options("Username" => node["glance"]["service_user"],
          "Password" => node["glance"]["service_pass"],
          "TenantName" => node["glance"]["service_tenant_name"],
          "AuthURL" => ks_service_endpoint["uri"] )
end

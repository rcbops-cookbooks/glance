#
# Cookbook Name:: glance
# Recipe:: glance-common
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
#
#

# install common packages
platform_options = node["glance"]["platform"]

pkgs = platform_options["glance_packages"] +
  platform_options["supporting_packages"]

# install (or upgrade) glance packages.  We execute 'glance-manage db_sync'
# on package transition but the execute block only runs when do_package_upgrades
# is set to true
pkgs.each do |pkg|
  package pkg do
    action node["osops"]["do_package_upgrades"] == true ? :upgrade : :install
    options platform_options["package_overrides"]
    notifies :run, "execute[glance-manage db_sync]", :delayed
  end
end

directory "/etc/glance" do
  action :create
  group "glance"
  owner "glance"
  mode "0700"
end

# Search for rabbit endpoint info
rabbit_info = get_access_endpoint("rabbitmq-server", "rabbitmq", "queue")
# Search for mysql endpoint info
mysql_info = get_access_endpoint("mysql-master", "mysql", "db")
# Search for keystone endpoint info
ks_api_role = "keystone-api"
ks_ns = "keystone"
ks_admin_endpoint = get_access_endpoint(ks_api_role, ks_ns, "admin-api")
ks_service_endpoint = get_access_endpoint(ks_api_role, ks_ns, "service-api")
# Get settings from role[keystone-setup]
keystone = get_settings_by_role("keystone-setup", "keystone")
# Get settings from role[glance-api]
glance = get_settings_by_role("glance-api", "glance")
# Get settings from role[glance-setup]
settings = get_settings_by_role("glance-setup", "glance")
# Get api endpoint bind info
api_bind = get_bind_endpoint("glance", "api")
# Get registry endpoint bind info
registry_bind = get_bind_endpoint("glance", "registry")
# Search for glance-registry endpoint info
registry_endpoint = get_access_endpoint("glance-registry", "glance", "registry")

# Only use the glance image cacher if we aren't using file for our backing store.
if glance["api"]["default_store"]=="file"
  glance_flavor="keystone"
else
  glance_flavor="keystone+cachemanagement"
end

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
  swift_store_auth_address="http://#{ks_admin_endpoint["host"]}:#{ks_service_endpoint["port"]}#{ks_service_endpoint["path"]}"
  swift_store_user="#{glance["service_tenant_name"]}:#{glance["service_user"]}"
  swift_store_key=settings["service_pass"]
  swift_store_auth_version=2
else
  swift_store_auth_address=settings["api"]["swift_store_auth_address"]
  swift_store_user=settings["api"]["swift_store_user"]
  swift_store_key=settings["api"]["swift_store_key"]
  swift_store_auth_version=settings["api"]["swift_store_auth_version"]
end

template "/etc/glance/glance-registry.conf" do
  source "glance-registry.conf.erb"
  owner "glance"
  group "glance"
  mode "0600"
  variables(
    "registry_bind_address" => registry_bind["host"],
    "registry_port" => registry_bind["port"],
    "db_ip_address" => mysql_info["host"],
    "db_user" => node["glance"]["db"]["username"],
    "db_password" => node["glance"]["db"]["password"],
    "db_name" => node["glance"]["db"]["name"],
    "keystone_api_ipaddress" => ks_admin_endpoint["host"],
    "keystone_service_port" => ks_service_endpoint["port"],
    "keystone_admin_port" => ks_admin_endpoint["port"],
    "service_tenant_name" => node["glance"]["service_tenant_name"],
    "service_user" => node["glance"]["service_user"],
    "service_pass" => node["glance"]["service_pass"]
  )
end

template "/etc/glance/glance-registry-paste.ini" do
  source "glance-registry-paste.ini.erb"
  owner "glance"
  group "glance"
  mode "0600"
  variables(
    "keystone_api_ipaddress" => ks_admin_endpoint["host"],
    "keystone_service_port" => ks_service_endpoint["port"],
    "keystone_admin_port" => ks_admin_endpoint["port"],
    "service_tenant_name" => node["glance"]["service_tenant_name"],
    "service_user" => node["glance"]["service_user"],
    "service_pass" => node["glance"]["service_pass"]
  )
end

template "/etc/glance/glance-api.conf" do
  source "glance-api.conf.erb"
  owner "glance"
  group "glance"
  mode "0600"
  variables(
    "api_bind_address" => api_bind["host"],
    "api_bind_port" => api_bind["port"],
    "registry_ip_address" => registry_endpoint["host"],
    "registry_port" => registry_endpoint["port"],
    "rabbit_ipaddress" => rabbit_info["host"],
    "rabbit_port" => rabbit_info["port"],
    "default_store" => glance["api"]["default_store"],
    "notifier_strategy" => glance["api"]["notifier_strategy"],
    "notification_topic" => glance["api"]["notification_topic"],
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
    "db_name" => settings["db"]["name"],
    "keystone_api_ipaddress" => ks_admin_endpoint["host"],
    "keystone_service_port" => ks_service_endpoint["port"],
    "keystone_admin_port" => ks_admin_endpoint["port"],
    "keystone_admin_token" => keystone["admin_token"],
    "service_tenant_name" => settings["service_tenant_name"],
    "service_user" => settings["service_user"],
    "service_pass" => settings["service_pass"],
    "glance_workers" => glance["api"]["workers"]
  )
end

template "/etc/glance/glance-api-paste.ini" do
  source "glance-api-paste.ini.erb"
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
end

#
# Cookbook Name:: glance
# Recipe:: api
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

include_recipe "glance::glance-common"

platform_options = node["glance"]["platform"]

api_endpoint = get_bind_endpoint("glance", "api")
internal_api_endpoint = get_bind_endpoint("glance", "internal-api")
admin_api_endpoint = get_bind_endpoint("glance", "admin-api")

if api_endpoint["scheme"] == "https"
  include_recipe "glance::api-ssl"
else
  if node.recipe?"apache2"
    apache_site "openstack-glance-api" do
      enable false
      notifies :restart, "service[apache2]", :immediately
    end
  end
end

service "glance-api" do
  service_name platform_options["glance_api_service"]
  supports :status => true, :restart => true
  unless api_endpoint["scheme"] == "https"
    action :enable
    subscribes :restart, "template[/etc/glance/glance-api.conf]", :immediately
    subscribes :restart,
      "template[/etc/glance/glance-api-paste.ini]",
      :immediately
  else
    action [ :disable, :stop ]
  end
end

# glance-registry gets pulled in when we install glance-api.  Unless we are
# meant to be a glance-registry node too, make sure it's stopped
service "glance-registry" do
  service_name platform_options["glance_registry_service"]
  supports :status => true, :restart => true
  action [:stop, :disable]
  not_if {
    node.run_list.expand(
      node.chef_environment).recipes.include?("glance::registry")
  }
end

# Search for keystone endpoint info
ks_api_role = "keystone-api"
ks_ns = "keystone"
ks_admin_endpoint = get_access_endpoint(ks_api_role, ks_ns, "admin-api")

# Get settings from role[keystone-setup]
keystone = get_settings_by_role("keystone-setup", "keystone")

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

# are we using rbd to store our images?
if node['glance']['api']['default_store'] == "rbd" && rcb_safe_deref(node, "ceph.config.fsid")

  include_recipe "ceph::repo"
  include_recipe "ceph"
  include_recipe "ceph::conf"

  rbd_store_user = node['glance']['api']['rbd']['rbd_store_user']
  rbd_store_pool = node['glance']['api']['rbd']['rbd_store_pool']
  rbd_store_pool_pg_num = node['glance']['api']['rbd']['rbd_store_pool_pg_num']

  # ruby block needed to prevent this failing at compile time.
  ruby_block 'configure rbd for glance' do
    block do

      rbd_user_keyring_file="/etc/ceph/ceph.client.#{rbd_store_user}.keyring"
      mon_keyring_file = "#{Chef::Config[:file_cache_path]}/#{node['hostname']}.mon.keyring"

      # create the admin client keyring
      unless File.exist?(rbd_user_keyring_file)

        monitor_secret = if node['ceph']['encrypted_data_bags']
          secret = Chef::EncryptedDataBagItem.load_secret(node["ceph"]["mon"]["secret_file"])
          Chef::EncryptedDataBagItem.load("ceph", "mon", secret)["secret"]
        else
          node["ceph"]["monitor-secret"]
        end

        # create the mon keyring temporarily
        Mixlib::ShellOut.new("ceph-authtool '#{mon_keyring_file}' --create-keyring --name='mon.' --add-key='#{monitor_secret}' --cap mon 'allow *'").run_command

        # get (or create) the glance rbd user in cephx
        Mixlib::ShellOut.new("ceph auth get-or-create client.#{rbd_store_user} --name='mon.' --keyring='#{mon_keyring_file}' ").run_command
        Mixlib::ShellOut.new("ceph auth caps client.#{rbd_store_user} --name='mon.' --keyring='#{mon_keyring_file}'  mon 'allow r' osd 'allow class-read object_prefix rbd_children, allow rwx pool=#{rbd_store_pool}'").run_command

        # get the full client, with caps, and write it out to file
        # TODO(mancdaz): discover ceph config dir rather than hardcode
        rbd_user_keyring = Mixlib::ShellOut.new("ceph auth get client.#{rbd_store_user} --name='mon.' --keyring='#{mon_keyring_file}' ").run_command.stdout
        f = File.open("/etc/ceph/ceph.client.#{rbd_store_user}.keyring", 'w')
        f.write(rbd_user_keyring)
        f.close

        # create the pool with provided pg_num
        Mixlib::ShellOut.new("ceph osd pool create #{rbd_store_pool} #{rbd_store_pool_pg_num} #{rbd_store_pool_pg_num} --name='mon.' --keyring='#{mon_keyring_file}' ").run_command

        # remove the temporary mon keyring
        File.delete(mon_keyring_file)
      end
    end
  end
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
  endpoint_adminurl admin_api_endpoint["uri"]
  endpoint_internalurl internal_api_endpoint["uri"]
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
      scheme api_endpoint["scheme"]
      action :upload
    end
  end
end

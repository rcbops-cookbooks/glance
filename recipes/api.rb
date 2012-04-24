#
# Cookbook Name:: glance
# Recipe:: api
#
# Copyright 2009, Rackspace Hosting, Inc.
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

# Distribution specific settings go here
if platform?(%w{fedora})
  # Fedora
  mysql_python_package = "MySQL-python"
  glance_package = "openstack-glance"
  glance_api_service = "openstack-glance-api"
  glance_package_options = ""
else
  # All Others (right now Debian and Ubuntu)
  mysql_python_package="python-mysqldb"
  glance_package = "glance"
  glance_api_service = "glance-api"
  glance_package_options = "-o Dpkg::Options::='--force-confold' --force-yes"
end

package "curl" do
  action :upgrade
end

package "python-keystone" do
    action :install
end

package glance_package do
  action :upgrade
end

service glance_api_service do
  supports :status => true, :restart => true
  action :enable
end

directory "/etc/glance" do
  action :create
  group "glance"
  owner "glance"
  mode "0700"
  not_if do
    File.exists?("/etc/glance")
  end
end

template "/etc/glance/policy.json" do
  source "policy.json.erb"
  owner "root"
  group "root"
  mode "0644"
  notifies :restart, resources(:service => glance_api_service), :immediately
  not_if do
    File.exists?("/etc/glance/policy.json")
  end
end

if Chef::Config[:solo]
  Chef::Log.warn("This recipe uses search. Chef Solo does not support search.")
else 
  # Lookup mysql ip address
  mysql_server, start, arbitrary_value = Chef::Search::Query.new.search(:node, "roles:mysql-master AND chef_environment:#{node.chef_environment}")
  if mysql_server.length > 0
    Chef::Log.info("mysql: using search")
    db_ip_address = mysql_server[0]['mysql']['bind_address']
  else
    Chef::Log.info("mysql: NOT using search")
    db_ip_address = node['mysql']['bind_address']
  end

  # Lookup rabbit ip address
  rabbit, start, arbitrary_value = Chef::Search::Query.new.search(:node, "roles:rabbitmq-server AND chef_environment:#{node.chef_environment}")
  if rabbit.length > 0
    Chef::Log.info("rabbitmq: using search")
    rabbit_ip_address = rabbit[0]['ipaddress']
  else
    Chef::Log.info("rabbitmq: NOT using search")
    rabbit_ip_address = node['ipaddress']
  end

  # Lookup keystone api ip address
  keystone, start, arbitrary_value = Chef::Search::Query.new.search(:node, "roles:keystone AND chef_environment:#{node.chef_environment}")
  if keystone.length > 0
    Chef::Log.info("keystone: using search")
    keystone_api_ip = keystone[0]['keystone']['api_ipaddress']
    keystone_service_port = keystone[0]['keystone']['service_port']
    keystone_admin_port = keystone[0]['keystone']['admin_port']
    # TODO: keystone_admin_token should be deleted from this file
    keystone_admin_token = keystone[0]['keystone']['admin_token']
  else
    Chef::Log.info("keystone: NOT using search")
    keystone_api_ip = node['keystone']['api_ipaddress']
    keystone_service_port = node['keystone']['service_port']
    keystone_admin_port = node['keystone']['admin_port']
    # TODO: keystone_admin_token should be deleted from this file
    keystone_admin_token = node['keystone']['admin_token']
  end

  # Lookup glance::registry ip address
  registry, start, arbitrary_value = search(:node, "roles:glance-registry AND chef_environment:#{node.chef_environment}")
  if registry.length > 0
    Chef::Log.info("glance::api/registry: using search")
    registry_ip_address = registry[0]["glance"]["registry"]["ip_address"]
    registry_port = registry[0]["glance"]["registry"]["port"]
  else
    Chef::Log.info("glance::api/registry: NOT using search")
    registry_ip_address = node["glance"]["registry"]["ip_address"]
    registry_port = node["glance"]["registry"]["port"]
  end
end

template "/etc/glance/glance-api.conf" do
  source "glance-api.conf.erb"
  owner "root"
  group "root"
  mode "0644"
  variables(
    "api_bind_address" => node["glance"]["api"]["bind_address"],
    "api_bind_port" => node["glance"]["api"]["port"],
    "registry_ip_address" => registry_ip_address,
    "registry_port" => registry_port,
    "rabbit_ipaddress" => rabbit_ip_address
  )
  notifies :restart, resources(:service => glance_api_service), :immediately
end

template "/etc/glance/glance-api-paste.ini" do
  source "glance-api-paste.ini.erb"
  owner "root"
  group "root"
  mode "0644"
  variables(
    "keystone_api_ipaddress" => keystone_api_ip,
    "keystone_service_port" => keystone_service_port,
    "keystone_admin_port" => keystone_admin_port,
    "keystone_admin_token" => keystone_admin_token,
    "service_tenant_name" => node["glance"]["service_tenant_name"],
    "service_user" => node["glance"]["service_user"],
    "service_pass" => node["glance"]["service_pass"]
  )
  notifies :restart, resources(:service => glance_api_service), :immediately
end

template "/etc/glance/glance-scrubber.conf" do
  source "glance-scrubber.conf.erb"
  owner "root"
  group "root"
  mode "0644"
  variables(
    "registry_ip_address" => registry_ip_address,
    "registry_port" => registry_port
  )
end

template "/etc/glance/glance-scrubber-paste.ini" do
  source "glance-scrubber-paste.ini.erb"
  owner "root"
  group "root"
  mode "0644"
end

# Register Image Service
keystone_register "Register Image Service" do
  auth_host keystone_api_ip
  auth_port keystone_admin_port
  auth_protocol "http"
  api_ver "/v2.0"
  auth_token keystone_admin_token
  service_name "glance"
  service_type "image"
  service_description "Glance Image Service"
  action :create_service
end

# Register Image Endpoint
keystone_register "Register Image Endpoint" do
  auth_host keystone_api_ip
  auth_port keystone_admin_port
  auth_protocol "http"
  api_ver "/v2.0"
  auth_token keystone_admin_token
  service_type "image"
  endpoint_region "RegionOne"
  endpoint_adminurl node["glance"]["api"]["adminURL"]
  endpoint_internalurl node["glance"]["api"]["internalURL"]
  endpoint_publicurl node["glance"]["api"]["publicURL"]
  action :create_endpoint
end

if node["glance"]["image_upload"]
  keystone_auth_url = "http://#{keystone_api_ip}:#{keystone_admin_port}/v2.0"

  # TODO(breu): the environment needs to be derived from a search
  node["glance"]["images"].each do |img|
    bash "default image setup for #{img.to_s}" do
      cwd "/tmp"
      user "root"
      environment ({"OS_USERNAME" => "admin",
                    "OS_PASSWORD" => "secrete",
                    "OS_TENANT_NAME" => "admin",
                    "OS_AUTH_URL" => keystone_auth_url})
      code <<-EOH
        set -e
        set -x
        mkdir -p images

        curl #{node["glance"]["image"][img.to_sym]} | tar -zx -C images/
        image_name=$(basename #{node["glance"]["image"][img]} .tar.gz)

        image_name=${image_name%-multinic}

        kernel_file=$(ls images/*vmlinuz-virtual | head -n1)
        if [ ${#kernel_file} -eq 0 ]; then
           kernel_file=$(ls images/*vmlinuz | head -n1)
        fi

        ramdisk=$(ls images/*-initrd | head -n1)
        if [ ${#ramdisk} -eq 0 ]; then
            ramdisk=$(ls images/*-loader | head -n1)
        fi

        kernel=$(ls images/*.img | head -n1)

        kid=$(glance --silent-upload add name="${image_name}-kernel" disk_format=aki container_format=aki < ${kernel_file} | cut -d: -f2 | sed 's/ //')
        rid=$(glance --silent-upload add name="${image_name}-initrd" disk_format=ari container_format=ari < ${ramdisk} | cut -d: -f2 | sed 's/ //')
        glance --silent-upload add name="#{img.to_s}-image" disk_format=ami container_format=ami kernel_id=$kid ramdisk_id=$rid < ${kernel}
      EOH
      not_if "glance index | grep #{img.to_s}-image"
    end
  end
end

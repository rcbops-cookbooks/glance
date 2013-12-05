#
# Cookbook Name:: glance
# Recipe:: registry-ssl
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

include_recipe "apache2"
include_recipe "apache2::mod_wsgi"
include_recipe "apache2::mod_rewrite"
include_recipe "osops-utils::mod_ssl"
include_recipe "osops-utils::ssl_packages"

# Remove monit file if it exists
if node.attribute?"monit"
  if node["monit"].attribute?"conf.d_dir"
    file "#{node['monit']['conf.d_dir']}/glance-registry.conf" do
      action :delete
      notifies :reload, "service[monit]", :immediately
    end
  end
end

# setup cert files
case node["platform"]
when "ubuntu", "debian"
  grp = "ssl-cert"
else
  grp = "root"
end

cookbook_file "#{node["glance"]["ssl"]["dir"]}/certs/#{node["glance"]["services"]["registry"]["cert_file"]}" do
  source "glance_registry.pem"
  mode 0644
  owner "root"
  group "root"
end

cookbook_file "#{node["glance"]["ssl"]["dir"]}/private/#{node["glance"]["services"]["registry"]["key_file"]}" do
  source "glance_registry.key"
  mode 0644
  owner "root"
  group grp
end

unless node["glance"]["services"]["registry"]["chain_file"].nil?
  cookbook_file "#{node["glance"]["ssl"]["dir"]}/certs/#{node["glance"]["services"]["registry"]["chain_file"]}" do
    source node["glance"]["services"]["registry"]["chain_file"]
    mode 0644
    owner "root"
    group "root"
  end
end

# setup wsgi file

directory "#{node["apache"]["dir"]}/wsgi" do
  action :create
  owner "root"
  group "root"
  mode "0755"
end

cookbook_file "#{node["apache"]["dir"]}/wsgi/#{node["glance"]["services"]["registry"]["wsgi_file"]}" do
  source "registry_modwsgi.py"
  mode 0644
  owner "root"
  group "root"
end

glance_registry_bind = get_bind_endpoint("glance", "registry")

unless node["glance"]["services"]["registry"].attribute?"cert_override"
  cert_location = "#{node["glance"]["ssl"]["dir"]}/certs/#{node["glance"]["services"]["registry"]["cert_file"]}"
else
  cert_location = node["glance"]["services"]["registry"]["cert_override"]
end

unless node["glance"]["services"]["registry"].attribute?"key_override"
  key_location = "#{node["glance"]["ssl"]["dir"]}/private/#{node["glance"]["services"]["registry"]["key_file"]}"
else
  key_location = node["glance"]["services"]["registry"]["key_override"]
end

unless node["glance"]["services"]["registry"]["chain_file"].nil?
  chain_location = "#{node["glance"]["ssl"]["dir"]}/certs/#{node["glance"]["services"]["registry"]["chain_file"]}"
else
  chain_location = "donotset"
end

template value_for_platform(
  ["ubuntu", "debian", "fedora"] => {
    "default" => "#{node["apache"]["dir"]}/sites-available/openstack-glance-registry"
  },
  "fedora" => {
    "default" => "#{node["apache"]["dir"]}/vhost.d/openstack-glance-registry"
  },
  ["redhat", "centos"] => {
    "default" => "#{node["apache"]["dir"]}/conf.d/openstack-glance-registry"
  },
  "default" => {
    "default" => "#{node["apache"]["dir"]}/openstack-glance-registry"
  }
) do
  source "modwsgi_vhost.erb"
  owner "root"
  group "root"
  mode "0644"
  variables(
    :listen_ip => glance_registry_bind["host"],
    :service_port => glance_registry_bind["port"],
    :cert_file => cert_location,
    :key_file => key_location,
    :chain_file => chain_location,
    :wsgi_file  => "#{node["apache"]["dir"]}/wsgi/#{node["glance"]["services"]["registry"]["wsgi_file"]}",
    :proc_group => "glance-registry",
    :log_file => "/var/log/glance/registry-ssl.log"
  )
  notifies :reload, "service[apache2]", :delayed
end

apache_site "openstack-glance-registry" do
  enable true
  notifies :restart, "service[apache2]", :immediately
end

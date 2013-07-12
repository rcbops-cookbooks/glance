#
# Cookbook Name:: glance
# Recipe:: api-ssl
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

include_recipe "apache2"
include_recipe "apache2::mod_wsgi"
include_recipe "apache2::mod_rewrite"
include_recipe "osops-utils::mod_ssl"
include_recipe "osops-utils::ssl_packages"

# Remove monit file if it exists
if node.attribute?"monit"
  if node["monit"].attribute?"conf.d_dir"
    file "#{node['monit']['conf.d_dir']}/glance-api.conf" do
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

cookbook_file "#{node["glance"]["ssl"]["dir"]}/certs/#{node["glance"]["services"]["api"]["cert_file"]}" do
  source "glance_api.pem"
  mode 0644
  owner "root"
  group "root"
  notifies :run, "execute[restore-selinux-context]", :immediately
end

cookbook_file "#{node["glance"]["ssl"]["dir"]}/private/#{node["glance"]["services"]["api"]["key_file"]}" do
  source "glance_api.key"
  mode 0644
  owner "root"
  group grp
  notifies :run, "execute[restore-selinux-context]", :immediately
end

# setup wsgi file

directory "#{node["apache"]["dir"]}/wsgi" do
  action :create
  owner "root"
  group "root"
  mode "0755"
end

cookbook_file "#{node["apache"]["dir"]}/wsgi/#{node["glance"]["services"]["api"]["wsgi_file"]}" do
  source "api_modwsgi.py"
  mode 0644
  owner "root"
  group "root"
end

glance_api_bind = get_bind_endpoint("glance", "api")

template value_for_platform(
  ["ubuntu", "debian", "fedora"] => {
    "default" => "#{node["apache"]["dir"]}/sites-available/openstack-glance-api"
  },
  "fedora" => {
    "default" => "#{node["apache"]["dir"]}/vhost.d/openstack-glance-api"
  },
  ["redhat", "centos"] => {
    "default" => "#{node["apache"]["dir"]}/conf.d/openstack-glance-api"
  },
  "default" => {
    "default" => "#{node["apache"]["dir"]}/openstack-glance-api"
  }
) do
  source "modwsgi_vhost.erb"
  owner "root"
  group "root"
  mode "0644"
  variables(
    :listen_ip => glance_api_bind["host"],
    :service_port => glance_api_bind["port"],
    :cert_file => "#{node["glance"]["ssl"]["dir"]}/certs/#{node["glance"]["services"]["api"]["cert_file"]}",
    :key_file => "#{node["glance"]["ssl"]["dir"]}/private/#{node["glance"]["services"]["api"]["key_file"]}",
    :wsgi_file  => "#{node["apache"]["dir"]}/wsgi/#{node["glance"]["services"]["api"]["wsgi_file"]}",
    :proc_group => "glance-api",
    :log_file => "/var/log/glance/glance-api.log"
  )
  notifies :run, "execute[restore-selinux-context]", :immediately
  notifies :reload, "service[apache2]", :delayed
end

apache_site "openstack-glance-api" do
  enable true
  notifies :run, "execute[restore-selinux-context]", :immediately
  notifies :restart, "service[apache2]", :immediately
end

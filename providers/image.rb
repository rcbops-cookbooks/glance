#
# Cookbook Name:: glance
# Provider:: image
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

action :upload do
  @user = new_resource.keystone_user
  @pass = new_resource.keystone_pass
  @tenant = new_resource.keystone_tenant
  @ks_uri = new_resource.keystone_uri

  name = new_resource.image_name
  url = new_resource.image_url
  type = new_resource.image_type
  @insecure = ""
  if new_resource.scheme == "https"
    @insecure = "--insecure"
  end

  if type == "unknown"
    type = _determine_type(url)
  end
  _upload_image(type, name, url)
  new_resource.updated_by_last_action(true)
end

private
def _determine_type(url)
  # Lets do our best to determine the type from the file extension
  case ::File.extname(url)
  when ".gz", ".tgz"
    return "ami"
  when ".qcow2", ".img"
    return "qcow"
  end
end

private
def _upload_image(type, name, url)
  case type
  when 'ami'
    _upload_ami(name, url)
  when 'qcow'
    _upload_qcow(name, url)
  end
end

private
def _upload_qcow(name, url)
  glance_cmd = "glance #{@insecure} --os-username #{@user} --os-password #{@pass} " +
    "--os-tenant-name #{@tenant} --os-auth-url #{@ks_uri}"
  new_name = "#{name}-image"
  c_fmt = "--container-format bare"
  d_fmt = "--disk-format qcow2"
  is_pub = "--is-public True"

  bash "Uploading QCOW2 image #{name}" do
    cwd "/tmp"
    user "root"
    code <<-EOH
        #{glance_cmd} image-create --name "#{new_name}" #{is_pub} #{c_fmt} #{d_fmt} --location "#{url}"
    EOH
    not_if "#{glance_cmd} -f image-list | grep #{new_name.to_s}"
  end
end

private
def _upload_ami(name, url)
  glance_cmd = "glance #{@insecure} -I #{@user} -K #{@pass} -T #{@tenant} -N #{@ks_uri}"
  new_name = "#{name}-image"
  aki_fmt = "container_format=aki disk_format=aki"
  ari_fmt = "container_format=ari disk_format=ari"
  ami_fmt = "container_format=ami disk_format=ami"

  bash "Uploading AMI image #{name}" do
    cwd "/tmp"
    user "root"
    code <<-EOH
        set -x
        mkdir -p images/#{name}
        cd images/#{name}

        curl -L #{url} | tar -zx
        image_name=$(basename #{url} .tar.gz)

        image_name=${image_name%-multinic}

        kernel_file=$(ls *vmlinuz-virtual | head -n1)
        if [ ${#kernel_file} -eq 0 ]; then
            kernel_file=$(ls *vmlinuz | head -n1)
        fi

        ramdisk=$(ls *-initrd | head -n1)
        if [ ${#ramdisk} -eq 0 ]; then
            ramdisk=$(ls *-loader | head -n1)
        fi

        kernel=$(ls *.img | head -n1)

        kid=$(#{glance_cmd} add name="${image_name}-kernel" is_public=true #{aki_fmt} < ${kernel_file} | cut -d: -f2 | sed 's/ //')
        rid=$(#{glance_cmd} add name="${image_name}-initrd" is_public=true #{ari_fmt} < ${ramdisk} | cut -d: -f2 | sed 's/ //')
        #{glance_cmd} add name="#{new_name}" is_public=true #{ami_fmt} kernel_id=$kid ramdisk_id=$rid < ${kernel}
    EOH
    not_if "#{glance_cmd} -f image-list | grep #{new_name.to_s}"
  end
end

#
# Cookbook Name:: bcpc
# Recipe:: ceph-rgw
#
# Copyright 2013, Bloomberg Finance L.P.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

#RGW Stuff
#Note, currently rgw cannot use Keystone to auth S3 requests, only swift, so for the time being we'll have
#to manually provision accounts for RGW in the radosgw-admin tool

include_recipe "bcpc::apache2"

package "radosgw" do
   action :upgrade
end

directory "/var/lib/ceph/radosgw/ceph-radosgw.gateway" do
  owner "root"
  group "root"
  mode 0755
  action :create
  recursive true
end

file "/var/lib/ceph/radosgw/ceph-radosgw.gateway/done" do
  owner "root"
  group "root"
  mode "0644"
  action :touch
end

bash "write-client-radosgw-key" do
    code <<-EOH
        RGW_KEY=`ceph --name client.admin --keyring /etc/ceph/ceph.client.admin.keyring auth get-or-create-key client.radosgw.gateway osd 'allow rwx' mon 'allow rw'`
        ceph-authtool "/var/lib/ceph/radosgw/ceph-radosgw.gateway/keyring" \
            --create-keyring \
            --name=client.radosgw.gateway \
            --add-key="$RGW_KEY"
    EOH
    not_if "test -f /var/lib/ceph/radosgw/ceph-radosgw.gateway/keyring && chmod 644 /var/lib/ceph/radosgw/ceph-radosgw.gateway/keyring"
end

bash "pre-alloc-rgwspools" do
    flags '-x'
    pools = %w{ .rgw.buckets .log .rgw .rgw.control .users.uid .users.email .users .usage .intent-log }
    code pools.map { |pool|
    "ceph osd pool create #{pool} #{get_num_pgs(node[:bcpc][:rgw_pool_multiplier][pool])};ceph osd pool set #{pool} size #{node[:bcpc][:ceph_s3_replica_count]}"
    }.join("\n")
    not_if "rados df | grep .rgw.buckets"
end

file "/var/www/s3gw.fcgi" do
    owner "root"
    group "root"
    mode 0755
    content "#!/bin/sh\n exec /usr/bin/radosgw -c /etc/ceph/ceph.conf -n client.radosgw.gateway"
end

template "/etc/apache2/sites-available/radosgw" do
    source "apache-radosgw.conf.erb"
    owner "root"
    group "root"
    mode 00644
    notifies :restart, "service[apache2]", :delayed
end

bash "apache-enable-radosgw" do
    user "root"
    code "a2ensite radosgw"
    not_if "test -r /etc/apache2/sites-enabled/radosgw"
    notifies :restart, "service[apache2]", :immediately
end

execute "radosgw-all-starter" do
    command "start radosgw-all-starter"
end

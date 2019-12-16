# Include the common recipe
include_recipe 'olyn_percona::common'

# Load information about the current server from the servers data bag
local_server = data_bag_item('servers', node[:hostname])

# Load the mysql root user data bag item
percona_root_user = data_bag_item('percona_users', node[:olyn_percona][:users][:root][:data_bag_item])

# TODO: As of Chef 15, this response file is generated plain text and shown inline - has sensitive info
# Install the base percona package unattended
package node[:olyn_percona][:packages][:base] do
  options '-q -y'
  response_file node[:olyn_percona][:seed_file]
  response_file_variables(
    package:       node[:olyn_percona][:packages][:server],
    root_password: percona_root_user[:password]
  )
  action :install
end

# One time lock file for percona member init (stops mysql on non-bootsrappers)
file "#{Chef::Config[:file_cache_path]}/percona.member.init.lock" do
  action :create_if_missing
  only_if { !local_server[:options][:percona][:bootstrapper] }
  notifies :stop, 'service[mysql]', :immediately
  notifies :start, 'service[mysql]', :delayed
end

# An array of cluster IPs built from the server data bag
cluster_ips = []

# Loop through each server in the data bag to find cluster IPs
data_bag('servers').each do |server_item_name|

  # Load the data bag item
  server = data_bag_item('servers', server_item_name)

  # Skip this server if it isn't in the cluster or is the local server
  next if server[:cluster] != local_server[:cluster] || !local_server[:options][:percona][:member]

  # Add the IP to the cluster array
  cluster_ips << server[:ip]

end

# Percona WSREP config file
template '/etc/mysql/percona-xtradb-cluster.conf.d/wsrep.cnf' do
  source 'wsrep.cnf.erb'
  mode 0644
  owner 'root'
  group 'root'
  variables(
    local_server: local_server,
    cluster_ips:  cluster_ips,
    sst_user:     data_bag_item('percona_users', node[:olyn_percona][:users][:sst][:data_bag_item]),
    certificates: { server: data_bag_item('ssl_certificates', node[:olyn_percona][:ssl_certificates][:server_data_bag_item]),
                    client: data_bag_item('ssl_certificates', node[:olyn_percona][:ssl_certificates][:client_data_bag_item]) },
    ports:        { group: data_bag_item('ports', node[:olyn_percona][:ports][:group][:data_bag_item]),
                    mysql: data_bag_item('ports', node[:olyn_percona][:ports][:mysql][:data_bag_item]),
                    sst:   data_bag_item('ports', node[:olyn_percona][:ports][:sst][:data_bag_item]),
                    ist:   data_bag_item('ports', node[:olyn_percona][:ports][:ist][:data_bag_item]) }
  )
  sensitive true
end

# MySQL client config file
template '/etc/mysql/percona-xtradb-cluster.conf.d/client.cnf' do
  source 'client.cnf.erb'
  mode 0644
  owner 'root'
  group 'root'
  variables(
    certificates: { server: data_bag_item('ssl_certificates', node[:olyn_percona][:ssl_certificates][:server_data_bag_item]),
                    client: data_bag_item('ssl_certificates', node[:olyn_percona][:ssl_certificates][:client_data_bag_item]) },
    ports:        {
      mysql: data_bag_item('ports', node[:olyn_percona][:ports][:mysql][:data_bag_item])
    }
  )
end
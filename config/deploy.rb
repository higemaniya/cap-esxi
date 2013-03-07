# set :host, "root@somewhere"

require "json"
require "erb"

set :vmname, "test" unless exists? :vmname

role :host, 'root@esxi'
set :config, JSON.parse( File::open("data/config.json").read )

_vminfo = nil 
set (:vminfo) { _vminfo }

namespace :esxi do
	task :getallvms do
		run "vim-cmd vmsvc/getallvms | sort -n" do |channel, stream, data|
			puts data
		end
	end

	task :getvminfo do
		run "vim-cmd vmsvc/getallvms" do |channel, stream, data|
			allvms = data.split("\n").grep(/^(\d+)\s+(.*?)\s+(\[.*?\].*?\.vmx)\s+(.*Guest)\s+(vmx-\d+)\s*(.*?)?\s*$/) {
				{ :vmid => $1, :name => $2, :file => $3, :guestos => $4, :version => $5, :annotation => $6 }
			}
			allvms.each { |x|
				_vminfo = x if x[:name] == vmname
			}
		end
	end

	task :showvm do
		getvminfo
		puts vminfo
	end

	task :lsvmfiles do
		getvminfo
		path = File.dirname(vminfo[:file].gsub(/\[(.*?)\]\s*/, '/vmfs/volumes/\1/'))
		run "ls -l #{path}"
	end

	task :destroyvm do
		getvminfo
		run "vim-cmd vmsvc/destroy #{vminfo[:vmid]}"
	end

	task :createvm do
		vm = JSON.parse( File::open("data/vm.json").read )[vmname]
		puts vm
		getvminfo
		path = vm["path"].gsub(/\[(.*?)\]\s*/, '/vmfs/volumes/\1/')
		vmx = "#{path}/#{vmname}.vmx"
		vmdk = "#{path}/#{vmname}.vmdk"
		puts vmx
		erb = ERB.new(IO.read("data/template.vmx"), nil, "%")
		File.open("data/deploy.vmx", "w") do |f|
			f.write erb.result(binding)
		end
		run "mkdir -p #{path}"
		upload("data/deploy.vmx", "#{vmx}", :via => :scp)
		run	"vmkfstools -c #{vm["disksize"]} -d zeroedthick -a #{vm["virtualdev"]} #{vmdk}"
		run "vim-cmd solo/register #{vmx}"
	end

	namespace :power do
		task :getstate do
			getvminfo
			run "vim-cmd vmsvc/power.getstate #{vminfo[:vmid]}"
		end
		task :on do
			getvminfo
			run "vim-cmd vmsvc/power.on #{vminfo[:vmid]}"
		end
		task :off do
			getvminfo
			run "vim-cmd vmsvc/power.off #{vminfo[:vmid]}"
		end
		task :shutdown do
			getvminfo
			run "vim-cmd vmsvc/power.shutdown #{vminfo[:vmid]}"
		end
	end

	namespace :vnc do
		task :enable do
			upload("data/enablevnc.xml", "/etc/vmware/firewall", :via => :scp)
			run "esxcli network firewall refresh"
		end
		task :disable do
			run "rm /etc/vmware/firewall/enablevnc.xml"
			run "esxcli network firewall refresh"
		end
	end

	namespace :ssh do
		task :installkey do
			run "echo #{config['ssh-key']} > /etc/ssh/keys-root/authorized_keys"
		end
	end

end
